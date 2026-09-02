from contextlib import asynccontextmanager
from datetime import datetime, timezone
from core.tz import IST, now as ist_now
from fastapi import FastAPI, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import uuid

from services.cpsat_bridge import run_cpsat_schedule
from core.database import get_db, create_tables
from core.auth import hash_password, verify_password, create_access_token
from core.dependencies import get_current_user
from models.models import User, Task, TaskStatus, TaskCategory, EnergyLevel
from schemas.schemas import RegisterRequest, LoginRequest, TokenResponse, UserRead
from services.task_service import create_task, get_task, list_tasks, transition_task, get_task_history
from services.nudge_service import evaluate_and_log

from ml.ml_features import extract_features
from ml.ml_train import train, predict_completion
from ml.lgbm_train import train_procrastination, predict_procrastination_risk
from services.analytics_service import build_behavior_profile, get_behavior_profile
from services.scheduler_service import (
    suggest_slots, book_slot, get_day_schedule
)

# Runs on app startup/shutdown: creates DB tables before serving requests.
@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_tables()
    print("Tables ready!")
    yield


app = FastAPI(title="AURA", lifespan=lifespan)


# ── Auth ───────────────────────────────────────────────────────────────────────

# Liveness check.
@app.get("/")
def root():
    return {"message": "AURA is alive"}


# Creates a new user account, hashing the password and rejecting duplicate emails.
@app.post("/register", response_model=UserRead, status_code=201)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == payload.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email           = payload.email,
        username        = payload.username,
        hashed_password = hash_password(payload.password),
        full_name       = payload.full_name,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


# Verifies email/password and issues a JWT access token.
@app.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == payload.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    token = create_access_token(str(user.id))
    return TokenResponse(access_token=token)


# ── Tasks ──────────────────────────────────────────────────────────────────────

# Creates a new task (status=DRAFT) for the current user.
@app.post("/tasks", status_code=201)
async def api_create_task(
    title              : str,
    category           : TaskCategory,
    energy_requirement : EnergyLevel,
    estimated_duration : int,
    priority           : int = 5,
    deadline           : datetime | None = None,
    db                 : AsyncSession = Depends(get_db),
    current_user       : User = Depends(get_current_user),
):
    task = await create_task(
        user_id            = current_user.id,
        title              = title,
        category           = category,
        energy_requirement = energy_requirement,
        estimated_duration = estimated_duration,
        priority           = priority,
        deadline           = deadline,
        db                 = db,
    )
    return {
        "id"    : str(task.id),
        "title" : task.title,
        "status": task.status,
    }


# Lists all tasks belonging to the current user.
@app.get("/tasks")
async def api_list_tasks(
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    tasks = await list_tasks(current_user.id, db)
    return [
        {
            "id"      : str(t.id),
            "title"   : t.title,
            "status"  : t.status,
            "priority": t.priority,
            "category": t.category,
        }
        for t in tasks
    ]


# Moves a task to a new status through the valid state-machine transitions.
@app.patch("/tasks/{task_id}/transition")
async def api_transition_task(
    task_id      : str,
    to_status    : TaskStatus,
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    try:
        task = await transition_task(
            task_id   = uuid.UUID(task_id),
            user_id   = current_user.id,
            to_status = to_status,
            db        = db,
        )
        return {
            "id"                   : str(task.id),
            "title"                : task.title,
            "status"               : task.status,
            "procrastination_count": task.procrastination_count,
        }
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


# Returns the status-change event log for a single task.
@app.get("/tasks/{task_id}/history")
async def api_task_history(
    task_id      : str,
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    try:
        events = await get_task_history(
            task_id = uuid.UUID(task_id),
            user_id = current_user.id,
            db      = db,
        )
        return [
            {
                "event_type" : e.event_type,
                "from_status": e.from_status,
                "to_status"  : e.to_status,
                "hour_of_day": e.hour_of_day,
                "day_of_week": e.day_of_week,
                "occurred_at": e.occurred_at,
            }
            for e in events
        ]
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

# Computes a stress score from biometrics/usage signals and logs a nudge recommendation.
@app.post("/nudge/evaluate")
async def api_nudge_evaluate(
    heart_rate          : int,
    hrv_ms              : float,
    app_switches        : int   = 0,
    screen_time_hours   : float = 0.0,
    minutes_since_break : int   = 0,
    db                  : AsyncSession = Depends(get_db),
    current_user        : User = Depends(get_current_user),
):
    result = await evaluate_and_log(
        user_id             = current_user.id,
        heart_rate          = heart_rate,
        hrv_ms              = hrv_ms,
        app_switches        = app_switches,
        screen_time_hours   = screen_time_hours,
        minutes_since_break = minutes_since_break,
        db                  = db,
    )
    return result


# Extracts training features from historical tasks and trains the XGBoost completion-probability model.
@app.post("/ml/train")
async def api_train(
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    df = await extract_features(db)

    if df.empty:
        return {
            "status" : "not enough data",
            "message": "Complete or abandon at least 10 tasks first",
        }

    metrics = train(df)
    return {"status": "trained", "metrics": metrics}


# Predicts a single task's completion probability using the trained XGBoost model.
@app.post("/ml/predict")
async def api_predict(
    task_id      : str,
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    task = await get_task(uuid.UUID(task_id), current_user.id, db)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    category_map = {
        "deep_work": 0, "admin": 1, "learning": 2,
        "meeting": 3, "personal": 4, "health": 5,
    }
    energy_map = {
        "very_low": 0, "low": 1, "medium": 2, "high": 3, "peak": 4,
    }

    from datetime import datetime, timezone
    now = ist_now()

    features = {
        "estimated_duration"    : task.estimated_duration,
        "priority"              : task.priority,
        "category_enc"          : category_map.get(task.category.value, 0),
        "energy_requirement_enc": energy_map.get(task.energy_requirement.value, 2),
        "procrastination_count" : task.procrastination_count,
        "reschedule_count"      : task.reschedule_count,
        "skip_count"            : task.skip_count,
        "hour_of_day"           : now.hour,
        "day_of_week"           : now.weekday(),
    }

    prob = predict_completion(features)
    return {
        "task_id"               : task_id,
        "title"                 : task.title,
        "completion_probability": prob,
        "interpretation"        : (
            "likely to complete" if prob >= 0.6
            else "at risk of procrastination" if prob <= 0.4
            else "uncertain"
        ),
    }

# Extracts training features and trains the LightGBM procrastination-risk model.
@app.post("/ml/train/procrastination")
async def api_train_procrastination(
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    df = await extract_features(db)

    if df.empty:
        return {
            "status" : "not enough data",
            "message": "Complete or abandon at least 10 tasks first",
        }

    metrics = train_procrastination(df)
    return {"status": "trained", "metrics": metrics}


# Predicts a single task's procrastination risk using the trained LightGBM model.
@app.post("/ml/predict/procrastination")
async def api_predict_procrastination(
    task_id      : str,
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    task = await get_task(uuid.UUID(task_id), current_user.id, db)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    category_map = {
        "deep_work": 0, "admin": 1, "learning": 2,
        "meeting"  : 3, "personal": 4, "health": 5,
    }
    energy_map = {
        "very_low": 0, "low": 1, "medium": 2, "high": 3, "peak": 4,
    }

    from datetime import datetime, timezone
    now = ist_now()

    features = {
        "estimated_duration"      : task.estimated_duration,
        "priority"                : task.priority,
        "category_enc"            : category_map.get(task.category.value, 0),
        "energy_requirement_enc"  : energy_map.get(task.energy_requirement.value, 2),
        "procrastination_count"   : task.procrastination_count,
        "reschedule_count"        : task.reschedule_count,
        "skip_count"              : task.skip_count,
        "hour_of_day"             : now.hour,
        "day_of_week"             : now.weekday(),
    }

    risk = predict_procrastination_risk(features)

    return {
        "task_id"               : task_id,
        "title"                 : task.title,
        "procrastination_risk"  : risk,
        "interpretation"        : (
            "high risk — likely to delay"    if risk >= 0.6
            else "low risk — likely to start" if risk <= 0.3
            else "moderate risk"
        ),
        "suggestion": (
            "Break this task into smaller pieces" if risk >= 0.6
            else "Good time to schedule this"     if risk <= 0.3
            else "Set a specific start time"
        ),
    }

# Rebuilds and upserts the current user's behavior profile from their task history.
@app.post("/analytics/profile/build")
async def api_build_profile(
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    profile = await build_behavior_profile(current_user.id, db)
    return {
        "user_id"                      : str(profile.user_id),
        "total_tasks_created"          : profile.total_tasks_created,
        "total_tasks_completed"        : profile.total_tasks_completed,
        "total_tasks_abandoned"        : profile.total_tasks_abandoned,
        "completion_rate"              : profile.completion_rate,
        "avg_estimation_error_minutes" : profile.avg_estimation_error_minutes,
        "avg_procrastination_count"    : profile.avg_procrastination_count,
        "avg_reschedule_count"         : profile.avg_reschedule_count,
        "avg_skip_count"               : profile.avg_skip_count,
        "peak_focus_hour_start"        : profile.peak_focus_hour_start,
        "peak_focus_hour_end"          : profile.peak_focus_hour_end,
        "most_procrastinated_category" : profile.most_procrastinated_category,
        "last_updated"                 : profile.last_updated,
    }


# Fetches the current user's existing behavior profile, if one has been built.
@app.get("/analytics/profile")
async def api_get_profile(
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    profile = await get_behavior_profile(current_user.id, db)
    if profile is None:
        return {
            "message": "No profile yet. Hit POST /analytics/profile/build first."
        }
    return {
        "user_id"                      : str(profile.user_id),
        "total_tasks_created"          : profile.total_tasks_created,
        "total_tasks_completed"        : profile.total_tasks_completed,
        "total_tasks_abandoned"        : profile.total_tasks_abandoned,
        "completion_rate"              : profile.completion_rate,
        "avg_estimation_error_minutes" : profile.avg_estimation_error_minutes,
        "avg_procrastination_count"    : profile.avg_procrastination_count,
        "avg_reschedule_count"         : profile.avg_reschedule_count,
        "avg_skip_count"               : profile.avg_skip_count,
        "peak_focus_hour_start"        : profile.peak_focus_hour_start,
        "peak_focus_hour_end"          : profile.peak_focus_hour_end,
        "most_procrastinated_category" : profile.most_procrastinated_category,
        "last_updated"                 : profile.last_updated,
    }

# Queues an async model retraining job on the Celery worker.
@app.post("/ml/retrain")
async def api_retrain(
    current_user: User = Depends(get_current_user),
):
    """Trigger model retraining via Celery worker."""
    from workers.tasks import retrain_models
    task = retrain_models.delay()
    return {"status": "queued", "task_id": task.id}


# Queues an async behavior-profile refresh for all users on the Celery worker.
@app.post("/ml/update-profiles")
async def api_update_profiles(
    current_user: User = Depends(get_current_user),
):
    """Trigger behavior profile update via Celery worker."""
    from workers.tasks import update_behavior_profiles
    task = update_behavior_profiles.delay()
    return {"status": "queued", "task_id": task.id}


# Polls the status/result of a previously queued Celery task by id.
@app.get("/ml/task-status/{task_id}")
async def api_task_status(
    task_id      : str,
    current_user : User = Depends(get_current_user),
):
    """Check status of a queued Celery task."""
    from workers.celery_app import celery_app
    task = celery_app.AsyncResult(task_id)
    return {
        "task_id": task_id,
        "status" : task.status,
        "result" : task.result if task.ready() else None,
    }

# Scores a task's ML predictions then ranks the day's free calendar gaps to suggest the best time slots.
@app.get("/schedule/suggest/{task_id}")
async def api_suggest_slots(
    task_id      : str,
    date         : str | None = None,   # YYYY-MM-DD, defaults to today
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    """Suggest best time slots for a task on a given date."""
    from datetime import date as date_type
    import uuid as uuid_module

    if date:
        target_date = datetime.strptime(date, "%Y-%m-%d").replace(
            tzinfo=IST
        )
    else:
        target_date = ist_now()

    # Get ML scores for this task
    task_result = await db.execute(
        select(Task).where(
            Task.id      == uuid.UUID(task_id),
            Task.user_id == current_user.id,
        )
    )
    task = task_result.scalar_one_or_none()
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")

    category_map = {
        "deep_work": 0, "admin": 1, "learning": 2,
        "meeting"  : 3, "personal": 4, "health": 5,
    }
    energy_map = {
        "very_low": 0, "low": 1, "medium": 2, "high": 3, "peak": 4,
    }

    features = {
        "estimated_duration"      : task.estimated_duration,
        "priority"                : task.priority,
        "category_enc"            : category_map.get(task.category.value, 0),
        "energy_requirement_enc"  : energy_map.get(task.energy_requirement.value, 2),
        "procrastination_count"   : task.procrastination_count,
        "reschedule_count"        : task.reschedule_count,
        "skip_count"              : task.skip_count,
        "hour_of_day"             : ist_now().hour,
        "day_of_week"             : ist_now().weekday(),
    }

    from ml.ml_train import predict_completion
    from ml.lgbm_train import predict_procrastination_risk
    comp_prob = predict_completion(features)
    proc_risk = predict_procrastination_risk(features)

    try:
        suggestions = await suggest_slots(
            task_id             = uuid.UUID(task_id),
            user_id             = current_user.id,
            date                = target_date,
            db                  = db,
            completion_prob     = comp_prob,
            procrastination_risk= proc_risk,
        )
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    return {
        "task_id"           : task_id,
        "title"             : task.title,
        "duration_minutes"  : task.estimated_duration,
        "completion_prob"   : comp_prob,
        "procrastination_risk": proc_risk,
        "suggestions"       : suggestions,
    }


# Books a specific start/end slot for a task, rejecting overlaps with existing slots.
@app.post("/schedule/book")
async def api_book_slot(
    task_id     : str,
    slot_start  : datetime,
    slot_end    : datetime,
    db          : AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Book a specific slot for a task."""
    try:
        slot = await book_slot(
            task_id    = uuid.UUID(task_id),
            user_id    = current_user.id,
            slot_start = slot_start,
            slot_end   = slot_end,
            db         = db,
            created_by = "user",
        )
        return {
            "slot_id"   : str(slot.id),
            "task_id"   : task_id,
            "start"     : slot.scheduled_start.isoformat(),
            "end"       : slot.scheduled_end.isoformat(),
            "status"    : "booked",
        }
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))


# Records a manually-moved slot as RL feedback, then updates the slot's time.
@app.post("/schedule/preference/move")
async def api_user_moved_slot(
    slot_id      : str,
    new_start    : datetime,
    new_end      : datetime,
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    """
    Called when user manually moves a scheduled slot.
    Records the preference for RL training.
    """
    from models.models import SlotPreferenceFeedback, ScheduledSlot
    import uuid as uuid_module

    # Load old slot
    result = await db.execute(
        select(ScheduledSlot).where(
            ScheduledSlot.id      == uuid_module.UUID(slot_id),
            ScheduledSlot.user_id == current_user.id,
        )
    )
    old_slot = result.scalar_one_or_none()
    if not old_slot:
        raise HTTPException(status_code=404, detail="Slot not found")

    now = ist_now()

    # Record the preference signal
    feedback = SlotPreferenceFeedback(
        user_id           = current_user.id,
        task_id           = old_slot.task_id,
        suggested_start   = old_slot.scheduled_start,
        suggested_score   = 0.0,   # will be filled by RL trainer
        user_chosen_start = new_start,
        was_kept          = False,
        hour_of_day       = new_start.hour,
        day_of_week       = new_start.weekday(),
        created_at        = now,
    )
    db.add(feedback)

    # Update the slot
    old_slot.scheduled_start = new_start
    old_slot.scheduled_end   = new_end

    await db.commit()
    return {"status": "moved", "preference_recorded": True}


# Returns a day's booked slots plus the free gaps between them.
@app.get("/schedule/day")
async def api_day_schedule(
    date         : str | None = None,   # YYYY-MM-DD
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    """Get full schedule for a day."""
    if date:
        target_date = datetime.strptime(date, "%Y-%m-%d").replace(
            tzinfo=IST
        )
    else:
        target_date = ist_now()

    schedule = await get_day_schedule(current_user.id, target_date, db)

    # Also return free gaps
    from services.scheduler_service import get_booked_slots, find_free_gaps
    booked = await get_booked_slots(current_user.id, target_date, db)
    gaps   = find_free_gaps(booked, target_date)

    return {
        "date"          : target_date.date().isoformat(),
        "booked_slots"  : schedule,
        "free_gaps"     : [
            {
                "start"           : s.isoformat(),
                "end"             : e.isoformat(),
                "duration_minutes": int((e - s).total_seconds() / 60),
            }
            for s, e in gaps
        ],
        "total_booked_minutes": sum(
            int((datetime.fromisoformat(s["end"]) -
                 datetime.fromisoformat(s["start"])).total_seconds() / 60)
            for s in schedule
        ),
    }

# Deletes every scheduled slot for the current user, leaving the tasks themselves intact.
@app.delete("/schedule/slots")
async def api_clear_slots(
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    from models.models import ScheduledSlot
    from sqlalchemy import delete

    result = await db.execute(
        delete(ScheduledSlot).where(ScheduledSlot.user_id == current_user.id)
    )
    await db.commit()
    return {"status": "cleared", "deleted": result.rowcount}


# Runs the full CP-SAT scheduling pipeline: fits pending tasks into free slots, splits long tasks into sessions, scores with behavioral ML.
@app.post("/schedule/cpsat")
async def api_cpsat_schedule(
    task_ids     : list[str] | None = None,
    db           : AsyncSession = Depends(get_db),
    current_user : User = Depends(get_current_user),
):
    """
    Full CP-SAT scheduling pipeline.
    Fits all pending tasks into free calendar slots,
    splits long tasks into sessions, scores with behavioral ML.
    """
    parsed_ids = [uuid.UUID(tid) for tid in task_ids] if task_ids else None

    result = await run_cpsat_schedule(
        user_id  = current_user.id,
        db       = db,
        task_ids = parsed_ids,
    )
    return result