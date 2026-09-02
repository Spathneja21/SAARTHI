from datetime import datetime, timezone
from core.tz import now as ist_now
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from models.models import (
    Task, TaskEvent, StressLog,
    UserBehaviorProfile, TaskStatus,
)


def _now():
    return ist_now()


async def build_behavior_profile(
    user_id: object,
    db: AsyncSession,
) -> UserBehaviorProfile:
    """
    Aggregate all task and event data into a UserBehaviorProfile.
    Creates or updates the profile row for this user.
    """
    now = _now()

    # ── Task counts ───────────────────────────────────────────────────────────
    total_result = await db.execute(
        select(func.count(Task.id)).where(Task.user_id == user_id)
    )
    total = total_result.scalar() or 0

    completed_result = await db.execute(
        select(func.count(Task.id)).where(
            Task.user_id == user_id,
            Task.status  == TaskStatus.COMPLETED,
        )
    )
    completed = completed_result.scalar() or 0

    abandoned_result = await db.execute(
        select(func.count(Task.id)).where(
            Task.user_id == user_id,
            Task.status  == TaskStatus.ABANDONED,
        )
    )
    abandoned = abandoned_result.scalar() or 0

    completion_rate = round(completed / total, 4) if total > 0 else 0.0

    # ── Estimation accuracy ───────────────────────────────────────────────────
    # actual_duration - estimated_duration for completed tasks
    tasks_result = await db.execute(
        select(Task).where(
            Task.user_id        == user_id,
            Task.status         == TaskStatus.COMPLETED,
            Task.actual_duration.is_not(None),
        )
    )
    completed_tasks = tasks_result.scalars().all()

    estimation_errors = [
        t.actual_duration - t.estimated_duration
        for t in completed_tasks
        if t.actual_duration and t.estimated_duration
    ]
    avg_error = round(
        sum(estimation_errors) / len(estimation_errors), 2
    ) if estimation_errors else 0.0

    # ── Procrastination averages ──────────────────────────────────────────────
    all_tasks_result = await db.execute(
        select(Task).where(Task.user_id == user_id)
    )
    all_tasks = all_tasks_result.scalars().all()

    avg_proc = round(
        sum(t.procrastination_count for t in all_tasks) / len(all_tasks), 2
    ) if all_tasks else 0.0

    avg_resc = round(
        sum(t.reschedule_count for t in all_tasks) / len(all_tasks), 2
    ) if all_tasks else 0.0

    avg_skip = round(
        sum(t.skip_count for t in all_tasks) / len(all_tasks), 2
    ) if all_tasks else 0.0

    # ── Peak focus hours ──────────────────────────────────────────────────────
    # Find the hour with most completions
    completions_by_hour_result = await db.execute(
        select(
            TaskEvent.hour_of_day,
            func.count(TaskEvent.id).label("count"),
        )
        .where(
            TaskEvent.user_id    == user_id,
            TaskEvent.event_type == "task_completed",
            TaskEvent.hour_of_day.is_not(None),
        )
        .group_by(TaskEvent.hour_of_day)
        .order_by(func.count(TaskEvent.id).desc())
        .limit(1)
    )
    peak_row = completions_by_hour_result.one_or_none()
    peak_hour = peak_row.hour_of_day if peak_row else None

    # ── Most procrastinated category ──────────────────────────────────────────
    proc_by_category_result = await db.execute(
        select(
            Task.category,
            func.sum(Task.procrastination_count).label("total_proc"),
        )
        .where(Task.user_id == user_id)
        .group_by(Task.category)
        .order_by(func.sum(Task.procrastination_count).desc())
        .limit(1)
    )
    proc_cat_row = proc_by_category_result.one_or_none()
    most_proc_category = proc_cat_row.category.value if proc_cat_row else None

    # ── Upsert profile ────────────────────────────────────────────────────────
    existing = await db.execute(
        select(UserBehaviorProfile).where(
            UserBehaviorProfile.user_id == user_id
        )
    )
    profile = existing.scalar_one_or_none()

    if profile is None:
        profile = UserBehaviorProfile(user_id=user_id)
        db.add(profile)

    profile.total_tasks_created          = total
    profile.total_tasks_completed        = completed
    profile.total_tasks_abandoned        = abandoned
    profile.completion_rate              = completion_rate
    profile.avg_estimation_error_minutes = avg_error
    profile.avg_procrastination_count    = avg_proc
    profile.avg_reschedule_count         = avg_resc
    profile.avg_skip_count               = avg_skip
    profile.peak_focus_hour_start        = peak_hour
    profile.peak_focus_hour_end          = (peak_hour + 2) if peak_hour else None
    profile.most_procrastinated_category = most_proc_category
    profile.last_updated                 = now

    await db.commit()
    await db.refresh(profile)
    return profile


async def get_behavior_profile(
    user_id: object,
    db: AsyncSession,
) -> UserBehaviorProfile | None:
    result = await db.execute(
        select(UserBehaviorProfile).where(
            UserBehaviorProfile.user_id == user_id
        )
    )
    return result.scalar_one_or_none()