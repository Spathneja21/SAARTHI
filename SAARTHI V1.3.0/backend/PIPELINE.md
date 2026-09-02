# AURA — Pipeline Documentation

Entry point: **`main.py`** (FastAPI app `AURA`). Background jobs: **`workers/celery_app.py`** + **`workers/tasks.py`** (Celery, Redis broker).

## 1. Startup

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_tables()   # Base.metadata.create_all — no Alembic, no seed data
    yield

app = FastAPI(title="AURA", lifespan=lifespan)
```

`create_tables()` (`core/database.py`) opens the async SQLAlchemy engine and creates any missing tables directly from the ORM models in `models/models.py`.

## 2. Routes → functions called → output

| Route | Calls (in order) | Output |
|---|---|---|
| `GET /` | — | `{"message": "AURA is alive"}` |
| `POST /register` | dup-check `select(User)` → `hash_password()` → insert `User` | `UserRead` (id, email, username, full_name, timezone) |
| `POST /login` | `select(User)` → `verify_password()` → `create_access_token()` | `TokenResponse` (JWT) |
| `POST /tasks` | `task_service.create_task()` | task id/title/status |
| `GET /tasks` | `task_service.list_tasks()` | list of tasks |
| `PATCH /tasks/{id}/transition` | `task_service.transition_task()` | id/title/status/procrastination_count |
| `GET /tasks/{id}/history` | `task_service.get_task_history()` | list of `TaskEvent` |
| `POST /nudge/evaluate` | `nudge_service.evaluate_and_log()` → `compute_stress_score` → `get_stress_level` → `get_nudge_type` → `get_nudge_message` → persist `StressLog` | stress_score, stress_level, should_intervene, nudge_type, message |
| `POST /ml/train` | `ml_features.extract_features()` → `ml_train.train()` | XGBoost metrics, pickled to `ml/artifacts/xgb_completion.pkl` |
| `POST /ml/predict` | build feature dict → `ml_train.predict_completion()` | completion probability + interpretation |
| `POST /ml/train/procrastination` | `ml_features.extract_features()` → `lgbm_train.train_procrastination()` | LightGBM metrics, pickled to `ml/artifacts/lgbm_procrastination.pkl` |
| `POST /ml/predict/procrastination` | build feature dict → `lgbm_train.predict_procrastination_risk()` | risk + interpretation + suggestion |
| `POST /analytics/profile/build` | `analytics_service.build_behavior_profile()` | upserted `UserBehaviorProfile` |
| `GET /analytics/profile` | `analytics_service.get_behavior_profile()` | existing profile |
| `POST /ml/retrain` | `workers.tasks.retrain_models.delay()` | `{status: queued, task_id}` |
| `POST /ml/update-profiles` | `workers.tasks.update_behavior_profiles.delay()` | `{status: queued, task_id}` |
| `GET /ml/task-status/{id}` | `celery_app.AsyncResult()` | Celery task status/result |
| `GET /schedule/suggest/{task_id}` | load task → ML predictions → `scheduler_service.suggest_slots()` → `get_booked_slots` → `find_free_gaps` → `score_slot()` per gap | top-3 ranked slot suggestions with reasoning |
| `POST /schedule/book` | `scheduler_service.book_slot()` (conflict check → insert `ScheduledSlot`) | booked slot |
| `POST /schedule/preference/move` | load old slot → insert `SlotPreferenceFeedback` → update slot | `{status: moved}` |
| `GET /schedule/day` | `scheduler_service.get_day_schedule()` + `get_booked_slots`/`find_free_gaps` | booked_slots, free_gaps, total_booked_minutes |
| `POST /schedule/cpsat` | `cpsat_bridge.run_cpsat_schedule()` (full pipeline, §4) | scheduled, dropped, warnings, solve_status, solve_time_ms |

## 3. Auth

`core/auth.py` — **bcrypt** for hashing, **python-jose HS256** JWT, 30-min expiry, hardcoded `SECRET_KEY` (not from env — flagged as a hardening gap):

```python
def hash_password(password): return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
def verify_password(plain, hashed): return bcrypt.checkpw(plain.encode(), hashed.encode())

def create_access_token(user_id):
    payload = {"sub": user_id, "exp": now_utc + 30min}
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")
```

`core/dependencies.py::get_current_user` — decodes the `Authorization: Bearer` token, 401s on bad/expired token or inactive/missing user, else injects the `User` ORM object into the route.

## 4. Formulas

### 4.1 Stress score — `services/nudge_service.py`
**Input**: `heart_rate, hrv_ms, app_switches, screen_time_hours, minutes_since_break`

```python
hr_stress     = clamp(0,100, int((heart_rate - 70) * 2))
hrv_stress    = clamp(0,100, int((80 - hrv_ms) * 1.5))
switch_stress = min(100, app_switches * 8)
screen_stress = min(100, int(screen_time_hours * 15))
break_stress  = min(100, int(minutes_since_break * 1.2))

score = int(
    hr_stress     * 0.25 +
    hrv_stress    * 0.30 +
    switch_stress * 0.20 +
    screen_stress * 0.10 +
    break_stress  * 0.15
)
```
**Output**: `stress_score` (0-100) →
- `stress_level`: `<30` calm · `<55` elevated · `<75` high · else critical
- `nudge_type` (priority order): `score<30`→none · `break_min>90`→break · `app_switches>8`→reprioritize · `score>=70`→breathing · `screen_hrs>3`→hydrate · else→break
- `should_intervene = score >= 35`

### 4.2 Completion probability — XGBoost (`ml/ml_train.py`)
`XGBClassifier(n_estimators=100, max_depth=4, learning_rate=0.1)`

**Input features** (`ml/ml_features.py::extract_features`, joined from `tasks`+`task_events`):
`estimated_duration, priority, category_enc, energy_requirement_enc, procrastination_count, reschedule_count, skip_count, hour_of_day, day_of_week`

**Label**: `1 if task.status == "completed" else 0` (restricted to resolved tasks: completed/abandoned/skipped/partially_done)

**Output**: `predict_completion(features) -> float` (0-1 probability; cold-start default `0.5` if no model trained yet)

### 4.3 Procrastination risk — LightGBM (`ml/lgbm_train.py`)
`LGBMClassifier(n_estimators=200, max_depth=5, learning_rate=0.05, num_leaves=31)`

**Input**: same feature set as 4.2. **Label**: inverse of completion label (`1` = did not complete).

**Output**: `predict_procrastination_risk(features) -> float` (0-1). Cold-start fallback (no model trained yet):
```python
risk  = min(procrastination_count * 0.15, 0.45)
risk += min(skip_count * 0.10, 0.30)
risk += min(reschedule_count * 0.05, 0.25)
risk = min(risk, 1.0)
```

### 4.4 Behavioral score (post-CP-SAT) — `services/cpsat_bridge.py::_behavioral_score`
**Input**: assignment start hour, task energy requirement, deadline, `completion_prob`, `proc_risk`, overrun.

```python
energy_match    = 1.0 - abs(slot_energy[hour] - task_energy)          # both in [0,1]
urgency         = 1.0 / (1.0 + hours_until_deadline / 24)
overrun_penalty = 1.0 if no_overrun else 0.5

score = (
    energy_match     * 0.30 +
    urgency          * 0.20 +
    completion_prob  * 0.25 +
    (1 - proc_risk)  * 0.15 +
    overrun_penalty  * 0.10
) * 100
```
Energy curve `DEFAULT_ENERGY[hour]` peaks ~10am (1.0), lowest late night (0.1). `ENERGY_REQUIREMENT = {very_low:0.2, low:0.4, medium:0.6, high:0.8, peak:1.0}`.

### 4.5 Slot quality score (pre-solve, feeds CP-SAT objective) — `cpsat_bridge.py::compute_slot_scores`
```python
hour_score = int((
    energy_match  * 0.35 +
    comp_prob     * 0.30 +
    (1-proc_risk) * 0.20 +
    rl_bias       * 0.15
) * 100)
```
`rl_bias` = learned per-hour bias from RL feedback (`get_user_slot_preference_bias`): `avg_reward / 20.0`, clamped to `[-1, 1]`, only computed for hours with ≥3 feedback samples.

### 4.6 `/schedule/suggest` slot scoring — `services/scheduler_service.py::score_slot`
```python
energy_match     = 1.0 - abs(slot_energy - task_energy)
deadline_urgency = 1.0/(1+hours_left/24)  if task.deadline else 0.3
proc_penalty     = 1.0 - procrastination_risk

score = (
    energy_match     * 0.35 +
    deadline_urgency * 0.25 +
    completion_prob  * 0.25 +
    proc_penalty     * 0.15
) * 100
```

### 4.7 Behavior profile aggregates — `services/analytics_service.py::build_behavior_profile`
- `completion_rate = completed / total`
- `avg_estimation_error_minutes = mean(actual_duration - estimated_duration)` over completed tasks (positive = underestimated)
- `avg_procrastination_count / avg_reschedule_count / avg_skip_count` = per-task means
- `peak_focus_hour` = `hour_of_day` with most `task_completed` events (+2h window)
- `most_procrastinated_category` = category with highest summed `procrastination_count`

### 4.8 CP-SAT scheduler — `saarthi/packer.py` (invoked by `cpsat_bridge.run_cpsat_schedule`)

**Per-chunk variables**:
```python
start    = model.new_int_var(0, HORIZON - occupied, ...)
end      = model.new_int_var(occupied, HORIZON, ...)
present  = model.new_bool_var(...)
overrun  = model.new_int_var(0, HORIZON, ...)
interval = model.new_optional_interval_var(start, occupied, end, present, ...)
```
**Constraints**: only start inside free grid slots; `add_no_overlap` across all chunks + fixed events; soft-deadline via `overrun`; chunk-of-same-task precedence and partial-completion ordering; frozen in-progress chunks; displacement tracked via `add_abs_equality`.

**Objective**:
```python
core_objective = (
    W_SCHEDULE * sum(present)
  - W_OVERRUN  * sum(overrun)
  - W_DISPLACE * sum(displacement)
)
full_objective = core_objective + W_SLOT_QUALITY * sum(quality_bonus)   # phase 2, with ML hints
```
Weights (`saarthi/config.py`): `w_schedule=10000, w_overrun=100, w_displace=5, w_slot_quality=50`; `grid_minutes=15`, `horizon_days=7`, `elastic_buffer_ratio=0.08`, `solver_time_limit_s=3.0`.

**Output**: per-chunk `Assignment` (start, end, overrun, on_time) → persisted as `ScheduledSlot` rows, scored via §4.4 → returned as the `scheduled` list.

## 5. Celery pipeline (`workers/celery_app.py` + `workers/tasks.py`)

Broker/backend: Redis. Beat schedule (UTC):

| Task | Schedule | Calls | Output |
|---|---|---|---|
| `retrain_models` | Sun 02:00 | `extract_features()` → `ml_train.train()` + `lgbm_train.train_procrastination()` | both training metrics dicts (skips if <10 rows) |
| `update_behavior_profiles` | daily 00:30 | `analytics_service.build_behavior_profile()` per active user | `{status, users_updated}` |
| `update_rl_rewards` | daily 01:00 | scans `SlotPreferenceFeedback` where `reward IS NULL`, assigns reward per task outcome | reward written back per row |
| `retrain_on_demand` | manual only | `retrain_models.apply().get()` | same as `retrain_models` |

RL reward rule (`update_rl_rewards`):
```
completed & kept AURA's slot   → +20
completed but user moved it    → +10
user moved slot, not resolved  →  -5
abandoned after reschedule     → -10
```

## 6. Data model (`models/models.py`)

No SQL-level foreign keys — relationships are indexed UUID columns enforced only in application code.

- **`users`**: id, email, username, hashed_password, full_name, timezone, is_active, created_at
- **`tasks`**: id, user_id, title, description, category, energy_requirement, estimated_duration, actual_duration, priority, deadline, status, procrastination_count, reschedule_count, skip_count, created_at, updated_at, started_at, completed_at
- **`task_events`**: id, task_id, user_id, event_type, from_status, to_status, reason, hour_of_day, day_of_week, stress_score, occurred_at
- **`stress_logs`**: id, user_id, heart_rate, hrv_ms, app_switches, screen_time_hours, minutes_since_break, stress_score, stress_level, nudge_type, hour_of_day, day_of_week, recorded_at
- **`user_behavior_profiles`**: user_id (PK), total_tasks_created, completed, abandoned, completion_rate, avg_estimation_error_minutes, avg_procrastination_count, avg_reschedule_count, avg_skip_count, peak_focus_hour_start/_end, most_procrastinated_category, last_updated
- **`slot_preference_feedback`**: id, user_id, task_id, suggested_start, suggested_score, user_chosen_start, was_completed, was_kept, reward, hour_of_day, day_of_week, created_at
- **`scheduled_slots`**: id, user_id, task_id, scheduled_start, scheduled_end, is_active, created_by (ai|user), created_at

Enums: `TaskStatus` (draft/scheduled/in_progress/paused/completed/partially_done/postponed/skipped/abandoned) · `TaskCategory` (deep_work/admin/learning/meeting/personal/health) · `EnergyLevel` (very_low/low/medium/high/peak)
