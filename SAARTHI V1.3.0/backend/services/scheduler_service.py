from datetime import datetime, timezone, timedelta
from core.tz import now as ist_now
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from models.models import Task, ScheduledSlot, TaskStatus
import uuid


def _now():
    return ist_now()


# ── Energy curve ──────────────────────────────────────────────────────────────
# Default energy by hour (0-23). 0=midnight, 9=morning peak, 14=post-lunch dip
# This gets replaced by LSTM predictions in Phase 2.

DEFAULT_ENERGY = {
    0: 0.1, 1: 0.1, 2: 0.1, 3: 0.1, 4: 0.1, 5: 0.2,
    6: 0.4, 7: 0.5, 8: 0.7, 9: 0.9, 10: 1.0, 11: 0.9,
    12: 0.7, 13: 0.5, 14: 0.4, 15: 0.6, 16: 0.7, 17: 0.7,
    18: 0.6, 19: 0.5, 20: 0.4, 21: 0.3, 22: 0.2, 23: 0.1,
}

ENERGY_REQUIREMENT = {
    "very_low": 0.2,
    "low"     : 0.4,
    "medium"  : 0.6,
    "high"    : 0.8,
    "peak"    : 1.0,
}


async def get_booked_slots(
    user_id: uuid.UUID,
    date: datetime,
    db: AsyncSession,
) -> list[tuple[datetime, datetime]]:
    """Return all active booked slots for a user on a given date."""
    day_start = date.replace(hour=0,  minute=0,  second=0,  microsecond=0)
    day_end   = date.replace(hour=23, minute=59, second=59, microsecond=0)

    result = await db.execute(
        select(ScheduledSlot).where(
            ScheduledSlot.user_id        == user_id,
            ScheduledSlot.is_active      == True,
            ScheduledSlot.scheduled_start >= day_start,
            ScheduledSlot.scheduled_end   <= day_end,
        ).order_by(ScheduledSlot.scheduled_start)
    )
    slots = result.scalars().all()
    return [(s.scheduled_start, s.scheduled_end) for s in slots]


def find_free_gaps(
    booked    : list[tuple[datetime, datetime]],
    date      : datetime,
    work_start: int = 8,
    work_end  : int = 22,
) -> list[tuple[datetime, datetime]]:
    """
    Find free time gaps in a day given booked slots.
    Returns list of (gap_start, gap_end) tuples.
    Work hours: 08:00 — 22:00 by default.
    """
    day_start = date.replace(
        hour=work_start, minute=0, second=0, microsecond=0
    )
    day_end = date.replace(
        hour=work_end, minute=0, second=0, microsecond=0
    )

    # Sort booked slots
    booked_sorted = sorted(booked, key=lambda x: x[0])

    gaps = []
    cursor = day_start

    for slot_start, slot_end in booked_sorted:
        if slot_start > cursor:
            gaps.append((cursor, slot_start))
        cursor = max(cursor, slot_end)

    # Gap after last booking until end of work day
    if cursor < day_end:
        gaps.append((cursor, day_end))

    return gaps


def score_slot(
    gap_start          : datetime,
    task               : Task,
    completion_prob    : float = 0.5,
    procrastination_risk: float = 0.3,
) -> float:
    """
    Score a time slot for a task. Higher = better fit.

    Components:
      energy_match    (35%) — does slot energy match task requirement?
      deadline_urgency(25%) — how close is the deadline?
      ml_score        (25%) — XGBoost completion probability
      proc_penalty    (15%) — penalise high procrastination risk
    """
    # Energy match
    hour         = gap_start.hour
    slot_energy  = DEFAULT_ENERGY.get(hour, 0.5)
    task_energy  = ENERGY_REQUIREMENT.get(task.energy_requirement.value, 0.6)
    energy_match = 1.0 - abs(slot_energy - task_energy)

    # Deadline urgency — higher score if deadline is soon
    if task.deadline:
        hours_left       = max((task.deadline - _now()).total_seconds() / 3600, 0)
        deadline_urgency = 1.0 / (1.0 + hours_left / 24)
    else:
        deadline_urgency = 0.3   # no deadline — low urgency

    # ML scores
    ml_score     = completion_prob
    proc_penalty = 1.0 - procrastination_risk

    # Weighted composite
    score = (
        energy_match     * 0.35 +
        deadline_urgency * 0.25 +
        ml_score         * 0.25 +
        proc_penalty     * 0.15
    )
    return round(score * 100, 1)   # 0–100


async def suggest_slots(
    task_id            : uuid.UUID,
    user_id            : uuid.UUID,
    date               : datetime,
    db                 : AsyncSession,
    completion_prob    : float = 0.5,
    procrastination_risk: float = 0.3,
    max_suggestions    : int = 3,
) -> list[dict]:
    """
    Main entry point — suggest best time slots for a task on a given date.
    Returns up to max_suggestions ranked slot suggestions.
    """
    # Load task
    result = await db.execute(
        select(Task).where(
            Task.id      == task_id,
            Task.user_id == user_id,
        )
    )
    task = result.scalar_one_or_none()
    if task is None:
        raise ValueError("Task not found")

    if task.status not in (
        TaskStatus.DRAFT, TaskStatus.SCHEDULED,
        TaskStatus.POSTPONED, TaskStatus.PARTIALLY_DONE
    ):
        raise ValueError(
            f"Task status is {task.status.value} — cannot schedule"
        )

    # Get booked slots for the day
    booked = await get_booked_slots(user_id, date, db)

    # Find free gaps
    gaps = find_free_gaps(booked, date)

    # Filter gaps that fit the task duration
    duration_minutes = task.estimated_duration
    valid_gaps = [
        (start, end) for start, end in gaps
        if (end - start).total_seconds() / 60 >= duration_minutes
    ]

    if not valid_gaps:
        return []

    # Score each gap
    suggestions = []
    for gap_start, gap_end in valid_gaps:
        slot_end = gap_start + timedelta(minutes=duration_minutes)
        score    = score_slot(
            gap_start,
            task,
            completion_prob,
            procrastination_risk,
        )

        hour = gap_start.hour
        energy_label = (
            "peak"     if DEFAULT_ENERGY.get(hour, 0) >= 0.8 else
            "high"     if DEFAULT_ENERGY.get(hour, 0) >= 0.6 else
            "medium"   if DEFAULT_ENERGY.get(hour, 0) >= 0.4 else
            "low"
        )

        suggestions.append({
            "slot_start"    : gap_start.isoformat(),
            "slot_end"      : slot_end.isoformat(),
            "score"         : score,
            "energy_level"  : energy_label,
            "reasoning"     : _build_reasoning(
                score, hour, energy_label,
                task, completion_prob, procrastination_risk,
            ),
        })

    # Sort by score descending
    suggestions.sort(key=lambda x: x["score"], reverse=True)
    return suggestions[:max_suggestions]


async def book_slot(
    task_id     : uuid.UUID,
    user_id     : uuid.UUID,
    slot_start  : datetime,
    slot_end    : datetime,
    db          : AsyncSession,
    created_by  : str = "ai",
) -> ScheduledSlot:
    """
    Book a slot for a task.
    Checks for conflicts before saving.
    """
    # Conflict check
    result = await db.execute(
        select(ScheduledSlot).where(
            ScheduledSlot.user_id   == user_id,
            ScheduledSlot.is_active == True,
            ScheduledSlot.scheduled_start < slot_end,
            ScheduledSlot.scheduled_end   > slot_start,
        )
    )
    conflict = result.scalar_one_or_none()
    if conflict:
        raise ValueError(
            f"Slot conflicts with an existing booking "
            f"({conflict.scheduled_start} — {conflict.scheduled_end})"
        )

    slot = ScheduledSlot(
        user_id         = user_id,
        task_id         = task_id,
        scheduled_start = slot_start,
        scheduled_end   = slot_end,
        is_active       = True,
        created_by      = created_by,
    )
    db.add(slot)
    await db.commit()
    await db.refresh(slot)
    return slot


async def get_day_schedule(
    user_id : uuid.UUID,
    date    : datetime,
    db      : AsyncSession,
) -> list[dict]:
    """Return full day schedule with task details."""
    day_start = date.replace(hour=0,  minute=0,  second=0,  microsecond=0)
    day_end   = date.replace(hour=23, minute=59, second=59, microsecond=0)

    result = await db.execute(
        select(ScheduledSlot, Task)
        .join(Task, Task.id == ScheduledSlot.task_id)
        .where(
            ScheduledSlot.user_id        == user_id,
            ScheduledSlot.is_active      == True,
            ScheduledSlot.scheduled_start >= day_start,
            ScheduledSlot.scheduled_end   <= day_end,
        )
        .order_by(ScheduledSlot.scheduled_start)
    )
    rows = result.all()

    return [
        {
            "slot_id"   : str(slot.id),
            "task_id"   : str(slot.task_id),
            "title"     : task.title,
            "category"  : task.category.value,
            "priority"  : task.priority,
            "start"     : slot.scheduled_start.isoformat(),
            "end"       : slot.scheduled_end.isoformat(),
            "created_by": slot.created_by,
            "status"    : task.status.value,
            # From the parent task, not the slot — what the user asked for when
            # creating it, so they can compare it against where it landed.
            "estimated_duration": task.estimated_duration,
            "deadline"  : task.deadline.isoformat() if task.deadline else None,
        }
        for slot, task in rows
    ]


def _build_reasoning(
    score       : float,
    hour        : int,
    energy_label: str,
    task        : Task,
    comp_prob   : float,
    proc_risk   : float,
) -> str:
    parts = []

    if energy_label in ("peak", "high"):
        parts.append(f"{hour:02d}:00 is a high-energy window")
    elif energy_label == "low":
        parts.append(f"{hour:02d}:00 is a low-energy window — consider a lighter task")

    if task.deadline:
        hours_left = (task.deadline - _now()).total_seconds() / 3600
        if hours_left < 24:
            parts.append(f"deadline in {hours_left:.0f}h — urgent")
        elif hours_left < 72:
            parts.append(f"deadline in {hours_left:.0f}h")

    if comp_prob >= 0.7:
        parts.append(f"ML predicts {comp_prob*100:.0f}% completion probability")
    if proc_risk >= 0.6:
        parts.append("high procrastination risk — schedule early in the day")

    parts.append(f"score {score}/100")
    return " · ".join(parts)