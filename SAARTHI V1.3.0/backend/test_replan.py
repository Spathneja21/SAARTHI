"""Re-planning must not evict existing tasks past their deadlines.

The bug: load_fixed_events blocked every active ScheduledSlot, including the
slots of the tasks being re-planned. Each task was walled off from its own
current time, shoved to the next day past its deadline, and its old slot was
deactivated moments later -- leaving the day looking empty.

Runs against the live dev DB but confines itself to a throwaway user_id
(no FK constraints exist, so no users row is needed) and deletes its own
rows afterwards.
"""
import asyncio
import uuid
from datetime import datetime, timedelta

from sqlalchemy import delete, select

from core.database import AsyncSessionLocal, engine
from core.tz import now as ist_now
from models.models import (
    EnergyLevel, ScheduledSlot, Task, TaskCategory, TaskEvent,
)
from services.cpsat_bridge import load_fixed_events, run_cpsat_schedule
from services.task_service import create_task

FOUR = [
    ("sahil ka bday", 90, 7, TaskCategory.PERSONAL, EnergyLevel.MEDIUM),
    ("Robotics task", 75, 7, TaskCategory.DEEP_WORK, EnergyLevel.HIGH),
    ("Yoga", 60, 8, TaskCategory.HEALTH, EnergyLevel.LOW),
    ("Capstone work", 75, 10, TaskCategory.DEEP_WORK, EnergyLevel.PEAK),
]
FIFTH = ("ashmeen ka bday", 20, 10, TaskCategory.PERSONAL, EnergyLevel.HIGH)


def _late(result, deadline):
    return [
        s for s in result["scheduled"]
        if datetime.fromisoformat(s["end"]) > deadline
    ]


async def _run():
    user_id = uuid.uuid4()          # isolated namespace, cleaned up below
    # Generous deadline: this test is about eviction, not deadline feasibility.
    deadline = ist_now() + timedelta(days=2)

    try:
        async with AsyncSessionLocal() as db:
            for title, dur, prio, cat, energy in FOUR:
                await create_task(
                    user_id=user_id, title=title, category=cat,
                    energy_requirement=energy, estimated_duration=dur,
                    priority=prio, deadline=deadline, db=db,
                )
            run1 = await run_cpsat_schedule(user_id, db)
            assert len(run1["scheduled"]) >= 4, run1

            title, dur, prio, cat, energy = FIFTH
            await create_task(
                user_id=user_id, title=title, category=cat,
                energy_requirement=energy, estimated_duration=dur,
                priority=prio, deadline=deadline, db=db,
            )
            run2 = await run_cpsat_schedule(user_id, db)

            # All five re-planned together...
            titles = {s["title"] for s in run2["scheduled"]}
            assert titles == {t[0] for t in FOUR} | {FIFTH[0]}, (
                f"expected all 5 tasks re-planned, got {titles}"
            )

            # ...and nothing past its deadline.
            late = _late(run2, deadline)
            assert not late, "re-plan pushed tasks past their deadline: " + ", ".join(
                f"{s['title']} ends {s['end']}" for s in late
            )

            # The core of the fix, asserted directly: a task being re-planned
            # must not appear in its own blocked calendar. Checked here rather
            # than via solver output, which also moves for unrelated reasons
            # (there is no earliness term, so equally-optimal plans drift).
            task_ids = {
                t.id for t in
                (await db.execute(select(Task).where(Task.user_id == user_id)))
                .scalars().all()
            }
            blocked = await load_fixed_events(user_id, db, exclude_task_ids=task_ids)
            titles_blocked = {e.title for e in blocked}
            assert not any(t.startswith("slot_") for t in titles_blocked), (
                "a task being re-planned is still blocking itself: "
                f"{[t for t in titles_blocked if t.startswith('slot_')]}"
            )

            # Sanity: without the exclusion those slots *are* blocked, so the
            # assertion above is actually testing something.
            unfiltered = await load_fixed_events(user_id, db)
            assert any(e.title.startswith("slot_") for e in unfiltered), (
                "expected un-excluded slots to be blocked — test is vacuous"
            )
    finally:
        async with AsyncSessionLocal() as db:
            for model in (ScheduledSlot, TaskEvent, Task):
                await db.execute(delete(model).where(model.user_id == user_id))
            await db.commit()
        # Pooled asyncpg connections are bound to this event loop; the next
        # asyncio.run() gets a new one and would fail to reuse them.
        await engine.dispose()


def test_replan_does_not_evict_past_deadline():
    asyncio.run(_run())


async def _run_chunks():
    """Every chunk of a split task must survive the save.

    save_assignments used to deactivate old slots inside the per-assignment
    loop; autoflush meant chunk 1's query matched the slot chunk 0 had just
    inserted and retired it, so only the final chunk stayed active and the
    booked time came out far below the estimate.
    """
    user_id = uuid.uuid4()
    minutes = 180                       # long enough to force a split
    deadline = ist_now().replace(hour=23, minute=0, second=0, microsecond=0)

    try:
        async with AsyncSessionLocal() as db:
            await create_task(
                user_id=user_id, title="long task", category=TaskCategory.LEARNING,
                energy_requirement=EnergyLevel.MEDIUM, estimated_duration=minutes,
                priority=8, deadline=deadline, db=db,
            )
            result = await run_cpsat_schedule(user_id, db)
            planned = len(result["scheduled"])
            assert planned > 1, f"expected the task to be split, got {planned} chunk(s)"

            rows = (await db.execute(
                select(ScheduledSlot).where(
                    ScheduledSlot.user_id == user_id,
                    ScheduledSlot.is_active == True,        # noqa: E712
                )
            )).scalars().all()
            assert len(rows) == planned, (
                f"CP-SAT planned {planned} chunks but {len(rows)} slot(s) stayed active"
            )

            booked = sum(
                (r.scheduled_end - r.scheduled_start).total_seconds() / 60 for r in rows
            )
            assert booked == minutes, f"booked {booked} min but estimated {minutes} min"
    finally:
        async with AsyncSessionLocal() as db:
            for model in (ScheduledSlot, TaskEvent, Task):
                await db.execute(delete(model).where(model.user_id == user_id))
            await db.commit()
        # Pooled asyncpg connections are bound to this event loop; the next
        # asyncio.run() gets a new one and would fail to reuse them.
        await engine.dispose()


def test_all_chunks_persist():
    asyncio.run(_run_chunks())


if __name__ == "__main__":
    test_replan_does_not_evict_past_deadline()
    test_all_chunks_persist()
    print("ok")
