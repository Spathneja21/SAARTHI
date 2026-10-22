"""The whole RL loop, end to end, against the live dev DB.

    plan -> one feedback row per slot -> user moves one -> tasks resolve
         -> nightly reward job -> the policy's training data and its fit

test_slot_bandit.py covers the model's maths without a database; this covers
the plumbing around it (Phase 0, plus Phase 1's query).

Like test_replan.py, it confines itself to a throwaway user_id and deletes its
rows afterwards. One exception: it runs the real update_rl_rewards job, which
scores every user's resolved-but-unscored rows — exactly what the nightly run
would do to them anyway.
"""
import asyncio
import uuid
from datetime import timedelta
from types import SimpleNamespace

from sqlalchemy import delete, select

from core.database import AsyncSessionLocal, engine
from core.tz import now as ist_now
from main import api_user_moved_slot
from ml.slot_bandit import SlotPolicy, fit_posterior
from models.models import (
    EnergyLevel, ScheduledSlot, SlotPreferenceFeedback, Task, TaskCategory,
    TaskEvent, TaskStatus,
)
from schemas.schemas import MoveSlotRequest
from services.cpsat_bridge import (
    load_slot_observations, run_cpsat_schedule, sample_slot_policy,
)
from services.task_service import create_task, transition_task
from workers.tasks import update_rl_rewards

USER = uuid.uuid4()
MEDIUM = 0.6            # ENERGY_REQUIREMENT["medium"]


async def _feedback(db, task_id):
    """This task's feedback rows, re-read from the DB, not the session cache."""
    result = await db.execute(
        select(SlotPreferenceFeedback)
        .where(
            SlotPreferenceFeedback.user_id == USER,
            SlotPreferenceFeedback.task_id == task_id,
        )
        .execution_options(populate_existing=True)
    )
    return result.scalars().all()


async def _move(db, slot, new_start):
    return await api_user_moved_slot(
        MoveSlotRequest(slot_id=slot.id, new_start=new_start,
                        new_end=new_start + timedelta(minutes=60)),
        db=db, current_user=SimpleNamespace(id=USER),
    )


async def _plan_move_resolve():
    """Up to the point the nightly job takes over. Returns (kept_id, moved_id)."""
    try:
        async with AsyncSessionLocal() as db:
            # Same category and energy, so the only thing separating the two
            # tasks' outcomes, as far as the model can tell, is the hour.
            deadline = ist_now() + timedelta(days=2)
            kept, moved = [
                await create_task(
                    user_id=USER, title=title, category=TaskCategory.DEEP_WORK,
                    energy_requirement=EnergyLevel.MEDIUM, estimated_duration=60,
                    priority=5, deadline=deadline, db=db,
                )
                for title in ("rl test: kept", "rl test: moved")
            ]

            result = await run_cpsat_schedule(USER, db)
            assert len(result["scheduled"]) == 2, result

            # Phase 0 #1 — a placed task leaves DRAFT, or it can never resolve.
            for t in (kept, moved):
                await db.refresh(t)
                assert t.status == TaskStatus.SCHEDULED, t.status

            # Phase 0 #2 — every placed slot logs its suggestion: kept by
            # default, at the slot's own hour, with a real score, unrewarded.
            slots = {
                s.task_id: s for s in (await db.execute(
                    select(ScheduledSlot).where(
                        ScheduledSlot.user_id == USER,
                        ScheduledSlot.is_active == True,        # noqa: E712
                    )
                )).scalars().all()
            }
            for t in (kept, moved):
                [fb] = await _feedback(db, t.id)
                assert fb.was_kept and fb.reward is None
                assert fb.suggested_start == slots[t.id].scheduled_start
                assert fb.hour_of_day == slots[t.id].scheduled_start.hour
                assert fb.suggested_score > 0

            # Phase 0 #2/#3 — a move flips that same row instead of adding a
            # second one, and the rejection stays on the *suggested* hour.
            suggested_hour = slots[moved.id].scheduled_start.hour
            first = slots[moved.id].scheduled_start + timedelta(hours=3)
            assert (await _move(db, slots[moved.id], first))["preference_recorded"]
            [fb] = await _feedback(db, moved.id)
            assert not fb.was_kept
            assert fb.user_chosen_start == first
            assert fb.hour_of_day == suggested_hour

            # Moving it again still finds the row (by user_chosen_start now).
            second = first + timedelta(hours=1)
            assert (await _move(db, slots[moved.id], second))["preference_recorded"]
            [fb] = await _feedback(db, moved.id)
            assert fb.user_chosen_start == second and fb.hour_of_day == suggested_hour

            # A hand-booked slot was never AURA's suggestion: nothing to judge.
            manual = ScheduledSlot(
                user_id=USER, task_id=kept.id, created_by="user", is_active=True,
                scheduled_start=slots[kept.id].scheduled_start + timedelta(days=1, hours=1),
                scheduled_end=slots[kept.id].scheduled_end + timedelta(days=1, hours=1),
            )
            db.add(manual)
            await db.commit()
            resp = await _move(db, manual, manual.scheduled_start + timedelta(hours=1))
            assert resp["preference_recorded"] is False
            [fb] = await _feedback(db, kept.id)
            assert fb.was_kept, "moving a hand-booked slot touched AURA's row"

            # Resolve both, so the reward job has outcomes to score.
            await transition_task(moved.id, USER, TaskStatus.IN_PROGRESS, db)
            await transition_task(moved.id, USER, TaskStatus.COMPLETED, db)
            await transition_task(kept.id, USER, TaskStatus.ABANDONED, db)
            return kept.id, moved.id
    finally:
        # Pooled asyncpg connections are bound to this event loop; the next
        # asyncio.run() gets a new one and would fail to reuse them.
        await engine.dispose()


async def _check_rewards_and_policy(kept_id, moved_id):
    try:
        async with AsyncSessionLocal() as db:
            # Phase 0 #4 — rewards follow the resolved outcome.
            [k] = await _feedback(db, kept_id)
            [m] = await _feedback(db, moved_id)
            assert (k.reward, k.was_completed) == (-5.0, False), (k.reward, k.was_completed)
            assert (m.reward, m.was_completed) == (10.0, True), (m.reward, m.was_completed)

            # Phase 1 — the policy trains on exactly those two rows, each at
            # the hour AURA suggested.
            observations = await load_slot_observations(USER, db)
            assert sorted((o.hour, o.reward) for o in observations) == sorted(
                [(k.hour_of_day, -5.0), (m.hour_of_day, 10.0)]
            ), observations

            # With identical context, a ridge fit on two points always ranks
            # the rewarded hour above the penalised one; it can't tell them
            # apart only if CP-SAT put both at the same hour.
            mean = SlotPolicy(fit_posterior(observations, ist_now()).mean).bias(MEDIUM)
            if m.hour_of_day != k.hour_of_day:
                assert mean[m.hour_of_day] > mean[k.hour_of_day], mean
            else:
                print(f"note: both tasks landed at {k.hour_of_day}:00, ranking not checked")

            bias = (await sample_slot_policy(USER, db)).bias(MEDIUM)
            assert set(bias) == set(range(24))
            assert all(-1.0 <= v <= 1.0 for v in bias.values())
    finally:
        await engine.dispose()


async def _cleanup():
    try:
        async with AsyncSessionLocal() as db:
            for model in (SlotPreferenceFeedback, ScheduledSlot, TaskEvent, Task):
                await db.execute(delete(model).where(model.user_id == USER))
            await db.commit()
    finally:
        await engine.dispose()


def test_rl_loop_end_to_end():
    try:
        kept_id, moved_id = asyncio.run(_plan_move_resolve())
        # A Celery task called directly runs inline, in its own event loop, so
        # it has to sit between asyncio.run() calls rather than inside one.
        update_rl_rewards()
        asyncio.run(_check_rewards_and_policy(kept_id, moved_id))
    finally:
        asyncio.run(_cleanup())


if __name__ == "__main__":
    test_rl_loop_end_to_end()
    print("ok")
