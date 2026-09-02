from datetime import datetime, timezone
from core.tz import now as ist_now
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from models.models import Task, TaskEvent, TaskStatus, TaskCategory, EnergyLevel


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
               to_status: TaskStatus, reason: str = None,
               stress_score: int = None) -> TaskEvent:
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
                          db: AsyncSession, reason: str = None,
                          stress_score: int = None) -> Task:
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