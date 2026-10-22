# AURA — Backend

**A**daptive **U**ser **R**outine **A**ssistant. The FastAPI service behind SAARTHI: it
owns tasks, fixed commitments and the schedule, and decides *when* each task happens.

The client is a Flutter app ([`../app files/`](../app%20files/)) that authenticates
through Firebase and does no scheduling of its own — every task, commitment and
scheduled block lives here, in PostgreSQL, scoped to the signed-in account.

---

## 🧠 What it does

- **Task state machine** — draft → scheduled → in_progress → completed (or
  postponed / skipped / abandoned along the way), each transition logged as a
  `TaskEvent` with the hour and weekday it happened, which is what the ML models
  train on.
- **CP-SAT scheduling** — `POST /schedule/cpsat` hands every pending task to an
  OR-Tools constraint solver (`saarthi/`), which fits them into the gaps left by
  the user's fixed weekly commitments: no overlaps, deadlines respected, long
  tasks split into focus-limited chunks with breaks.
- **Behavioral scoring** — each candidate start hour is scored by blending an
  energy-match curve, an XGBoost completion-probability model, a LightGBM
  procrastination-risk model, and a learned per-user, per-hour preference — so
  CP-SAT doesn't just find *a* feasible plan, it prefers a good one.
- **Reinforcement learning on slot preference** — every AI-suggested slot is
  logged; if the user moves it, that's a rejection signal; once the task
  resolves (completed/abandoned), a nightly job turns the outcome into a reward.
  A Thompson-sampling policy (`ml/slot_bandit.py`) learns from that and feeds
  back into the next plan's scoring. See **RL system** below and
  [`docs/RL_INTEGRATION_PLAN.md`](docs/RL_INTEGRATION_PLAN.md) for the full design.
- **Stress-based nudges** — `POST /nudge/evaluate` turns wearable-style signals
  (heart rate, HRV, app switches, screen time) into a stress score and a nudge
  suggestion (break / breathing / reprioritize / hydrate).
- **Behavior profiles** — nightly aggregation of completion rate, estimation
  error, procrastination patterns and peak focus hours per user.

---

## 🏗️ Architecture

```
┌─────────────┐  Bearer (Firebase ID token)   ┌──────────────────────────────────────┐
│ Flutter app │ ─────────────────────────────▶│              FastAPI (main.py)        │
└─────────────┘ ◀───────────────────────────── │                                        │
                          JSON                  │  core/        auth, db session, tz    │
                                                 │  services/    task/schedule/analytics │
                                                 │  saarthi/     CP-SAT solver            │
                                                 │  ml/          XGBoost·LightGBM·RL      │
                                                 └───────────────┬────────────────────────┘
                                                                 │
                          ┌──────────────────────────────────────┼───────────────────────┐
                          ▼                                      ▼                        ▼
                  ┌───────────────┐                     ┌────────────────┐      ┌─────────────────┐
                  │  PostgreSQL   │                      │ Redis + Celery  │      │  Firebase Admin  │
                  │  users·tasks  │                      │ nightly jobs:   │      │  verifies the    │
                  │  slots·events │                      │  retrain, RL    │      │  ID token; the   │
                  │  feedback     │                      │  reward, profile│      │  backend never   │
                  └───────────────┘                      └────────────────┘      │  sees a password │
                                                                                   └──────────────────┘
```

**Auth is Firebase-only.** `/register` and `/login` (local bcrypt + JWT) predate
the Firebase migration and still work at the database level, but the JWT they
mint is **not accepted by any route** — `get_current_user` only verifies Firebase
ID tokens (`core/dependencies.py`). Every other endpoint auto-provisions a `User`
row on first request from a verified token; there is no separate "register with
the backend" step for a real client.

The **brain / doorway split**, from
[`docs/INTEGRATION_LOG.md`](docs/INTEGRATION_LOG.md): `ml/`, `saarthi/`, and the
scoring formulas in `services/` are the brain and read only from the database,
never from a URL. `main.py` and `schemas/` are the doorway — the only layer that
changes when the client changes.

---

## 📁 Project structure

```
main.py                          831   FastAPI app — every route (see Endpoint map)
dashboard.py                     233   Streamlit debug dashboard, standalone (own deps, not in requirements.txt)

core/
├── database.py                   32   Async engine/session; create_tables() at startup
├── auth.py                       25   bcrypt + JWT — legacy /register+/login path, unused by the app
├── firebase_auth.py              65   Firebase Admin SDK init + ID-token verification
├── dependencies.py              130   get_current_user: verifies token, finds-or-creates the User row
└── tz.py                         17   IST is the single source of truth for every hour_of_day

models/models.py                 319   SQLAlchemy ORM — every table (see Data model)
schemas/schemas.py               164   Pydantic request/response models

services/
├── task_service.py              328   State machine, transitions, TaskEvent logging
├── scheduler_service.py         326   Legacy top-3 slot suggestion (/schedule/suggest, /schedule/book)
├── cpsat_bridge.py               679   The real scheduler: AURA ⇄ CP-SAT bridge, RL policy sampling
├── analytics_service.py         158   Nightly behavior-profile aggregation
└── nudge_service.py             122   Stress score → nudge type

saarthi/                               The CP-SAT solver — pure scheduling, no AURA/ML imports
├── Models.py                    110   Task, Chunk, FixedEvent, Assignment, Plan
├── config.py                     40   Grid/horizon/weights — SchedulerConfig
├── calendar_.py                  86   Free-window computation from fixed events
├── chunker.py                    89   Splits a task into focus-limited chunks + breaks
├── degradation.py                86   Classifies a plan's chunks (on-time / overrun / dropped)
├── scheduler.py                 150   Orchestrates calendar → chunk → pack → plan
├── packer.py                    447   The CP-SAT model itself (variables, constraints, objective)
└── demo.py                       83   `python demo.py` — interactive CLI demo, no server needed

ml/
├── ml_features.py                 56   SQL → training DataFrame (tasks ⋈ task_events)
├── ml_train.py                   101   XGBoost completion-probability model
├── lgbm_train.py                 123   LightGBM procrastination-risk model
└── slot_bandit.py                237   Thompson-sampling slot-preference policy (Phase 1 RL)

workers/
├── celery_app.py                  41   Celery app + beat schedule (nightly jobs, UTC)
└── tasks.py                      174   retrain_models · update_behavior_profiles · update_rl_rewards

test_tz.py, test_cp.py, test_no_overlap.py,        706   asyncio-runnable scripts, see Testing
test_replan.py, test_rl_loop.py, test_slot_bandit.py
```

---

## 🌐 Endpoint map

Auth (`🔓` = no token required, `🔒` = `Authorization: Bearer <Firebase ID token>`):

| Group | Method & path | Calls | Notes |
|---|---|---|---|
| — | 🔓 `GET /` | — | liveness check |
| Legacy auth | 🔓 `POST /register` | `hash_password`, insert `User` | not used by the app; token it returns is not accepted anywhere |
| Legacy auth | 🔓 `POST /login` | `verify_password`, `create_access_token` | same |
| Tasks | 🔒 `POST /tasks` | `task_service.create_task` | |
| Tasks | 🔒 `GET /tasks` | `task_service.list_tasks` | |
| Tasks | 🔒 `GET /tasks/{id}` | `task_service.get_task` | |
| Tasks | 🔒 `PATCH /tasks/{id}` | `task_service.update_task` | descriptive fields only |
| Tasks | 🔒 `DELETE /tasks/{id}` | `task_service.delete_task` | |
| Tasks | 🔒 `POST /tasks/{id}/complete` | `resolve_task(..., COMPLETED)` | walks the state machine safely |
| Tasks | 🔒 `POST /tasks/{id}/postpone` | `resolve_task(..., POSTPONED)` | |
| Tasks | 🔒 `POST /tasks/{id}/skip` | `resolve_task(..., SKIPPED)` | |
| Tasks | 🔒 `PATCH /tasks/{id}/transition` | `task_service.transition_task` | raw state-machine transition |
| Tasks | 🔒 `GET /tasks/{id}/history` | `task_service.get_task_history` | `TaskEvent` list |
| Nudges | 🔒 `POST /nudge/evaluate` | `nudge_service.evaluate_and_log` | stress score, level, nudge type |
| ML | 🔒 `POST /ml/train` / `POST /ml/predict` | `ml_train` | completion probability |
| ML | 🔒 `POST /ml/train/procrastination` / `POST /ml/predict/procrastination` | `lgbm_train` | risk score |
| ML | 🔒 `POST /ml/retrain` / `POST /ml/update-profiles` | queues a Celery task | `{status: queued, task_id}` |
| ML | 🔒 `GET /ml/task-status/{id}` | `celery_app.AsyncResult` | poll a queued job |
| Analytics | 🔒 `POST /analytics/profile/build` / `GET /analytics/profile` | `analytics_service` | |
| Schedule (legacy) | 🔒 `GET /schedule/suggest/{task_id}` | `scheduler_service.suggest_slots` | top-3 ranked slots, no CP-SAT |
| Schedule (legacy) | 🔒 `POST /schedule/book` | `scheduler_service.book_slot` | conflict-checked manual booking |
| Schedule | 🔒 `POST /schedule/preference/move` | flips the CP-SAT-logged `SlotPreferenceFeedback` row | **the RL rejection signal** |
| Schedule | 🔒 `GET /schedule/day` | booked slots + free gaps for one day | |
| Schedule | 🔒 `DELETE /schedule/slots` | wipes all scheduled slots (not tasks) | |
| Schedule | 🔒 `GET` / `POST` / `DELETE /schedule/commitments[/{id}]` | fixed weekly commitments CRUD | |
| Schedule | 🔒 `POST /schedule/cpsat` | **`cpsat_bridge.run_cpsat_schedule`** — the real planner | scheduled / dropped / warnings / solve_status |

The app's own endpoint map — which of these it actually calls, and which it
doesn't — is kept in
[`../app files/docs/QUICK_REFERENCE.md`](../app%20files/docs/QUICK_REFERENCE.md)
(Endpoint Map section).

---

## 🗄️ Data model (`models/models.py`)

| Table | Holds |
|---|---|
| `users` | Firebase-linked account (`firebase_uid`), or a legacy local one (`hashed_password`) |
| `tasks` | title, category, energy requirement, duration, priority, deadline, status, procrastination/reschedule/skip counters |
| `task_events` | every state transition — `hour_of_day` + `day_of_week`, the ML/RL training signal |
| `stress_logs` | nudge inputs + computed stress score/level/type |
| `user_behavior_profiles` | nightly-aggregated completion rate, estimation error, peak focus hours |
| `scheduled_slots` | a placed block: task, start, end, `created_by` (`ai`/`user`), `is_active` |
| `slot_preference_feedback` | **the RL training table** — suggested slot + score, whether kept, what the user moved it to, the eventual reward |
| `fixed_commitments` | per-user recurring blocked time (replaces the old global timetable JSON) |

No Alembic migration is wired up day-to-day — `create_tables()` runs
`Base.metadata.create_all` at startup, which creates missing *tables* but never
alters an existing one's columns. A schema change on an existing table needs a
manual `ALTER` (or drop-and-recreate in dev).

---

## 🤖 ML models

| Model | Predicts | Library | Cold-start fallback |
|---|---|---|---|
| `ml/ml_train.py` | completion probability | XGBoost (AUC ~0.99 on training data) | `0.5` |
| `ml/lgbm_train.py` | procrastination risk | LightGBM (AUC ~0.95) | small hand-tuned formula from procrastination/skip/reschedule counts |

Both train on the same feature set from `ml/ml_features.py` (`estimated_duration,
priority, category_enc, energy_requirement_enc, procrastination_count,
reschedule_count, skip_count, hour_of_day, day_of_week`), pickled to
`ml/artifacts/` (gitignored). Retrained nightly (Sunday 02:00 UTC) or on demand
via `POST /ml/retrain`; skips if fewer than 10 resolved tasks exist.

---

## 🎯 RL system — slot preference

The scheduler doesn't just place tasks; it learns *when this user actually
follows through*. Full design and build log:
[`docs/RL_INTEGRATION_PLAN.md`](docs/RL_INTEGRATION_PLAN.md).

**Loop:**
1. `POST /schedule/cpsat` places a task → logs one `SlotPreferenceFeedback` row
   per slot (`was_kept=True`, the suggested hour, a real score).
2. If the user moves it, `POST /schedule/preference/move` flips that same row
   (`was_kept=False`, `user_chosen_start` set) — it does **not** insert a new
   row, and the row keeps the *originally suggested* hour, not where the task
   moved to.
3. Once the task resolves, the nightly `update_rl_rewards` job scores the row:

   ```
   completed & kept AURA's slot   → +20
   completed but user moved it    → +10
   abandoned & kept AURA's slot   →  -5
   abandoned after user moved it  → -10
   ```

4. `ml/slot_bandit.py` fits a Bayesian linear regression (Fourier hour-of-day
   basis, with an hour×energy interaction so the curve differs by kind of task)
   over every rewarded row, and `services/cpsat_bridge.sample_slot_policy` draws
   one posterior sample per scheduling run — so a whole day's plan is scored
   under one consistent hypothesis about the user, not a different guess per
   slot.
5. The resulting `{hour: bias}` feeds `compute_slot_scores`, affine-remapped
   into `[0, 100]` alongside energy match, completion probability and
   procrastination risk, before CP-SAT ever sees it.

**Why a bandit, not full RL:** CP-SAT already handles every state transition
(overlaps, deadlines, splitting); the learner only answers a contextual
preference question, and a single user generates on the order of 10² samples a
month — three to four orders of magnitude below what deep RL needs. See the
plan doc's "Why a bandit, not an MDP" section for the full argument.

**Kill switch:** `RL_KAPPA=0` (env var, default `1.0`) scales the learned term
to zero and plans with the pre-RL heuristic alone — no code change, and the
on/off mechanism an evaluation (e.g. an ABAB week-block test) would use.

---

## 🚀 Getting started

### 1. Start Postgres (and Redis, if you'll run Celery)

```bash
docker compose up -d db redis
```

> **Container name conflict across projects:** `docker-compose.yml` uses fixed
> container names (`aura_postgres`, `aura_redis`, …). If you have another
> checkout of this project running elsewhere, `docker compose up` here will
> fail with *"Conflict. The container name ... is already in use"*. Either
> `docker compose down` in the other checkout first, or add
> `COMPOSE_PROJECT_NAME=aura` to `.env` so this checkout adopts the same
> containers/volumes instead of trying to create new ones.

### 2. Python environment

```bash
python -m venv venv
# Windows:
.\venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate

pip install -r requirements.txt
```

`requirements.txt` is the pinned, known-working set — prefer it over
`requirements-core.txt` (an older, unpinned list) unless you have a specific
reason to diverge.

### 3. Configure `.env`

```bash
cp .env.example .env
```

`DATABASE_URL` has no default — the app raises before serving a single request
if it's unset. Use `localhost` when running uvicorn on the host (the normal dev
flow); use `db` only if the API itself runs inside `docker compose`.

### 4. Firebase service-account key

Every route behind `get_current_user` needs
`secrets/firebase-service-account.json` — without it they return **503**
(a server misconfiguration, not a 401, so a client doesn't loop trying to
re-authenticate). See [`secrets/README.md`](secrets/README.md) for how to
generate one from the Firebase console for project `saarthi-931dd`.

### 5. Run the server

```bash
uvicorn main:app --reload
```

### 6. Open the docs

```
http://localhost:8000/docs
```

> **Blank white page at `/docs`?** FastAPI's default Swagger UI loads its JS/CSS
> from `cdn.jsdelivr.net` / `unpkg.com` at runtime. If your network can't reach
> those (corporate proxy, restricted environment), the HTML shell loads (200)
> but nothing ever paints. Check with:
> ```bash
> curl -I https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js
> ```
> If that fails, either get that CDN allow-listed, or self-host the Swagger UI
> assets (`pip install swagger-ui-bundle` and point `FastAPI(docs_url=None)` +
> a custom `get_swagger_ui_html` route at the local files) — not yet wired up
> in this repo.

### Full stack via Docker (API + worker + beat included)

```bash
docker compose up -d
```

Builds the API image from the `Dockerfile` and runs Postgres, Redis, the API,
a Celery worker and Celery beat together — see `docker-compose.yml` for exact
service wiring (the API needs `db` and `redis` healthy first).

---

## 🔑 Testing without the Flutter app

Every protected route needs a real Firebase ID token — there is no dev auth
bypass in the code. Mint one via Firebase's REST API (needs the project's
**Web API key**, from Firebase console → Project Settings → General, distinct
from the service-account key):

```bash
curl -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=<WEB_API_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123","returnSecureToken":true}'
```

Take `idToken` from the response (expires in 1 hour) and paste it into
`/docs`'s **Authorize** button, or as `Authorization: Bearer <token>` on any
request.

---

## 🧪 Testing

No pytest — these are asyncio-runnable scripts (`if __name__ == "__main__":`),
each printing `ok` on success:

| File | Needs | Covers |
|---|---|---|
| `test_tz.py` | nothing external | IST timezone contract for the scheduler grid |
| `test_cp.py` | live Postgres + OR-Tools | one end-to-end `run_cpsat_schedule` timing smoke test |
| `test_no_overlap.py` | live Postgres + OR-Tools | CP-SAT never double-books a slot |
| `test_replan.py` | live Postgres + OR-Tools | re-planning doesn't evict tasks past deadline; multi-chunk slots all persist |
| `test_slot_bandit.py` | **nothing external** | the RL policy's math — contract, learning, credit assignment, sampler correctness |
| `test_rl_loop.py` | live Postgres + OR-Tools + Celery importable | the whole RL loop: plan → feedback → move → resolve → reward job → policy fit |

```bash
python test_slot_bandit.py      # pure math, run this one anywhere
python test_tz.py               # also no DB needed

# needs docker compose up -d db first:
python test_replan.py
python test_rl_loop.py
```

Each DB-backed test confines itself to a throwaway `user_id` and deletes its
own rows in a `finally` block, so it's safe to run against a shared dev
database.

---

## 📄 Documentation

- [`PIPELINE.md`](PIPELINE.md) — every route, every scoring formula
  with its exact weights, the CP-SAT model's variables/constraints/objective,
  the Celery beat schedule
- [`docs/RL_INTEGRATION_PLAN.md`](docs/RL_INTEGRATION_PLAN.md) — the RL system's
  full design, what's built vs. planned, and why the build diverges from the
  original design where it does
- [`docs/INTEGRATION_LOG.md`](docs/INTEGRATION_LOG.md) — phase-by-phase record
  of connecting this backend to the Flutter app, with the reasoning behind each
  decision (Firebase vs. backend JWT, per-user timetable vs. hardcoded JSON, …)
- [`secrets/README.md`](secrets/README.md) — how to obtain the Firebase key
- **Frontend:** [`../app files/README.md`](../app%20files/README.md) and its
  `docs/` folder (control flow, architecture diagrams, auth, quick reference)
