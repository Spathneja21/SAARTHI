from collections import deque
from datetime import datetime, timezone
from core.tz import now as ist_now
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from models.models import (
    Task, TaskEvent, TaskStatus, TaskCategory, EnergyLevel, ScheduledSlot,
)


# ── Valid transitions ──────────────────────────────────────────────────────────

VALID_TRANSITIONS = {
    TaskStatus.DRAFT:          {TaskStatus.SCHEDULED, TaskStatus.ABANDONED},
    TaskStatus.SCHEDULED:      {TaskStatus.IN_PROGRESS, TaskStatus.POSTPONED,
                                TaskStatus.SKIPPED, TaskStatus.ABANDONED},
    TaskStatus.IN_PROGRESS:    {TaskStatus.PAUSED, TaskStatus.COMPLETED,
                                TaskStatus.PARTIALLY_DONE, TaskStatus.ABANDONED},
    TaskStatus.PAUSED:         {TaskStatus.IN_PROGRESS, TaskStatus.POSTPONED,
                                TaskStatus.ABANDONED},
    TaskStatus.POSTPONED:      {TaskStatus.SCHEDULED, TaskStatus.ABANDONED},
    TaskStatus.SKIPPED:        {TaskStatus.SCHEDULED},
    TaskStatus.PARTIALLY_DONE: {TaskStatus.SCHEDULED, TaskStatus.COMPLETED,
                                TaskStatus.ABANDONED},
    TaskStatus.COMPLETED:      set(),
    TaskStatus.ABANDONED:      {TaskStatus.DRAFT},
}


def _now():
    return ist_now()


def _log_event(task: Task, from_status: TaskStatus,
               to_status: TaskStatus, reason: str | None = None,
               stress_score: int | None = None) -> TaskEvent:
    now = _now()
    return TaskEvent(
        task_id     = task.id,
        user_id     = task.user_id,
        event_type  = f"task_{to_status.value}",
        from_status = from_status.value,
        to_status   = to_status.value,
        reason      = reason,
        hour_of_day = now.hour,
        day_of_week = now.weekday(),   # 0=Monday, 6=Sunday
        stress_score= stress_score,
        occurred_at = now,
    )


async def create_task(user_id, title, category, energy_requirement,
                      estimated_duration, priority, deadline,
                      db: AsyncSession) -> Task:
    now = _now()
    task = Task(
        user_id            = user_id,
        title              = title,
        category           = category,
        energy_requirement = energy_requirement,
        estimated_duration = estimated_duration,
        priority           = priority,
        deadline           = deadline,
        status             = TaskStatus.DRAFT,
        created_at         = now,
        updated_at         = now,
    )
    db.add(task)
    await db.flush()   # get task.id before creating event

    # Log creation event
    event = TaskEvent(
        task_id     = task.id,
        user_id     = task.user_id,
        event_type  = "task_created",
        from_status = None,
        to_status   = TaskStatus.DRAFT.value,
        hour_of_day = now.hour,
        day_of_week = now.weekday(),
        occurred_at = now,
    )
    db.add(event)
    await db.commit()
    await db.refresh(task)
    return task


async def get_task(task_id, user_id, db: AsyncSession) -> Task | None:
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == user_id)
    )
    return result.scalar_one_or_none()


async def list_tasks(user_id, db: AsyncSession) -> list[Task]:
    result = await db.execute(
        select(Task)
        .where(Task.user_id == user_id)
        .order_by(Task.created_at.desc())
    )
    return list(result.scalars().all())


async def get_task_history(task_id, user_id, db: AsyncSession) -> list[TaskEvent]:
    # Ownership check
    task = await get_task(task_id, user_id, db)
    if task is None:
        raise ValueError("Task not found")

    result = await db.execute(
        select(TaskEvent)
        .where(TaskEvent.task_id == task_id)
        .order_by(TaskEvent.occurred_at.asc())
    )
    return list(result.scalars().all())


async def transition_task(task_id, user_id, to_status: TaskStatus,
                          db: AsyncSession, reason: str | None = None,
                          stress_score: int | None = None) -> Task:
    task = await get_task(task_id, user_id, db)
    if task is None:
        raise ValueError("Task not found")

    allowed = VALID_TRANSITIONS.get(task.status, set())
    if to_status not in allowed:
        raise ValueError(
            f"Cannot move {task.status.value} → {to_status.value}. "
            f"Allowed: {[s.value for s in allowed]}"
        )

    now         = _now()
    from_status = task.status

    # Side effects
    if to_status == TaskStatus.IN_PROGRESS and task.started_at is None:
        task.started_at = now

    elif to_status == TaskStatus.COMPLETED:
        task.completed_at = now
        if task.started_at:
            task.actual_duration = int((now - task.started_at).total_seconds() / 60)

    elif to_status == TaskStatus.POSTPONED:
        task.procrastination_count += 1

    elif to_status == TaskStatus.SKIPPED:
        task.skip_count            += 1
        task.procrastination_count += 1

    elif to_status == TaskStatus.SCHEDULED:
        if from_status not in (TaskStatus.DRAFT, TaskStatus.POSTPONED, TaskStatus.SKIPPED):
            task.reschedule_count += 1

    elif to_status == TaskStatus.DRAFT:
        task.started_at      = None
        task.completed_at    = None
        task.actual_duration = None

    task.status     = to_status
    task.updated_at = now

    # Log the event
    event = _log_event(task, from_status, to_status, reason, stress_score)
    db.add(event)

    await db.commit()
    await db.refresh(task)
    return task


# ── Editing ────────────────────────────────────────────────────────────────────

async def update_task(task_id, user_id, fields: dict, db: AsyncSession) -> Task:
    """Apply a partial update to a task's descriptive fields.

    Deliberately cannot change `status` — that belongs to `transition_task`, which
    enforces the state machine and writes the event log. Only keys present in
    `fields` are touched, so an omitted key leaves its column alone.
    """
    task = await get_task(task_id, user_id, db)
    if task is None:
        raise ValueError("Task not found")

    editable = {
        "title", "description", "category", "energy_requirement",
        "estimated_duration", "priority", "deadline",
    }
    for key, value in fields.items():
        if key in editable:
            setattr(task, key, value)

    task.updated_at = _now()
    await db.commit()
    await db.refresh(task)
    return task


async def delete_task(task_id, user_id, db: AsyncSession) -> None:
    """Delete a task and deactivate any calendar slots pointing at it.

    Slots are soft-deleted rather than removed, matching how `cpsat_bridge`
    supersedes old plans. Without this the calendar would keep rendering blocks for
    a task that no longer exists, and the scheduler would keep treating that time as
    occupied.
    """
    task = await get_task(task_id, user_id, db)
    if task is None:
        raise ValueError("Task not found")

    await db.execute(
        update(ScheduledSlot)
        .where(
            ScheduledSlot.task_id == task_id,
            ScheduledSlot.is_active == True,   # noqa: E712 — SQL, not Python truthiness
        )
        .values(is_active=False)
    )
    await db.delete(task)
    await db.commit()


# ── Safe multi-step outcomes ───────────────────────────────────────────────────

def _path_to(from_status: TaskStatus, to_status: TaskStatus) -> list[TaskStatus] | None:
    """Shortest legal sequence of statuses from one state to another.

    Breadth-first over VALID_TRANSITIONS rather than a hardcoded route, so the path
    stays correct if the state machine is edited. Returns the intermediate states
    plus the target, or None when the target is unreachable.
    """
    if from_status == to_status:
        return []

    queue = deque([(from_status, [])])
    seen = {from_status}
    while queue:
        current, path = queue.popleft()
        for nxt in VALID_TRANSITIONS.get(current, set()):
            if nxt in seen:
                continue
            new_path = path + [nxt]
            if nxt == to_status:
                return new_path
            seen.add(nxt)
            queue.append((nxt, new_path))
    return None


async def _active_slot_start(task_id, db: AsyncSession) -> datetime | None:
    """Earliest active scheduled start for a task, if it was ever planned."""
    result = await db.execute(
        select(ScheduledSlot.scheduled_start)
        .where(
            ScheduledSlot.task_id == task_id,
            ScheduledSlot.is_active == True,   # noqa: E712
        )
        .order_by(ScheduledSlot.scheduled_start.asc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def resolve_task(task_id, user_id, to_status: TaskStatus,
                       db: AsyncSession, reason: str | None = None) -> Task:
    """Move a task to a terminal-ish outcome, walking the state machine safely.

    The UI offers "done", "postpone" and "skip" as single actions, but the state
    machine forbids most direct jumps — `draft → completed` is illegal, and the
    legal route is `draft → scheduled → in_progress → completed`. Firing those
    transitions from the client would be fragile, and for completion it also
    corrupts `actual_duration`: `transition_task` stamps `started_at = now` on
    entering IN_PROGRESS and then derives `actual_duration = now - started_at` on
    COMPLETED, so a rapid client-side walk records every task as taking ~0 minutes.

    A fabricated zero is worse than a null, because
    `analytics_service.build_behavior_profile` filters on
    `actual_duration IS NOT NULL` — a null is cleanly excluded from the
    estimation-error average, while a zero is treated as a real measurement.

    So `actual_duration` is only kept when it means something. A single "mark done"
    tap cannot tell us how long the work took; only a genuine IN_PROGRESS period
    can, which is exactly what `started_at` records. Therefore:

    - if the task had really been started (`started_at` already set, because the
      user pressed start earlier), the elapsed time is real and is kept;
    - otherwise both `started_at` and `actual_duration` are left NULL — "unknown"
      rather than a guess.

    An earlier version of this function seeded `started_at` from the task's
    scheduled slot. That was wrong: a slot is usually in the *future*, so
    `now - started_at` came out **negative** (observed: -932 minutes on a 60-minute
    task), which is worse than the zero it was meant to avoid.
    """
    task = await get_task(task_id, user_id, db)
    if task is None:
        raise ValueError("Task not found")

    if task.status == to_status:
        return task   # idempotent: safe for a mobile client retrying a request

    path = _path_to(task.status, to_status)
    if path is None:
        raise ValueError(
            f"No legal path from {task.status.value} → {to_status.value}."
        )

    # Captured before the walk, which will itself set started_at on the synthetic
    # IN_PROGRESS step. Only a pre-existing value reflects real work.
    was_really_started = task.started_at is not None

    for index, step in enumerate(path):
        is_final = index == len(path) - 1
        step_reason = reason if is_final else f"auto-step toward {to_status.value}"
        task = await transition_task(
            task_id      = task_id,
            user_id      = user_id,
            to_status    = step,
            db           = db,
            reason       = step_reason,
        )

    if to_status == TaskStatus.COMPLETED and not was_really_started:
        task.started_at      = None
        task.actual_duration = None
        await db.commit()
        await db.refresh(task)

    return task