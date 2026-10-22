# SAARTHI

**S**mart **A**utomated **A**ssistant for **R**outine **T**ask **H**andling &
**I**ntelligent scheduling — a Flutter app that decides *when* your work happens,
backed by a FastAPI service (**AURA**) that runs a CP-SAT constraint solver and a
reinforcement-learning slot-preference model.

Two parts, one project:

| | Path | README |
|---|---|---|
| **Frontend** | [`app files/`](app%20files/) | [`app files/README.md`](app%20files/README.md) |
| **Backend** | [`backend/`](backend/) | [`backend/README.md`](backend/README.md) |

Each has its own deep documentation — file-by-file structure, architecture,
tech stack, testing, troubleshooting. **This file is the map, not the manual:**
read it to see how the two connect, then follow the link into whichever side
you're changing.

---

## How they connect

```
┌───────────────────┐  Firebase ID token (Bearer)   ┌───────────────────────────┐       ┌──────────────┐
│   Flutter app      │ ─────────────────────────────▶│   AURA backend (FastAPI)  │  SQL  │  PostgreSQL  │
│   app files/        │ ◀───────────────────────────── │   backend/                 │──────▶│  (Docker)    │
│                     │             JSON               │                           │       │              │
│  UI + Provider      │                                 │  CP-SAT solver (saarthi/) │       │  tasks       │
│  stores/repositories│                                 │  XGBoost + LightGBM       │       │  slots       │
│  (no local sched-   │                                 │  RL: Thompson sampling    │       │  feedback    │
│   uling logic)      │                                 │  (ml/slot_bandit.py)      │       │  users …     │
└──────────┬──────────┘                                 └─────────────┬─────────────┘       └──────────────┘
           │                                                           │
           │ signs in                                                  │ verifies the token
           ▼                                                           ▼
     ┌───────────────┐                                        ┌──────────────────┐
     │ Firebase Auth  │ ─────────────── same project ────────▶│ Firebase Admin SDK │
     └───────────────┘                                        └──────────────────┘
```

- **The app owns no scheduling logic and no local task store.** Every task,
  fixed commitment and scheduled block lives in the backend's PostgreSQL,
  scoped to the signed-in Firebase account. `SharedPreferences` on the device
  holds only a display name and an onboarding flag — see
  [`app files/README.md`](app%20files/README.md) (see its Architecture section).
- **Auth is Firebase end to end.** The app signs in with `firebase_auth`; the
  backend verifies that same token with the Firebase Admin SDK and
  auto-provisions a matching `users` row on first contact. Both sides must
  point at the **same Firebase project** (`saarthi-931dd`) — a key from a
  different project verifies nothing.
- **Scheduling is a request-response round trip, not client-side.** "Plan my
  day" is `POST /schedule/cpsat`; the backend's OR-Tools solver does the work
  and the app just renders the result. Moving a block in the UI would be
  `POST /schedule/preference/move` — wired on both sides but with no UI
  trigger yet — and doubles as the reward signal the RL system trains on.
  Full loop: [`backend/README.md`](backend/README.md) (see its RL system section).

---

## Run both together

```bash
# 1. Backend: database + API
cd backend
docker compose up -d db redis      # or `docker compose up -d` for the full stack incl. API/workers
cp .env.example .env               # fill in DATABASE_URL etc. — see backend/README.md
# needs secrets/firebase-service-account.json — see backend/secrets/README.md
python -m venv venv && ./venv/Scripts/activate   # or source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload

# 2. Frontend, in a second terminal
cd "app files"
flutter pub get
flutter run
```

The app is not usable without the backend running — the splash screen routes
to login, and every screen past that makes HTTP calls. `localhost` resolves
differently per target (simulator vs. Android emulator vs. physical device);
see [`app files/README.md`](app%20files/README.md) (Getting started section)
for the per-platform base URL.

---

## Where things live

| I want to... | Look at |
|---|---|
| Add or change a UI screen | [`app files/lib/features/`](app%20files/lib/features/), [`app files/docs/CONTROL_FLOW_DOCUMENTATION.md`](app%20files/docs/CONTROL_FLOW_DOCUMENTATION.md) |
| Add or change an API route | [`backend/main.py`](backend/main.py), [`backend/PIPELINE.md`](backend/PIPELINE.md) |
| Change how tasks get scheduled | [`backend/saarthi/`](backend/saarthi/) (the solver) and [`backend/services/cpsat_bridge.py`](backend/services/cpsat_bridge.py) (the bridge that scores its output) |
| Change what the scheduler learns from user behavior | [`backend/ml/slot_bandit.py`](backend/ml/slot_bandit.py), [`backend/docs/RL_INTEGRATION_PLAN.md`](backend/docs/RL_INTEGRATION_PLAN.md) |
| Understand a past design decision | [`backend/docs/INTEGRATION_LOG.md`](backend/docs/INTEGRATION_LOG.md) — phase-by-phase, with the *why* |
| Find which endpoints the app actually calls | [`app files/docs/QUICK_REFERENCE.md`](app%20files/docs/QUICK_REFERENCE.md) (Endpoint Map section) |

---

## Status

Both sides describe what's built vs. not yet wired up in their own READMEs
(frontend: "Not built yet"; backend: RL system's "Phase 1 — built so far" /
open evaluation decision). Check those before assuming a feature exists.
