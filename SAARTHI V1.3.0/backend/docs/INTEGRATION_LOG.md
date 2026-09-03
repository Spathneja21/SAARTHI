# AURA ↔ Saarthi Integration Log

A running record of the work connecting the **Saarthi Flutter app** to the **AURA
FastAPI backend**. Every step gets an entry: what changed, how it was done, **why
it was necessary**, and how it was verified.

This log lives in `Aura-backend` because it is the git-tracked repository of the
two, but it covers changes on **both** sides. Flutter-side entries are marked
`[app]` in their file list.

## Why this log exists

Six months from now, a diff can tell you *what* changed but never *why*. "Added a
`firebase_uid` column" is useless on its own; "added `firebase_uid` because the app
authenticates against Firebase and the server needed a stable key to match a
Firebase account to its local rows" is the sentence that lets the decision be
reconstructed, challenged, or defended. This doubles as the capstone's
design-decision record.

## Entry format

```markdown
## [Phase N.M] <what changed>
**Date:** YYYY-MM-DD
**Files:** path/to/file.py:12-40
**What:** the change, in one or two sentences.
**How:** the mechanism — what was added or replaced, and what it now calls.
**Why:** the reason this was necessary. What breaks without it, or what it unlocks.
**Verified:** the command run and what it returned.
```

## The architecture in one paragraph

The Flutter app authenticates against **Firebase**, then sends the resulting ID
token as a `Bearer` header on every request. The backend verifies that token with
the Firebase Admin SDK and looks up (or creates) a matching `users` row keyed by
`firebase_uid`. Task data lives in **PostgreSQL** as the single source of truth;
the phone keeps only a read cache. Creating and completing tasks accumulates rows
in `task_events`, which is what the **XGBoost** and **LightGBM** models train on.
"Plan my day" calls the **CP-SAT** scheduler, which fits pending tasks into the
gaps left by the user's fixed weekly commitments and writes `scheduled_slots` rows
the app renders as time blocks.

**Boundary that this work respects:** the *brain* (`ml/`, `saarthi/`, and the
scoring formulas in `services/`) is not modified. Only the *doorway* — the route
signatures in `main.py` and the schemas in `schemas/` — is reshaped. The brain
reads from the database, never from a URL, so it cannot tell the difference.

---

# Entries

## [Phase 0] Created this log
**Date:** 2026-09-02
**Files:** `docs/INTEGRATION_LOG.md`
**What:** Added the integration log itself, with its entry format and a summary of
the target architecture.
**How:** New `docs/` directory in the backend repo. Work happens on the
`feat/flutter-integration` branch, cut from a clean `main`.
**Why:** The integration spans two codebases and a series of decisions with real
trade-offs (Firebase vs. backend JWT, per-user timetable vs. hardcoded JSON,
server-side vs. client-side status transitions). Recording the reasoning as the
work happens is the only way it survives; reconstructing it afterwards from diffs
loses exactly the part that matters.
**Verified:** N/A — documentation only.

## [Phase 1.1] Secrets can no longer be committed
**Date:** 2026-09-02
**Files:** `.gitignore`, `.dockerignore`
**What:** Added `secrets/` and `*-service-account.json` to both ignore files. Also
fixed an existing typo, `.vscode/s` → `.vscode/`.
**How:** Straight additions to both lists.
**Why:** Phase 2 introduces a Firebase service-account private key. That key grants
the ability to mint and verify tokens for the whole Firebase project, so it must be
impossible to commit *before* it exists on disk — adding the rule afterwards is how
keys leak. It is in `.dockerignore` too because secrets baked into an image travel
anywhere that image goes; the key will be bind-mounted at runtime instead. The
`.vscode/s` typo meant the VS Code directory was never actually ignored.
**Verified:** `git status --short` shows no untracked `secrets/` or `.env`.

## [Phase 1.2] Environment configuration
**Date:** 2026-09-02
**Files:** `.env.example` (new), `.env` (new, gitignored), `core/database.py:5-18`
**What:** Documented every environment variable in a committed `.env.example`,
created a working local `.env`, made a missing `DATABASE_URL` fail with a clear
message, and moved SQLAlchemy's `echo` behind a `SQL_ECHO` variable (default off).
**How:** `core/database.py` already called `load_dotenv()`; added an explicit guard
after the `os.getenv` call and replaced the hardcoded `echo=True`.
**Why:** `DATABASE_URL` was read with no default, so running outside Docker crashed
at *import* time with `create_async_engine(None)` — an error that names neither the
variable nor the fix, and which the README's setup steps do not mention. There was
also no `.env.example`, so a new machine had no way to discover which variables
exist. `echo=True` logged every SQL statement the app ever ran, which buries real
errors; it stays available for debugging via the variable.
**Verified:** Deferred — no Python runtime on this machine yet (see Phase 1.4).

## [Phase 1.3] CORS middleware
**Date:** 2026-09-02
**Files:** `main.py:5`, `main.py:36-46`
**What:** Added `CORSMiddleware` with permissive development settings.
**How:** `app.add_middleware(CORSMiddleware, allow_origins=["*"], ...)` immediately
after the `FastAPI(...)` construction. `allow_credentials` is deliberately `False`,
because browsers reject the combination of credentialed requests with a `*` origin.
**Why:** There was no CORS configuration anywhere in the project. Native Android and
iOS clients ignore CORS, so this changes nothing for the phone — but Flutter Web is
blocked by the browser on its very first request without it, with an error that
looks like a network failure rather than a policy rejection. Cheap to add now,
confusing to diagnose later. Must be narrowed to real origins before deployment.
**Verified:** Deferred — see Phase 1.4.

## [Phase 1.4] BLOCKED: no runtime on this machine
**Date:** 2026-09-02
**Files:** —
**What:** Phase 1's changes are written but **not yet executed**. This machine has
no Docker, no PostgreSQL, and no suitable Python — only the macOS system Python
3.9.6, while the codebase requires 3.11 (the `str | None` annotation syntax used
throughout `main.py` is a syntax error before 3.10, and the Dockerfile pins
`python:3.11-slim`).
**How:** N/A.
**Why:** Recorded because the project was previously developed on Linux (see
`saarthi/cmds.md`, which references a `/media/...` path and a `.venv-linux` conda
environment). None of that carried over to this Mac, so an environment has to be
established before any verification step in the plan can run.
**Verified:** `python3 --version` → 3.9.6; `import fastapi` → ModuleNotFoundError;
`docker --version` → command not found. Homebrew *is* present at
`/opt/homebrew/bin/brew`. Flutter *is* present at `/opt/homebrew/share/flutter`, so
only the backend side needs an environment.
**Resolution:** installing Docker Desktop (`brew install --cask docker-desktop`),
chosen over a Homebrew Python because the app also needs PostgreSQL and Redis, which
`docker-compose.yml` already defines, and because it matches the original Linux setup.

## [Phase 2.1] `firebase_uid` on the users table
**Date:** 2026-09-02
**Files:** `models/models.py:69-77`
**What:** Added a nullable, unique, indexed `firebase_uid` column to `User`, and made
`hashed_password` nullable.
**How:** Two `mapped_column` changes. No other model touched.
**Why:** `firebase_uid` is the join key between a Firebase account and its local rows.
The app authenticates against Firebase, so the server needs a stable identifier to
map "this verified token" onto "these tasks" — and it must be Firebase's uid rather
than the email, because a user can change their email while the uid never changes.
It is nullable so accounts created earlier through `/register` remain valid, and
unique so two rows can never claim the same Firebase account. `hashed_password`
became nullable because Firebase holds the credential; storing a dummy hash instead
would falsely imply a local password exists.
**Verified:** Deferred until the database is running.

## [Phase 2.2] Firebase Admin token verification
**Date:** 2026-09-02
**Files:** `core/firebase_auth.py` (new), `requirements.txt:25-27`,
`requirements-core.txt:10`
**What:** New module that initializes the Firebase Admin SDK from a service-account
key and exposes `verify_firebase_token(id_token) -> dict`.
**How:** `credentials.Certificate(path)` + `firebase_admin.initialize_app(cred)`,
guarded on `firebase_admin._apps` so uvicorn's reloader cannot double-initialize
(a second `initialize_app` raises). A dedicated `FirebaseNotConfigured` error
distinguishes a missing key from a bad token.
**Why:** Verification has to be cryptographic, not a lookup. The ID token is a JWT
signed by Google; the SDK checks that signature against Google's rotating public
keys along with expiry, audience and issuer. This is why the design sends a *token*
rather than a uid, even though `docs/AUTHENTICATION.md` §5 suggests sending the uid:
anyone can claim a uid, but only Firebase can sign for one, so trusting a
client-supplied uid would let any caller impersonate any user.
**Verified:** Deferred — needs both a Python runtime and the service-account key.

## [Phase 2.3] `get_current_user` now verifies Firebase tokens
**Date:** 2026-09-02
**Files:** `core/dependencies.py` (rewritten)
**What:** Replaced local JWT decoding with Firebase verification, and added
find-or-create provisioning of the local `User` row.
**How:** Kept the existing `HTTPBearer` extraction, then: verify the token → look up
by `firebase_uid` → failing that, adopt an existing row with the same email by
setting its `firebase_uid` → failing that, insert a new row with a username derived
from the email local-part. Username collisions get a numeric suffix, then a uuid
fallback. An `IntegrityError` on insert is caught and re-read, since two concurrent
first-requests from one account can race.
**Why:** Every protected route already depends on this one function, so switching
identity providers here switches the whole API at once with no route changes.
Auto-provisioning removes any need for the app to "also register with the backend" —
a step that could fail separately from Firebase signup and leave an account that can
log in but owns nothing. Three deliberate status-code choices: a missing key returns
**503** rather than 401, because it is the server that is broken and a 401 would send
the app into a re-authentication loop it can never win; a deactivated account returns
**403** rather than 401, because the token was valid and retrying will not help; and
a malformed token returns **401**. Also fixes a latent bug in the previous version,
where `uuid.UUID(user_id)` sat outside the `try` and turned a malformed token into a
500 instead of a 401.
**Verified:** Deferred until the database is running.

## [Phase 2.4] Guarded `/login` against null password hashes
**Date:** 2026-09-02
**Files:** `main.py:76-91`
**What:** `/login` now rejects accounts whose `hashed_password` is None before
calling `verify_password`.
**How:** Split the combined condition into a null check followed by the bcrypt check.
**Why:** A regression introduced by Phase 2.1. Once `hashed_password` became
nullable, a Firebase-provisioned account reaching `/login` would pass `None` into
`bcrypt.checkpw`, raising `AttributeError` and returning **500** — leaking that the
account exists, and crashing where it should simply refuse. Firebase accounts have
no local credential and must authenticate through Firebase.
**Verified:** Deferred until the database is running.

## [Phase 2.5] Service-account key handling
**Date:** 2026-09-02
**Files:** `docker-compose.yml:33-45`, `secrets/README.md` (new), `.gitignore:11-13`
**What:** The `api` service now receives `FIREBASE_CREDENTIALS_PATH` and mounts
`./secrets` read-only at `/app/secrets`. Added a `secrets/README.md` with retrieval
instructions, tracked via a gitignore negation while the keys themselves stay ignored.
**How:** `- ./secrets:/app/secrets:ro` alongside the existing `ml/artifacts` mount.
`.gitignore` became `secrets/*` plus `!secrets/README.md`.
**Why:** The key must reach the container without ever entering the image. `secrets/`
is in `.dockerignore`, so a `COPY` would not include it anyway — but the deeper
reason is that an image layer is permanent and portable: anyone who later pulls or
receives that image gets the key, and deleting the file in a subsequent layer does
not remove it from history. A read-only runtime mount keeps the key on the host.
The README is tracked because the *instructions* are not secret, and a future reader
finding an empty ignored directory would have no idea what belongs there.
**Verified:** `git check-ignore -v secrets/firebase-service-account.json` →
matched by `.gitignore:13`, confirming a real key cannot be committed.
`git status --short` shows no `.env` and no key file.

## [Phase 3.1] Request and response schemas
**Date:** 2026-09-02
**Files:** `schemas/schemas.py:1-8`, `schemas/schemas.py:32-121`
**What:** Added `TaskCreate`, `TaskUpdate`, `TaskRead`, `TransitionRequest`,
`BookSlotRequest`, `MoveSlotRequest`, `CpsatRequest` and `NudgeRequest`.
**How:** Plain Pydantic models with `Field` constraints; `TaskRead` uses
`from_attributes` so it can be built straight from an ORM `Task`.
**Why:** Every write endpoint except `/register` and `/login` took bare scalar
arguments, which FastAPI treats as **query parameters**. Three concrete problems
with that, beyond style: task titles end up in server access logs, so a title like
"Therapy appointment" leaks into infrastructure that is not treated as sensitive;
an ISO-8601 offset such as `+05:30` is decoded as a *space* unless escaped to
`%2B` on every single call, silently shifting deadlines by five and a half hours;
and there is no schema for OpenAPI to publish, so the generated `/docs` could not
describe a request body for the Flutter side to code against.
**Verified:** `ast.parse` clean. Full runtime check pending an environment.

## [Phase 3.2] Task CRUD and safe outcome endpoints
**Date:** 2026-09-02
**Files:** `services/task_service.py:169-330`, `main.py:99-240`
**What:** Added `update_task`, `delete_task` and `resolve_task` to the service, and
the routes `GET /tasks/{id}`, `PATCH /tasks/{id}`, `DELETE /tasks/{id}`,
`POST /tasks/{id}/complete`, `/postpone` and `/skip`. Converted `POST /tasks`,
`PATCH /tasks/{id}/transition`, `POST /nudge/evaluate`, `POST /schedule/book`,
`POST /schedule/preference/move` and `POST /schedule/cpsat` to JSON bodies.
`GET /tasks` and `POST /tasks` now return the full `TaskRead`.
**How:** `resolve_task` walks the state machine with a breadth-first search over
`VALID_TRANSITIONS` rather than a hardcoded route, so it stays correct if the state
machine is edited. `PATCH` uses `model_dump(exclude_unset=True)` to distinguish an
omitted field from an explicit null. `delete_task` soft-deletes dependent
`ScheduledSlot` rows before removing the task.
**Why:** There was previously no way to fetch a single task, edit one, or delete one,
and `GET /tasks` returned only five fields — omitting `deadline` and
`estimated_duration`, without which the timeline cannot size or place a block.

The `/complete` endpoint exists for a subtler reason. `VALID_TRANSITIONS` forbids
`draft → completed`; the legal route is `draft → scheduled → in_progress →
completed`. Letting the client fire those three calls itself looks harmless but
corrupts data: `transition_task` stamps `started_at = now` on entering IN_PROGRESS
and then computes `actual_duration = now - started_at` on COMPLETED, so a fast
client-side walk records every task as taking ~0 minutes.

**A correction to an earlier assumption.** While implementing this I checked
`ml/ml_features.py:24-26` and found `extract_features` joins task_events on
`event_type = 'task_created'` only — one row per task. So intermediate transitions
do *not* add spurious training rows, and the earlier claim that they would "poison
the training data" was wrong. The real damage is narrower but still worth
preventing: `analytics_service.build_behavior_profile` filters completed tasks on
`actual_duration IS NOT NULL`, so a fabricated `0` passes as a genuine measurement
and skews `avg_estimation_error_minutes`, whereas a NULL is cleanly excluded.
`resolve_task` therefore seeds `started_at` from the task's real `ScheduledSlot`
start when one exists, and deliberately leaves both `started_at` and
`actual_duration` NULL when the task was never scheduled — recording "unknown"
instead of inventing a number.
**Verified:** `ast.parse` clean. Behavior check pending an environment; verification
step 9 in the plan covers it.

## [Phase 3.3] Malformed UUIDs return 422 instead of 500
**Date:** 2026-09-02
**Files:** `main.py` — `/tasks/{id}/history`, `/ml/predict`,
`/ml/predict/procrastination`, `/schedule/suggest/{id}`
**What:** Changed `task_id: str` to `task_id: uuid.UUID` on four routes and removed
the now-redundant `uuid.UUID(task_id)` conversions.
**How:** Let FastAPI parse and validate the path parameter.
**Why:** Each of these called `uuid.UUID(task_id)` in the route body, outside any
`try`. A malformed id therefore raised `ValueError` and surfaced as **500 Internal
Server Error** — which reads as "the server is broken" when the truth is "you sent a
bad id". FastAPI now rejects it with a 422 and a field-level message before the
handler runs. `/ml/task-status/{task_id}` keeps `str` deliberately: that parameter is
a Celery job id, not a database key.
**Verified:** `grep -n "uuid.UUID(" main.py` returns no remaining call sites.

## [Phase 3.4] Guard clauses on slot times
**Date:** 2026-09-02
**Files:** `main.py` — `/schedule/book`, `/schedule/preference/move`
**What:** Both endpoints now reject a range whose end is not after its start.
**How:** An explicit check returning 422 before touching the database.
**Why:** `/schedule/preference/move` previously accepted any pair of timestamps and
wrote them straight to the row, so an inverted or zero-length slot could be
persisted. A slot with `end <= start` corrupts every downstream consumer at once:
`find_free_gaps` computes negative durations, the CP-SAT bridge builds an interval
with a negative size, and the timeline renders a block with negative height.
**Verified:** `ast.parse` clean; runtime check pending.

## [Phase 3.5] BLOCKED: Docker install needs an interactive password
**Date:** 2026-09-02
**Files:** —
**What:** `brew install --cask docker-desktop` downloaded and installed, then failed
on its final step and rolled back.
**How:** The cask symlinks `docker-credential-osxkeychain` into `/usr/local/bin`,
which requires `sudo`. There is no TTY in a background shell, so `sudo` could not
prompt, and Homebrew reverted the whole install and removed `/Applications/Docker.app`.
**Why:** Recorded because the failure is misleading in two ways. The command reported
**exit code 0** — the status came from the `| tail -25` at the end of the pipeline,
not from `brew` — so it looked successful. And the ~1 GB download *is* still cached
in `~/Library/Caches/Homebrew/downloads`, so re-running is fast and does not
re-download. The fix is for the user to run the command in their own terminal, where
`sudo` can prompt.
**Verified:** `which docker` → not found; `/Applications/Docker.app` absent.

## [Phase 3.6] RESOLVED: Docker would not start — Rosetta
**Date:** 2026-09-03
**Files:** `~/Library/Group Containers/group.com.docker/settings-store.json`
(outside the repo; backed up alongside as `.bak-<timestamp>`)
**What:** After the user re-ran the install with `sudo` available, Docker Desktop
launched but its Linux VM never started. Setting
`UseVirtualizationFrameworkRosetta: false` fixed it; the daemon came up in ~20s.
**How:** Quit Docker Desktop first — it rewrites its settings file on exit, so an
edit made while running is silently discarded — then added the key and relaunched.
**Why:** Two things made this hard to read from the UI. First, the Rosetta dialog
looked optional ("Retry or continue without Rosetta"), but `monitor.log` showed
Rosetta installation is a *step inside VM startup*:
`engine linux/virtualization-framework failed to start: installing Rosetta:
VZErrorDomain Code=1`. When it failed the engine never started, which surfaced only
as `still waiting for the engine to respond to _ping after 9m36s: HTTP 503`.
Second, clicking "Disable Rosetta" never persisted — `settings-store.json` contained
no Rosetta key at all, so each relaunch fell back to the default (enabled) and
repeated the same failure.

Rosetta only accelerates **amd64** images on Apple Silicon. Every image here —
`postgres:16`, `redis:7-alpine`, `python:3.11-slim` — publishes a native arm64
build, so disabling it costs nothing. The underlying install failure is likely
macOS 26 related, where Rosetta 2 is being wound down.
**Verified:** `docker info` succeeds; `docker compose up -d db redis` →
`aura_postgres` and `aura_redis` both report `Up (healthy)`;
`pg_isready -U aura_user -d aura_db` → accepting connections.

## [Phase 4.1] Per-user fixed commitments
**Date:** 2026-09-03
**Files:** `models/models.py:274-330`, `schemas/schemas.py:124-171`,
`main.py:732-795`, `services/cpsat_bridge.py:120-180`,
`scripts/seed_commitments.py` (new)
**What:** Added a `FixedCommitment` model and a `CommitmentRecurrence` enum
(`one_time` / `daily` / `weekly`), the endpoints `GET`, `POST` and
`DELETE /schedule/commitments`, and rewrote `cpsat_bridge.timetable_events` to
read a user's rows from the database instead of `saarthi/fixed_tasks.json`.
Added a one-off seed script to migrate the JSON into a chosen user's rows.
**How:** `timetable_events` became `async` and now takes `user_id` and `db`; the
weekday-to-date projection logic was reused verbatim, only the data source changed.
`load_fixed_events` awaits it. `TIMETABLE_PATH` and the `json` import were removed
from `cpsat_bridge`, and the path moved into the seed script.
**Why:** `fixed_tasks.json` was a single hardcoded university timetable that
`cpsat_bridge` applied to **every** account — the code even said so in a comment.
That makes the app single-user by construction: a second user's scheduler would
carve their day around someone else's class times, and there was no API to change
it. This is the difference between a demo and a multi-user app.

Three specific design choices:

*Minutes from midnight, not timestamps.* A recurring commitment has no single date
— it is a wall-clock pattern projected onto concrete days. This also matches the
Flutter client's existing `ScheduleEntry.startMinutes` getter, so neither side has
to convert.

*A `recurrence` column, even though only weekly is wired to UI today.* The Flutter
`ScheduleStore.addEntry` is public and `ScheduleEntry.occursOn` already handles all
three kinds. A weekday-only table would silently discard daily and one-time
entries — the worst kind of failure, since the write would appear to succeed.

*Soft delete.* Deactivating rather than removing keeps a past schedule explicable:
a slot placed around a commitment still makes sense later, instead of appearing to
have avoided nothing.

Also note `end_minute` allows 1440 and the events are built by adding a
`timedelta` to midnight rather than via `time.fromisoformat`, so a commitment
ending at midnight rolls into the next day instead of raising on hour 24.
**Verified:** See Phase 4.4 — commitment isolation confirmed with two users.

## [Phase 4.2] Fixed `test_no_overlap.py`, broken by the signature change
**Date:** 2026-09-03
**Files:** `test_no_overlap.py:1-70`
**What:** The test called `timetable_events(start, end)`; Phase 4.1 changed that to
`timetable_events(user_id, db, start, end)`, so it failed with
`TypeError: missing 2 required positional arguments`. The test now builds its fixed
events from the JSON fixture through a local `events_from_fixture` helper.
**How:** Moved the weekday-projection loop into the test file and dropped the
`cpsat_bridge` import.
**Why:** The invariant under test — *the packer must never place a chunk on top of a
fixed event* — belongs to the packer, not to wherever the events came from. Wiring
the test to a database session would have turned a fast pure test into an
integration test needing Postgres and a seeded user, which makes it slower and more
likely to be skipped. Rebuilding the same realistic densely-booked week from the
JSON fixture keeps the coverage identical.
**Verified:** `python test_no_overlap.py` → `ok`.

## [Phase 4.3] `actual_duration` came out NEGATIVE — reverted the slot-seeding
**Date:** 2026-09-03
**Files:** `services/task_service.py:262-330`
**What:** Phase 3.2's `resolve_task` seeded `started_at` from the task's scheduled
slot. End-to-end testing recorded **`actual_duration = -932` minutes** on a
60-minute task. Replaced with: keep the duration only when the task was genuinely
started, otherwise leave both fields NULL.
**How:** Capture `was_really_started = task.started_at is not None` *before* the
state-machine walk, and null both fields afterwards unless it was true.
**Why:** The slot-seeding was wrong in a way that only running it revealed. A
scheduled slot is normally in the **future** — the CP-SAT plan for later today or
next week — so `actual_duration = now - started_at` computed *backwards*. That is
worse than the fabricated `0` the seeding was introduced to prevent, since a
negative number is not merely uninformative but actively skews
`avg_estimation_error_minutes` in the opposite direction.

The deeper mistake was trying to infer a duration at all. A single "mark done" tap
genuinely cannot tell us how long the work took, and no amount of cleverness with
slot times changes that. The state machine already models this correctly:
`started_at` is stamped on entering IN_PROGRESS, which only happens when the user
actually starts. So the honest rule is to keep `actual_duration` when a real
IN_PROGRESS period exists and record NULL otherwise.

**Implication for the app:** to collect estimation-accuracy data at all, the UI
needs a "start" action, not just a done-checkbox. Tapping done alone will always
produce NULL — correctly.
**Verified:** See Phase 4.4.

## [Phase 4.4] Full runtime verification
**Date:** 2026-09-03
**Files:** `test_pipeline.py` (new, promoted from a scratch script)
**What:** Brought up Postgres, Redis and the API in Docker and ran the whole chain.
**How:** `docker compose up -d`, then a seeded end-to-end script that creates two
users, gives one of them weekday 09:00-12:00 commitments, creates five tasks with
varied category and energy, runs CP-SAT, and asserts on the results.
**Why:** Everything through Phase 4.1 had only been syntax-checked. The two bugs
found here (4.2 and 4.3) were both invisible to `ast.parse` and to code review —
the negative duration in particular only appears once real future-dated slots exist.
Keeping the script in the repo as `test_pipeline.py` means the next refactor
re-checks the same invariants.

Results:
- API boots; `GET /` returns `{"message": "AURA is alive"}`; `/docs` returns 200.
- Schema: `users.firebase_uid` exists with `ix_users_firebase_uid` UNIQUE;
  `hashed_password` is nullable; `fixed_commitments` created with a
  `commitmentrecurrence` enum of `ONE_TIME`/`DAILY`/`WEEKLY`.
- Auth: no header → **401**; bad token with no service-account key → **503** with
  the actionable message naming the expected path. (The Phase 2.3 note predicted
  403 for a missing header; FastAPI 0.138.2 returns 401. Comment corrected in
  `core/dependencies.py`.)
- OpenAPI: every write endpoint now advertises a `requestBody`. The only remaining
  query parameters are UUIDs and dates on GET routes, which is appropriate.
- **The brain is unchanged**: CP-SAT returned `OPTIMAL` in 329 ms, scheduling 6
  chunks from 5 tasks with 0 dropped, correctly splitting the 120-minute task into
  two sessions. `test_tz.py`, `test_no_overlap.py` and `test_replan.py` all pass.
- Commitment isolation: Alice 6 fixed events over 7 days, Bob 0 — Bob does not
  inherit Alice's timetable, which was the entire point of Phase 4.
- No scheduled slot overlapped a commitment.
- `avg_estimation_error_minutes` stayed in a plausible range rather than absorbing
  a fabricated value.
**Verified:** `test_tz.py`, `test_no_overlap.py`, `test_replan.py`,
`test_pipeline.py` — all PASS.

## [Phase 4.5] Pinned firebase-admin
**Date:** 2026-09-03
**Files:** `requirements.txt:26`
**What:** Replaced the provisional `firebase-admin>=6.5.0` with `==7.5.0`.
**Why:** `requirements.txt` is a fully-pinned freeze; the floor was a placeholder
until an install revealed the real resolved version. Leaving a range in a lockfile
means two machines can silently get different builds.
**Verified:** The Docker build installed `firebase-admin-7.5.0`, and all ML wheels
resolved as prebuilt **linux/arm64** binaries with no source compilation —
`ortools-9.15.6755`, `xgboost-3.2.0`, `lightgbm-4.6.0`, `scipy-1.17.1`.

## [Phase 4.6] Service-account key installed — and one rotated after exposure
**Date:** 2026-09-03
**Files:** `secrets/firebase-service-account.json` (gitignored, not in the repo)
**What:** Installed the Firebase Admin service-account key, so token verification
is live. The first key generated (`private_key_id` starting `b96640d5ec`) was
**exposed and had to be revoked**; the installed key is a freshly issued
replacement (`7bed676aa13226…`).
**How:** Revoked the exposed key in Google Cloud IAM → Service Accounts → Keys,
issued a new JSON key, moved it to `secrets/firebase-service-account.json` with
mode `600`, and deleted the revoked file. Validated structurally — `type`,
`project_id`, `client_email`, `private_key_id` — without ever printing
`private_key`. Then restarted the API.
**Why the rotation was necessary:** the key's full JSON, including the
`private_key` PEM block, was pasted into a chat transcript. That credential holds
*Firebase Authentication Admin* and *Service Account Token Creator* on the project,
so possession allows minting a valid ID token for **any** user and reading or
modifying the entire user table — it is equivalent to a project root password.
Deleting the local copy would not have helped; only revocation in IAM invalidates a
key that has already left the machine. Rotation took under a minute and the exposure
window was short and private, so the practical risk was low, but the correct
response to a leaked private key is always to revoke rather than to assess.

A related trap worth recording: on the IAM **permissions** page the visible action
is "Remove access", which strips the service account's *roles*
(Firebase Admin SDK Administrator Service Agent, Firebase Authentication Admin,
Service Account Token Creator) and would break Admin SDK access project-wide.
Key management lives on a different page — IAM & Admin → **Service Accounts** →
the account → **Keys** tab — and revoking a key there leaves the roles intact.
**Verified:** In-container, `FIREBASE_CREDENTIALS_PATH` resolves to
`/app/secrets/firebase-service-account.json` and
`firebase_admin.get_app().project_id` → `saarthi-931dd`, matching the Flutter app's
`firebase_options.dart`. Protected endpoints flipped from **503** (key missing) to
**401 "Invalid or expired token"** for a bogus token — the SDK is now performing
real signature verification. No credential errors in the API logs.
`git check-ignore` confirms the key is excluded by `.gitignore:13`.

## [Phase 4.7] Full authenticated endpoint sweep — 71 checks
**Date:** 2026-09-03
**Files:** `scripts/api_sweep.sh` (new), `scripts/mint_test_token.py` (new)
**What:** Exercised every route with **real Firebase ID tokens** for two separate
users, covering happy paths, validation failures, the state machine, and cross-user
isolation. 71 checks, all passing.
**How:** The Admin SDK can only issue *custom* tokens, so
`scripts/mint_test_token.py` does the two-step exchange a real client does:
`auth.create_custom_token(uid)` → POST to the identitytoolkit
`signInWithCustomToken` endpoint with the app's public Web API key → a genuine ID
token. That token travels the same verification path as production traffic, which
is what makes the sweep meaningful rather than a mock.
**Why:** Phase 4.4 verified the internals by calling service functions directly,
bypassing HTTP entirely. That leaves the whole doorway — Pydantic validation, status
codes, auth wiring, ownership checks — unverified. Given that Phase 3 reshaped
exactly that layer, it needed exercising through real requests.

Coverage worth noting:
- **Auth**: no header → 401, malformed token → 401, valid token → 200 with a
  user row auto-provisioned from the token's claims.
- **Validation**: missing required field, bad enum value, `estimated_duration` 0,
  empty title, `priority` 99, empty PATCH body, `weekday` 7, weekly commitment
  with no weekday, one-time with no date, `end_minute <= start_minute`,
  `heart_rate` 900 — all correctly 422 rather than 500 or silent acceptance.
- **State machine**: `draft → completed` correctly rejected with 422;
  `draft → scheduled` accepted; history accumulated ≥2 events.
- **Outcomes**: `/complete` on a never-started task leaves `actual_duration` NULL
  (the Phase 4.3 fix holding under HTTP); `/complete` twice is idempotent;
  `/skip` bumps both `skip_count` and `procrastination_count`.
- **Scheduling**: CP-SAT returns OPTIMAL with and without an explicit `task_ids`
  body; `/schedule/book` accepts a valid slot, returns 409 on an overlap and 422 on
  an inverted range; `/preference/move` returns 404 for an unknown slot.
- **Cross-user isolation**: Bob cannot read, patch, delete or complete Alice's
  task (404/422), sees zero of her tasks and zero of her commitments, and cannot
  delete her commitment. This is the property the whole per-user timetable work
  existed to establish, now proven through the API rather than inferred.
- **Celery**: `/ml/retrain` and `/ml/update-profiles` queue successfully against
  the Redis broker.

**One real bug found and fixed:** `DELETE /schedule/commitments/{id}` returned
**204 on an already-deleted commitment** instead of 404. The lookup matched on id
and user but not on `is_active`, so a soft-deleted row was found again and
"deleted" a second time. A caller could not distinguish "deleted it" from "there
was nothing there", which would let a UI show a success toast for a no-op.
Fixed by adding `is_active == True` to the query — a soft-deleted row is gone as
far as the API is concerned.

Five other apparent failures in the first run were **defects in the test harness**,
not the API: nested command substitution inside the assertion function's argument
list produced a stray extra token, so `/schedule/book` and `/preference/move` were
misreported. Verified by hand (`/schedule/book` → 200 with a slot id), then the
harness was rewritten to assign each status to a variable first. Recorded because
the first instinct on a red test is to suspect the code, and here five of six reds
were the test.
**Verified:** `bash scripts/api_sweep.sh` → **PASSED: 71  FAILED: 0**.
`test_tz.py`, `test_no_overlap.py`, `test_replan.py`, `test_pipeline.py` all pass
after the fix.

---

# Backend status: Phases 0-4 complete and verified

| Phase | Scope | State |
|---|---|---|
| 0 | This log | ✅ |
| 1 | `.env`, CORS, config guards | ✅ verified |
| 2 | Firebase ID-token verification, auto-provisioning | ✅ verified with real tokens |
| 3 | JSON request bodies, task CRUD, safe outcome endpoints | ✅ 71-check sweep |
| 4 | Per-user fixed commitments | ✅ isolation proven across two users |

The brain was never modified: `ml/`, `saarthi/` and the scoring formulas in
`services/` are byte-identical to `main` apart from `cpsat_bridge.timetable_events`,
whose *data source* changed while its projection logic was reused verbatim.
CP-SAT still returns OPTIMAL in ~330 ms.

---

## [Phase 5.1] Flutter API layer
**Date:** 2026-09-03
**Files:** `[app] pubspec.yaml`, `[app] lib/core/api/api_config.dart`,
`[app] lib/core/api/api_client.dart`, `[app] lib/core/api/backend_time.dart`,
`[app] lib/core/api/dto/{task,slot,commitment}_dto.dart`,
`[app] lib/core/data/repositories/{task,schedule}_repository.dart`
**What:** Added `http` and `provider` dependencies, then built the client layer:
a platform-aware base URL, a JSON client that attaches the Firebase ID token,
DTOs mirroring the backend's wire format, and two repositories.
**How:** `ApiClient` has two constructors — the default pulls tokens from
`FirebaseAuth.instance`, and `ApiClient.withTokenProvider` accepts any
`Future<String?> Function()`. Errors are split into `ApiException` (carrying the
status plus `isUnauthorized` / `isNotFound` / `isValidationError` /
`isServerMisconfigured`) and `ApiUnreachableException`.
**Why the specific choices:**

*Platform-aware base URL.* `localhost` means something different on every
target. The Android emulator sits behind its own NAT, so the host is only
reachable at `10.0.2.2`; on iOS Simulator and desktop, `localhost` is correct.
Getting this wrong produces "connection refused" with nothing pointing at the
cause. A `--dart-define=AURA_API_BASE_URL=...` override handles physical devices
on the LAN.

*Tokens fetched per request, not cached.* `user.getIdToken()` already returns a
cached value until roughly five minutes before expiry and refreshes
transparently. Caching again in the client would only risk sending a stale
token, and this is precisely the problem the backend's own 30-minute JWT had —
the reason Firebase won the auth decision in the first place.

*Distinguishing 503 from 401.* A missing service-account key is a *server*
fault. Treating it as an auth failure would send the app into a
re-authentication loop it can never win, so `isServerMisconfigured` is separate
and must not trigger a sign-out.

*Flattening FastAPI's error shapes.* A raised `HTTPException` gives
`{"detail": "..."}` while a validation failure gives `{"detail": [{"loc": [...],
"msg": "..."}]}`. Without flattening, the UI would show users a raw list of maps.

*Injectable token provider.* Plain `flutter test` has no platform channels, so
`FirebaseAuth.instance` cannot work there. Without this seam the entire client,
every DTO, and all error handling would be untestable outside a running app —
and Phase 5.3 shows that would have hidden a real bug.
**Verified:** `flutter analyze` clean; see Phase 5.3.

## [Phase 5.2] Android manifest networking
**Date:** 2026-09-03
**Files:** `[app] android/app/src/main/AndroidManifest.xml`
**What:** Added `android.permission.INTERNET` and
`android:usesCleartextTraffic="true"`.
**How:** Permission at the manifest root, attribute on `<application>`.
**Why:** Flutter's template declares `INTERNET` **only** in the `debug` and
`profile` manifests, which are not merged into a release build. Networking
therefore works throughout development and then fails on the first release
build — a failure mode that appears long after the cause. Separately, Android 9+
blocks cleartext HTTP by default, and the local backend is plain `http://`;
that rejection also surfaces as a generic connection error rather than a policy
message. The cleartext attribute must be removed once the backend is behind
HTTPS.

A first attempt at this edit put an XML comment *inside* the `<application>`
start tag, between attributes, which is not valid XML. Caught by parsing the
file rather than eyeballing it.
**Verified:** `xml.dom.minidom` parses the manifest;
`uses-permission` → `['android.permission.INTERNET']`;
`usesCleartextTraffic` → `true`.

## [Phase 5.3] Dart↔backend integration tests — and a timezone bug they caught
**Date:** 2026-09-03
**Files:** `[app] test/api_integration_test.dart` (new),
`[app] lib/core/api/backend_time.dart`
**What:** 15 tests driving the real backend over HTTP through the Dart layer.
All pass. They caught a genuine bug in `parseBackendTime`.
**How:** The suite uses `ApiClient.withTokenProvider` with a token minted by
`scripts/mint_test_token.py`, so requests traverse the same verification path as
the app. It skips itself with an explanatory message when the backend or token
is absent, keeping `flutter test` green on a machine without them.
**Why real HTTP instead of mocks:** a mock cannot catch a DTO field name that
does not match the server's JSON, a timestamp convention mismatch, or a status
code the client misinterprets — which are exactly the failure modes of a
client-server seam. Mocking here would have asserted that the code agrees with
itself.

**The bug found:** `parseBackendTime` ended in `.toLocal()`. The instant was
already shifted into IST by `.add(istOffset)`, but the result was still flagged
`isUtc`, so `.toLocal()` applied the offset a **second time**. On this machine —
which is itself set to IST — `15:50` parsed as `21:20`. Every block on the
timeline would have been drawn about six hours late, and because the shift is
consistent it would have looked like a plausible schedule rather than an error.
Fixed by rebuilding from the shifted *field values* through the plain `DateTime`
constructor, which yields a local-flagged wall clock that no later conversion
can move. This is the class of bug that only appears when a real
offset-bearing timestamp meets a real device clock.

Coverage: IST parsing in both `+05:30` and `Z` forms, outgoing `+05:30`
formatting, bad token → unauthorized, unreachable host → a *distinct* exception,
full task CRUD with `exclude_unset` semantics verified (an omitted field is not
nulled), readable validation messages, tap-to-complete leaving `actualDuration`
null, a genuine start yielding a non-negative duration, skip bumping both
counters, illegal transitions rejected, Dart 1-7 ↔ backend 0-6 weekday
conversion, commitment create/list/delete with 404 on re-delete, CP-SAT
placement appearing in `GET /schedule/day` with a usable `slot_id`, and a
240-minute task split into multiple sessions sharing one `task_id`.
**Verified:** `flutter test test/api_integration_test.dart` → **All 15 tests
passed.** `flutter analyze lib/core test/api_integration_test.dart` → no issues.

## Note for Phase 6: the UI needs a "start" action

Phase 4.3 established that `actualDuration` is only recorded when a task
genuinely passes through `in_progress`. A done-checkbox on its own will always
produce NULL, so `avg_estimation_error_minutes` would never populate and the
estimation-accuracy half of the behaviour profile would stay permanently empty.
`TaskRepository.startTask` exists for this; the task UI must expose it, not just
"done".

---

## [Phase 6.1] Stores hoisted into one MultiProvider
**Date:** 2026-09-03
**Files:** `[app] lib/app.dart`,
`[app] lib/core/data/stores/{task,schedule_slot,commitment}_store.dart` (new)
**What:** Added `TaskStore`, `ScheduleSlotStore` and `CommitmentStore`, all
server-backed, and provided them (plus one `ApiClient` and the two repositories)
from a single `MultiProvider` above `MaterialApp`.
**How:** `ChangeNotifierProvider` per store; `Provider` with a `dispose` callback
for the `ApiClient` so its HTTP client is closed with the app.
**Why:** `OnboardingFlow` and `HomeScreen` each used to construct their **own**
`ScheduleStore`, and they agreed only because both happened to read the same
`SharedPreferences` key. With server state that breaks immediately — two copies
diverge the moment either writes. `HomeScreen` also disposed the stores it
created, so state died on navigation. One instance above the navigator fixes
both.

The stores hold errors as state rather than throwing, so a failed request cannot
tear down a screen mid-build; screens read `store.error`, show a snack bar and
call `clearError()`.

## [Phase 6.2] Task dialog: category and energy in, flexibility and day out
**Date:** 2026-09-03
**Files:** `[app] lib/features/home/widgets/task_creation_dialog.dart`
**What:** Added required **Category** (6) and **Energy** (5) chip groups; removed
the Flexibility chips; the dialog no longer decides which day a task lands on.
**How:** `Wrap` of `ChoiceChip`s, matching the pattern the Flexibility control
already used, so the change reads as native to the existing design.
**Why:** `category` is a training feature for both ML models and `energy` is
matched against the scheduler's energy curve to choose an hour — without them the
solver was guessing on every task. *Flexibility* went because the backend has no
such field and derives it from duration; a control that changes nothing is worse
than no control. *Day selection* went because choosing the day is the scheduler's
entire purpose: the user supplies a deadline and a duration, CP-SAT returns the
placement. Previously `date` and `deadline` were independent and allowed to
contradict each other.

## [Phase 6.3] Timeline renders real scheduled blocks
**Date:** 2026-09-03
**Files:** `[app] lib/features/home/widgets/timeline_view.dart`,
`[app] lib/shared/theme/category_palette.dart` (new)
**What:** The timeline now draws fixed commitments *and* CP-SAT sessions as sized
blocks, replacing the zero-height deadline markers.
**How:** Both block types share one `_blockGeometry` helper so a commitment and a
session of equal length line up exactly. Commitments keep the existing solid blue
gradient; sessions are surface cards with a 4px category-coloured spine.
**Why:** Tasks were previously drawn as zero-height markers at their deadline —
`durationMinutes`, `priority` and `flexibility` were collected and never rendered.
This is the feature the app's own README listed as "Planned".

The two block styles are deliberately different. A user has to tell at a glance
what is immovable (a class) from what the app decided (their own work), because
only the latter can be started, finished or moved. Category colours are drawn
from Apple's system palette, so they sit beside the app's existing `#007AFF` —
itself iOS system blue — instead of introducing a second visual language.

Blocks are keyed by `slotId` and labelled "session n of m", because CP-SAT splits
a long task into several sessions sharing one `taskId`.

## [Phase 6.4] Task actions, with a Start action
**Date:** 2026-09-03
**Files:** `[app] lib/features/home/widgets/task_action_sheet.dart` (new)
**What:** A bottom sheet offering Start, Done, Postpone, Skip and Delete.
**Why: this is the payoff of the Phase 4.3 finding.** `actualDuration` is only
recorded when a task genuinely passes through `in_progress`, so a done-checkbox
alone always yields NULL and `avg_estimation_error_minutes` would stay
permanently empty — the app could never learn how badly the user estimates.
"Start working" is what makes that measurement possible, and it is labelled with
what it does ("Tracks how long this actually takes") rather than left implicit.
**Un-complete is deliberately absent**: `completed` is terminal in the server's
state machine, so offering it would produce a 422 the user could not act on.

## [Phase 6.5] Home screen data flow, and an Unplanned list
**Date:** 2026-09-03
**Files:** `[app] lib/features/home/home_screen.dart`,
`[app] lib/features/home/widgets/dashboard_page.dart`,
`[app] lib/features/home/widgets/unplanned_tasks_sheet.dart` (new)
**What:** Rewired both home pages off task-`date`. The timeline asks
`ScheduleSlotStore` for the selected day; the dashboard counts *today's slots*.
Added an Unplanned sheet and a "Plan my day" action.
**How:** `Consumer2` on the relevant stores. The dashboard receives slots only
when the loaded day really is today.
**Why:** Dropping task-`date` removed the basis for `tasksForDate()`, which was
the spine of both pages. The Unplanned list is genuinely new and genuinely
required: a task exists the moment it is created but has no slot until planning
runs, and since the user no longer picks a day it would otherwise be invisible.

Three details worth recording. The dashboard counts **distinct task ids**, not
slots, so a task split into three sessions does not read as "3 tasks today".
`dropped[]` from a plan run is surfaced in the snack bar — a task the solver
could not fit must never disappear quietly. And planning is followed by a task
reload, because planning changes task statuses and the unplanned count would
otherwise go stale.

## [Phase 6.6] Weekly setup writes to the server; sign-out clears local state
**Date:** 2026-09-03
**Files:** `[app] lib/features/onboarding/pages/weekly_setup_page.dart`,
`[app] lib/features/onboarding/onboarding_flow.dart`,
`[app] lib/core/data/stores/user_profile_store.dart`
**What:** Weekly commitments now go to `POST /schedule/commitments`. Added
`UserProfileStore.clear()`, called on sign-out along with clearing all three
stores.
**Why:** Commitments kept in `SharedPreferences` were invisible to the scheduler,
which is why it fell back to one hardcoded timetable for everybody. Sending them
up is what makes the per-user work of Phase 4 actually reachable from the app.

The sign-out clearing fixes a **real data leak**: the local profile keys are not
namespaced by user and sign-out left them in place, so signing in as a different
account on the same device showed the previous person's name and — because
`isOnboardingComplete` was still true — skipped onboarding entirely, dropping the
new user into a home screen greeting someone else.
**Verified:** `flutter analyze` → No issues found (whole project).
`flutter test test/api_integration_test.dart` → all 15 pass.

## ⚠️ [Phase 6.7] The Flutter app is not under version control
**Date:** 2026-09-03
**What:** `git rev-parse` in `/Users/wordo/Developer/saarthi` reports *not a git
repository*. The app has no history, no branches, and no way to undo.
**Why this is recorded rather than acted on:** Phase 6 rewrote or substantially
changed roughly a dozen files there. Every one of those edits is unrecoverable if
something needs reverting. Four files are now fully orphaned —
`daily_task_store.dart`, `schedule_store.dart`, `daily_task.dart` and
`schedule_entry.dart`, referenced only by each other — and would normally be
deleted, but deleting untracked files with no history is not reversible, so they
were left in place for the user to decide on.

`git init` in that directory is the single highest-value thing to do before
further work. The backend, by contrast, is on a `feat/flutter-integration` branch
cut from a clean `main`.
