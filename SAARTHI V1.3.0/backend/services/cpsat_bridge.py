"""
AURA ↔ Saarthi CP-SAT Bridge

Responsibility split:
  saarthi/  → constraint solving: fits chunks into free windows,
               respects deadlines, handles splitting, no-overlap
  AURA      → behavioral scoring: energy match, ML predictions,
               procrastination risk, user profile

Flow:
  1. Load AURA tasks from PostgreSQL
  2. Convert → saarthi Task objects
  3. Load calendar blocks from scheduled_slots table
  4. Run saarthi Scheduler → Plan
  5. Score each Assignment with AURA behavioral signals
  6. Save scored assignments to scheduled_slots table
  7. Return enriched schedule to API
"""
from __future__ import annotations

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import json
from datetime import datetime, time, timezone, timedelta
from core.tz import IST, now as ist_now
from uuid import UUID
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from models.models import Task as AURATask, ScheduledSlot, TaskStatus
from saarthi.Models import (
    Task as SaarthiTask,
    FixedEvent,
    Chunk,
    Assignment,
)
from saarthi.scheduler import Scheduler
from saarthi.config import DEFAULT_CONFIG, SchedulerConfig

from ml.ml_train import predict_completion
from ml.lgbm_train import predict_procrastination_risk


# ── Energy curve (default until LSTM is trained) ─────────────────────────────

DEFAULT_ENERGY = {
    6: 0.4, 7: 0.5, 8: 0.7, 9: 0.9, 10: 1.0, 11: 0.9,
    12: 0.7, 13: 0.5, 14: 0.4, 15: 0.6, 16: 0.7, 17: 0.7,
    18: 0.6, 19: 0.5, 20: 0.4, 21: 0.3, 22: 0.2, 23: 0.1,
}

ENERGY_REQUIREMENT = {
    "very_low": 0.2, "low": 0.4, "medium": 0.6,
    "high": 0.8,     "peak": 1.0,
}

CATEGORY_MAP = {
    "deep_work": 0, "admin": 1, "learning": 2,
    "meeting": 3,   "personal": 4, "health": 5,
}

ENERGY_MAP = {
    "very_low": 0, "low": 1, "medium": 2, "high": 3, "peak": 4,
}

# CP-SAT builds its grid outward from `now` (horizon_start), so every slot
# inherits that instant's minutes and seconds — hence times like 17:57:11.
# Anchoring `now` to a clean boundary makes every derived slot land on one
# too, without rounding assignments afterwards (which could nudge a chunk
# into a class or its neighbour).
SLOT_ROUNDING_MINUTES = 5


def round_up_to(dt: datetime, minutes: int = SLOT_ROUNDING_MINUTES) -> datetime:
    """Smallest `minutes`-aligned wall-clock time at or after `dt`."""
    aligned = dt.replace(second=0, microsecond=0)
    if aligned != dt:               # any seconds at all push us to the next mark
        aligned += timedelta(minutes=1)
    overshoot = aligned.minute % minutes
    if overshoot:
        aligned += timedelta(minutes=minutes - overshoot)
    return aligned


# ── Step 1+2: Convert AURA tasks → Saarthi Task objects ──────────────────────

def aura_task_to_saarthi(
    task: AURATask,
    focus_limit_minutes: int = 90,
) -> SaarthiTask:
    """
    Map an AURA PostgreSQL Task to a Saarthi Task.
    focus_limit_minutes: max continuous work before a break.
    Deep work gets 90 min, admin/personal get 60 min.
    """
    focus_limits = {
        "deep_work": 90, "learning": 90, "meeting": 90,
        "admin": 90,     "personal": 90, "health": 90,
    }
    focus = focus_limits.get(task.category.value, 60)

    # Deadline: if no deadline set, default to 7 days from now
    deadline = task.deadline or (
        ist_now() + timedelta(days=7)
    )

    return SaarthiTask.create(
        name                = task.title,
        duration_minutes    = task.estimated_duration,
        deadline            = deadline,
        focus_limit_minutes = focus,
        flexible            = task.estimated_duration > 90,  # long tasks = flexible
    )


# ── Step 3: Load calendar blocks from AURA scheduled_slots ───────────────────

# Resolved from __file__, not the CWD — the API runs with WORKDIR /app under
# Docker and from the repo root locally, and a relative path breaks in one.
TIMETABLE_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "saarthi", "fixed_tasks.json",
)


def timetable_events(start: datetime, end: datetime) -> list[FixedEvent]:
    """Expand the recurring weekly timetable into concrete FixedEvents.

    The timetable stores a weekday name plus wall-clock times ("Friday",
    "13:50"), so it has to be projected onto every matching date in the
    horizon before CP-SAT can treat those classes as blocked time.

    Note this file is global, not per-user — every user currently gets the
    same class schedule.
    """
    try:
        with open(TIMETABLE_PATH) as f:
            entries = json.load(f)
    except FileNotFoundError:
        return []

    events: list[FixedEvent] = []
    day = start.date()
    while day <= end.date():
        weekday = day.strftime("%A")
        for e in entries:
            if e["Day"] != weekday:
                continue
            s = datetime.combine(day, time.fromisoformat(e["Start"]), tzinfo=IST)
            en = datetime.combine(day, time.fromisoformat(e["End"]), tzinfo=IST)
            if en > start:          # a class already finished blocks nothing
                events.append(FixedEvent(
                    id=f"class_{day}_{e['Start']}",
                    title=e["Task"],
                    start=s,
                    end=en,
                ))
        day += timedelta(days=1)
    return events


async def load_fixed_events(
    user_id          : UUID,
    db               : AsyncSession,
    horizon          : int = 14,
    exclude_task_ids : set[UUID] | None = None,
) -> list[FixedEvent]:
    """
    Convert existing active ScheduledSlots into Saarthi FixedEvents
    so CP-SAT treats them as blocked time, plus the recurring timetable.

    `exclude_task_ids` must contain every task being re-planned in this run.
    Their existing slots are about to be deactivated and replaced, so leaving
    them in the blocked set walls each task off from its own current time —
    the solver then shoves it past its deadline to a later day and frees the
    original slot moments later, leaving the day looking empty.
    """
    now      = ist_now()
    until    = now + timedelta(days=horizon)
    exclude  = exclude_task_ids or set()

    result = await db.execute(
        select(ScheduledSlot).where(
            ScheduledSlot.user_id        == user_id,
            ScheduledSlot.is_active      == True,           # noqa: E712
            ScheduledSlot.scheduled_end  >= now,
            ScheduledSlot.scheduled_start<= until,
        ).order_by(ScheduledSlot.scheduled_start)
    )
    slots = result.scalars().all()

    slot_events = [
        FixedEvent(
            id    = str(slot.id),
            title = f"slot_{slot.task_id}",
            start = slot.scheduled_start,
            end   = slot.scheduled_end,
        )
        for slot in slots
        if slot.task_id not in exclude
    ]

    return slot_events + timetable_events(now, until)


# ── Step 5: Score each CP-SAT assignment with AURA behavioral signals ─────────

def _behavioral_score(
    assignment      : Assignment,
    aura_task       : AURATask,
    completion_prob : float,
    proc_risk       : float,
) -> float:
    """
    Score a CP-SAT assignment using AURA behavioral signals.
    Returns 0-100. Higher = better fit for this task at this time.
    """
    hour = assignment.start.hour

    # Energy match
    slot_energy = DEFAULT_ENERGY.get(hour, 0.5)
    task_energy = ENERGY_REQUIREMENT.get(aura_task.energy_requirement.value, 0.6)
    energy_match = 1.0 - abs(slot_energy - task_energy)

    # Deadline urgency
    now        = ist_now()
    deadline   = aura_task.deadline or (now + timedelta(days=7))
    hours_left = max((deadline - now).total_seconds() / 3600, 0.1)
    urgency    = 1.0 / (1.0 + hours_left / 24)

    # Overrun penalty — CP-SAT already flagged this
    overrun_penalty = 1.0 if assignment.overrun.total_seconds() == 0 else 0.5

    score = (
        energy_match     * 0.30 +
        urgency          * 0.20 +
        completion_prob  * 0.25 +
        (1 - proc_risk)  * 0.15 +
        overrun_penalty  * 0.10
    ) * 100

    return round(score, 1)


def _get_ml_scores(task: AURATask, hour: int) -> tuple[float, float]:
    """Get XGBoost + LightGBM scores for a task at a given hour."""
    features = {
        "estimated_duration"      : task.estimated_duration,
        "priority"                : task.priority,
        "category_enc"            : CATEGORY_MAP.get(task.category.value, 0),
        "energy_requirement_enc"  : ENERGY_MAP.get(task.energy_requirement.value, 2),
        "procrastination_count"   : task.procrastination_count,
        "reschedule_count"        : task.reschedule_count,
        "skip_count"              : task.skip_count,
        "hour_of_day"             : hour,
        "day_of_week"             : ist_now().weekday(),
    }
    completion_prob = predict_completion(features)
    proc_risk       = predict_procrastination_risk(features)
    return completion_prob, proc_risk


# ── Step 6: Save assignments to AURA scheduled_slots ─────────────────────────

async def save_assignments(
    assignments     : list[Assignment],
    aura_task_map   : dict[str, AURATask],  # saarthi_task_id → AURA task
    user_id         : UUID,
    db              : AsyncSession,
) -> list[dict]:
    """
    Persist CP-SAT assignments as AURA ScheduledSlot rows.
    Deactivates old slots for the same tasks first.
    """
    now    = ist_now()
    saved  = []

    # Deactivate previous slots ONCE, up front, for every task in this batch.
    # Doing it inside the loop silently dropped chunks: SQLAlchemy autoflushes
    # before each SELECT, so chunk 1's deactivation query matched the slot
    # chunk 0 had just added and flipped it inactive. Only the final chunk of
    # a multi-chunk task survived, so booked time < estimated duration.
    replaced_task_ids = {
        aura_task_map[a.parent_id].id
        for a in assignments
        if a.parent_id in aura_task_map
    }
    if replaced_task_ids:
        await db.execute(
            update(ScheduledSlot)
            .where(
                ScheduledSlot.task_id.in_(replaced_task_ids),
                ScheduledSlot.is_active == True,           # noqa: E712
            )
            .values(is_active=False)
        )

    for assignment in assignments:
        aura_task = aura_task_map.get(assignment.parent_id)
        if aura_task is None:
            continue

        # Get ML scores
        comp_prob, proc_risk = _get_ml_scores(aura_task, assignment.start.hour)
        b_score              = _behavioral_score(assignment, aura_task, comp_prob, proc_risk)

        # Create new slot
        slot = ScheduledSlot(
            user_id         = user_id,
            task_id         = aura_task.id,
            scheduled_start = assignment.start,
            scheduled_end   = assignment.end,
            is_active       = True,
            created_by      = "ai",
        )
        db.add(slot)

        saved.append({
            "task_id"           : str(aura_task.id),
            "title"             : aura_task.title,
            "chunk_index"       : assignment.chunk_index,
            "start"             : assignment.start.isoformat(),
            "end"               : assignment.end.isoformat(),
            "overrun"           : assignment.overrun.total_seconds() / 60,
            "on_time"           : assignment.on_time,
            "behavioral_score"  : b_score,
            "completion_prob"   : comp_prob,
            "procrastination_risk": proc_risk,
        })

    await db.commit()
    return saved


async def get_user_slot_preference_bias(
    user_id : UUID,
    db      : AsyncSession,
) -> dict[int, float]:
    """
    Returns {hour_of_day: preference_weight} learned from RL feedback.
    Hours where user moves tasks away get negative weight.
    Hours where user keeps tasks get positive weight.
    """
    from models.models import SlotPreferenceFeedback
    from sqlalchemy import func

    result = await db.execute(
        select(
            SlotPreferenceFeedback.hour_of_day,
            func.avg(SlotPreferenceFeedback.reward).label("avg_reward"),
            func.count(SlotPreferenceFeedback.id).label("count"),
        )
        .where(
            SlotPreferenceFeedback.user_id == user_id,
            SlotPreferenceFeedback.reward.is_not(None),
        )
        .group_by(SlotPreferenceFeedback.hour_of_day)
    )
    rows = result.all()

    bias = {}
    for row in rows:
        if row.count >= 3:   # need at least 3 observations
            # Normalize reward to -1 to +1 range
            bias[row.hour_of_day] = round(
                max(-1.0, min(1.0, row.avg_reward / 20.0)), 4
            )

    return bias

def compute_slot_scores(
    saarthi_task_id : str,
    aura_task       : AURATask,
    free_windows    : list,
    user_preference_bias: dict[int, float],
    grid_minutes    : int = 15,
    now             : datetime | None = None,
) -> dict[int, int]:
    """
    For each possible start slot in free windows,
    compute ML quality score (0-100).
    Returns {slot_index: score}.

    `now` MUST be the same instant the packer anchors its grid to, or the
    slot indices computed here address different times than the solver's,
    and each task's ML preferences get applied to the wrong slots.
    """
    from saarthi.packer import to_slot
    now = now or ist_now()

    # Pre-calculate the score for each of the 24 hours to avoid calling ML repeatedly
    hour_scores = {}
    task_energy = ENERGY_REQUIREMENT.get(
        aura_task.energy_requirement.value, 0.6
    )
    for h in range(24):
        comp_prob, proc_risk = _get_ml_scores(aura_task, h)
        slot_energy = DEFAULT_ENERGY.get(h, 0.5)
        energy_match = 1.0 - abs(slot_energy - task_energy)
        rl_bias = user_preference_bias.get(h, 0.0)

        hour_scores[h] = int((
            energy_match  * 0.35 +
            comp_prob     * 0.30 +
            (1-proc_risk) * 0.20 +
            rl_bias       * 0.15
        ) * 100)

    scores = {}
    for window in free_windows:
        slot_start = window.start
        while slot_start < window.end:
            hour = slot_start.hour
            score = hour_scores[hour]

            slot_idx = int(
                (slot_start - now).total_seconds() // 60 // grid_minutes
            )
            if slot_idx >= 0:
                scores[slot_idx] = score

            slot_start += timedelta(minutes=grid_minutes)

    return scores


# ── Main entry point ─────────────────────────────────────────────────────────

async def run_cpsat_schedule(
    user_id         : UUID,
    db              : AsyncSession,
    task_ids        : list[UUID] | None = None,
    config          : SchedulerConfig = DEFAULT_CONFIG,
) -> dict:
    """
    Full pipeline: AURA tasks → CP-SAT → behavioral scoring → save slots.

    Parameters:
        user_id  — current user
        db       — async DB session
        task_ids — specific tasks to schedule (None = all pending)
        config   — CP-SAT config

    Returns:
        {
          "scheduled": [...],   # assignments saved
          "dropped":   [...],   # task names that couldn't fit
          "warnings":  [...],   # overrun/infeasible warnings
          "solve_status": str,
          "solve_time_ms": float,
        }
    """
    # Anchor the whole grid so every slot lands on a clean 5-minute mark.
    now = round_up_to(ist_now())

    # ── Load AURA tasks ───────────────────────────────────────────────────────
    q = select(AURATask).where(
        AURATask.user_id == user_id,
        AURATask.status.in_([
            TaskStatus.DRAFT,
            TaskStatus.SCHEDULED,
            TaskStatus.POSTPONED,
            TaskStatus.PARTIALLY_DONE,
        ]),
    )
    if task_ids:
        q = q.where(AURATask.id.in_(task_ids))

    result      = await db.execute(q)
    aura_tasks  = result.scalars().all()

    if not aura_tasks:
        return {
            "scheduled"    : [],
            "dropped"      : [],
            "warnings"     : ["No schedulable tasks found."],
            "solve_status" : "SKIPPED",
            "solve_time_ms": 0,
        }

    # ── Build saarthi task map ────────────────────────────────────────────────
    # saarthi_task.id → AURA task (for reverse lookup after solving)
    saarthi_task_map : dict[str, SaarthiTask]  = {}
    aura_task_map    : dict[str, AURATask]     = {}

    for aura_task in aura_tasks:
        st = aura_task_to_saarthi(aura_task)
        saarthi_task_map[st.id] = st
        aura_task_map[st.id]    = aura_task

    # ── Load calendar blocks ──────────────────────────────────────────────────
    # Every task in this run is being re-placed, so its own current slot must
    # not block it. Slots of tasks NOT in this run stay blocked.
    fixed_events = await load_fixed_events(
        user_id, db, exclude_task_ids={t.id for t in aura_tasks}
    )

    # ── Get RL Bias ──────────────────────────────────────────────────────────
    user_preference_bias = await get_user_slot_preference_bias(user_id, db)

    # ── Run CP-SAT scheduler ──────────────────────────────────────────────────
    scheduler = Scheduler(config)
    scheduler.set_calendar(fixed_events, now=now)

    for st in saarthi_task_map.values():
        scheduler.add_task(st, now=now, replan=False)

    # ── Compute slot scores ──────────────────────────────────────────────────
    task_slot_scores = {}
    for st in saarthi_task_map.values():
        aura_task = aura_task_map[st.id]
        scores = compute_slot_scores(
            saarthi_task_id=st.id,
            aura_task=aura_task,
            free_windows=scheduler.free_windows,
            user_preference_bias=user_preference_bias,
            grid_minutes=config.grid_minutes,
            now=now,
        )
        task_slot_scores[st.id] = scores

    slot_scores = {}
    for chunk_id, chunk in scheduler.chunks.items():
        if chunk.parent_id in task_slot_scores:
            slot_scores[chunk_id] = task_slot_scores[chunk.parent_id]

    scheduler.slot_scores = slot_scores
    scheduler._replan(now)

    plan = scheduler.get_plan()

    if not plan:
        return {
            "scheduled"    : [],
            "dropped"      : list(saarthi_task_map.keys()),
            "warnings"     : ["CP-SAT could not generate a plan."],
            "solve_status" : "INFEASIBLE",
            "solve_time_ms": 0,
        }

    # ── Score and save ────────────────────────────────────────────────────────
    saved = await save_assignments(
        assignments   = plan.assignments,
        aura_task_map = aura_task_map,
        user_id       = user_id,
        db            = db,
    )

    # ── Warnings ──────────────────────────────────────────────────────────────
    warnings = scheduler.get_warnings()

    # Dropped task names
    dropped_names = []
    for chunk_id in plan.dropped_chunk_ids:
        # chunk_id format: "{saarthi_task_id}_c{index}"
        parent_id = chunk_id.rsplit("_c", 1)[0]
        aura_t    = aura_task_map.get(parent_id)
        if aura_t:
            dropped_names.append(aura_t.title)

    return {
        "scheduled"    : saved,
        "dropped"      : list(set(dropped_names)),
        "warnings"     : warnings,
        "solve_status" : plan.solve_status,
        "solve_time_ms": plan.solve_time_ms,
    }