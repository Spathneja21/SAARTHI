# Saarthi — Quick Reference & File Index

## 📋 Documentation

| File | Content |
|---|---|
| **CONTROL_FLOW_DOCUMENTATION.md** | File-by-file control flow, API layer, stores, error handling, design patterns |
| **ARCHITECTURE_DIAGRAMS.md** | Mermaid diagrams — layers, navigation, planning sequence, state machine, timezone |
| **AUTHENTICATION.md** | Firebase setup and how the ID token reaches the backend |
| **QUICK_REFERENCE.md** | This file — file index, endpoint map, code lookups, workflows |
| `../../Aura-backend/docs/INTEGRATION_LOG.md` | Phase-by-phase record of the backend integration, with reasoning |

---

## 📁 File Index

```
lib/
├── main.dart ................................ Firebase init, then runApp (13)
├── app.dart ................................. Themes + MultiProvider root (373)
├── firebase_options.dart .................... Generated — do not edit (86)
│
├── core/api/
│   ├── api_config.dart ...................... Per-platform base URL (57)
│   ├── api_client.dart ...................... HTTP + Bearer + error types (217)
│   ├── backend_time.dart .................... IST parse/format (74)
│   └── dto/
│       ├── task_dto.dart .................... TaskDto + 3 enums + requests (228)
│       ├── slot_dto.dart .................... Slots, gaps, CP-SAT results (208)
│       └── commitment_dto.dart .............. Fixed commitments (154)
│
├── core/data/
│   ├── models/
│   │   ├── user_profile.dart ................ Local profile (17)
│   │   ├── daily_task.dart .................. ⚠️ DEAD (78)
│   │   └── schedule_entry.dart .............. ⚠️ DEAD (75)
│   ├── repositories/
│   │   ├── task_repository.dart ............. /tasks endpoints (104)
│   │   └── schedule_repository.dart ......... /schedule endpoints (107)
│   └── stores/
│       ├── task_store.dart .................. ChangeNotifier (175)
│       ├── schedule_slot_store.dart ......... The loaded day + planning (164)
│       ├── commitment_store.dart ............ Fixed commitments (136)
│       ├── user_profile_store.dart .......... SharedPreferences (40)
│       ├── daily_task_store.dart ............ ⚠️ DEAD (101)
│       └── schedule_store.dart .............. ⚠️ DEAD (104)
│
├── core/services/auth_service.dart .......... Firebase Auth wrapper (63)
├── core/utils/time_utils.dart ............... isSameDate, compareTimes (44)
│
├── shared/
│   ├── theme/category_palette.dart .......... Category accents + icons (60)
│   └── widgets/
│       ├── page_shell.dart .................. Onboarding page layout (61)
│       ├── page_dots.dart ................... Page indicator (30)
│       ├── soft_blob.dart ................... Background circle (20)
│       ├── typewriter_text.dart ............. Single-line reveal (138)
│       ├── typewriter_block.dart ............ Multi-line reveal (172)
│       ├── morphing_sparkle.dart ............ Splash sparkle painter (71)
│       ├── fluid_morph_background.dart ...... Home background painter (165)
│       └── flip_clock.dart .................. ⚠️ built, unused (284)
│
└── features/
    ├── splash/splash_screen.dart ............ Word wall + auth routing (212)
    ├── auth/
    │   ├── login_screen.dart ................ Login / sign-up toggle (228)
    │   └── signup_success_screen.dart ....... Confirmation (68)
    ├── onboarding/
    │   ├── onboarding_flow.dart ............. 4-page container (212)
    │   ├── onboarding_complete_screen.dart .. Transition (92)
    │   └── pages/
    │       ├── name_page.dart ............... Name input (82)
    │       ├── intro_page.dart .............. Welcome (67)
    │       ├── start_page.dart .............. Instructions (44)
    │       └── weekly_setup_page.dart ....... Commitment editor (259)
    └── home/
        ├── home_screen.dart ................. Orchestrator (658)
        └── widgets/
            ├── dashboard_page.dart .......... Clock + stats (318)
            ├── timeline_view.dart ........... 24-hour column (522)
            ├── week_strip.dart .............. Day selector (78)
            ├── task_creation_dialog.dart .... Create form (297)
            ├── task_action_sheet.dart ....... Start/Done/… (282)
            └── unplanned_tasks_sheet.dart ... No-slot inbox (269)
```

**47 files · ~7,300 lines.** ⚠️ **DEAD** = the pre-backend local-storage layer.
The four files reference only each other; nothing live imports them. Safe to
delete.

---

## 🌐 Endpoint Map

Everything the app calls. Every request carries `Authorization: Bearer <Firebase ID token>`.

### Tasks — `TaskRepository`

| Method | Endpoint | Called by |
|---|---|---|
| `listTasks` | `GET /tasks` | `TaskStore.load` |
| `getTask` | `GET /tasks/{id}` | *(unused by UI)* |
| `createTask` | `POST /tasks` | `TaskStore.create` |
| `updateTask` | `PATCH /tasks/{id}` | `TaskStore.update` — **no UI yet** |
| `deleteTask` | `DELETE /tasks/{id}` | `TaskStore.delete` |
| `completeTask` | `POST /tasks/{id}/complete` | `TaskStore.complete` |
| `postponeTask` | `POST /tasks/{id}/postpone` | `TaskStore.postpone` |
| `skipTask` | `POST /tasks/{id}/skip` | `TaskStore.skip` |
| `transition` | `PATCH /tasks/{id}/transition` | via `startTask` |
| `startTask` | *(2 transitions)* | `TaskStore.start` |
| `getHistory` | `GET /tasks/{id}/history` | *(unused by UI)* |

### Schedule — `ScheduleRepository`

| Method | Endpoint | Called by |
|---|---|---|
| `listCommitments` | `GET /schedule/commitments` | `CommitmentStore.load` |
| `createCommitment` | `POST /schedule/commitments` | `CommitmentStore.addWeekly` |
| `deleteCommitment` | `DELETE /schedule/commitments/{id}` | `CommitmentStore.remove` |
| `getDaySchedule` | `GET /schedule/day?date=YYYY-MM-DD` | `ScheduleSlotStore.loadDay` |
| `planSchedule` | `POST /schedule/cpsat` | `ScheduleSlotStore.planDay` |
| `clearAllSlots` | `DELETE /schedule/slots` | `ScheduleSlotStore.clearAll` |
| `bookSlot` | `POST /schedule/book` | **no UI yet** — 409 on overlap |
| `moveSlot` | `POST /schedule/preference/move` | **no UI yet** — also an RL signal |

### Backend endpoints the app does **not** use

`/register`, `/login` (superseded by Firebase), `/nudge/evaluate`, `/ml/*`,
`/analytics/profile*`, `/schedule/suggest/{task_id}`.

---

## 🔤 Wire Enums

Values are lowercase snake_case; every `fromWire` falls back rather than throwing.

| Enum | Values |
|---|---|
| `TaskCategory` | `deep_work` · `admin` · `learning` · `meeting` · `personal` · `health` |
| `EnergyLevel` | `very_low` · `low` · `medium` · `high` · `peak` |
| `TaskStatus` | `draft` · `scheduled` · `in_progress` · `paused` · `completed` · `partially_done` · `postponed` · `skipped` · `abandoned` |
| `CommitmentRecurrence` | `one_time` · `daily` · `weekly` |

`TaskStatus.completed` is **terminal** — no un-complete action exists.
`TaskStatus.isResolved` covers `completed`, `abandoned`, `skipped`,
`partially_done`.

---

## 🔍 Quick Code Lookups

### Creating a task
**File:** `features/home/widgets/task_creation_dialog.dart`
```dart
_titleController              // task name, required
_category                     // TaskCategory — ML feature + focus limit
_energy                       // EnergyLevel — picks time of day
_duration                     // 15–480 min, 31 divisions, default 60
_priority                     // 1–5, default 3
_deadline / _deadlineTime     // default time 14:00 — "not when it runs"
```
No day picker and no flexibility toggle — see the class doc comment for why.

### Timeline geometry
**File:** `features/home/widgets/timeline_view.dart`
```dart
_blockGeometry(start, end, rangeStart, rangeEnd)  // shared by both block types
_buildCommitmentBlock()      // solid blue — immovable
_buildSessionBlock()         // surface card + 4px category spine
_buildNowLine()              // #FF8FA3, today only
_scrollToCurrentTime()       // today only, −200px lead
_offsetForMinute(m)          // (m / 60) * 76
```

### Tasks
**File:** `core/data/stores/task_store.dart`
```dart
load()                       // GET /tasks
create(TaskCreateRequest)    // returns TaskDto? — null means check .error
start(id)                    // the ONLY path that measures actualDuration
complete(id) / skip(id) / postpone(id) / delete(id)
unplanned                    // draft or postponed — the inbox
active / completed / byId(id)
clear()                      // sign-out
```

### The day
**File:** `core/data/stores/schedule_slot_store.dart`
```dart
loadDay(date)                // guards against out-of-order responses
planDay()                    // CP-SAT, then always refresh()
slotsForTask(taskId)         // can return several sessions
moveSlot(...) / clearAll() / refresh()
slots / freeGaps / totalBookedMinutes / lastPlan / loadedDate
isLoading / isPlanning / error
```

### Commitments
**File:** `core/data/stores/commitment_store.dart`
```dart
load() / addWeekly(title, dartWeekday, start, end) / remove(id)
forDate(date)                // occursOn filter, sorted
weeklyForDartWeekday(1-7)    // converts to the backend's 0-6
hasAny                       // gates the end of onboarding
```

### Time conversion
**File:** `core/api/backend_time.dart`
```dart
parseBackendTime(iso)        // → IST wall clock. NEVER call .toLocal() on it
parseBackendTimeOrNull(iso)  // for deadline, startedAt, completedAt
formatBackendTime(dt)        // → "…T15:50:00+05:30"
istOffset                    // Duration(hours: 5, minutes: 30)
```

---

## 🎨 Colors

**Theme** ([app.dart](../lib/app.dart)):

| Token | Light | Dark |
|---|---|---|
| Primary | `#007AFF` | `#0A84FF` |
| Background | `#F2F2F7` | `#000000` |
| Surface | `#FFFFFF` | `#1C1C1E` |
| Text | `#1C1C1E` | `#FFFFFF` |
| Muted | `#8E8E93` | `#98989D` |
| Error | `#FF3B30` | `#FF453A` |
| Now marker | `#FF8FA3` | `#FF8FA3` |

**Categories** ([category_palette.dart](../lib/shared/theme/category_palette.dart)):

| Category | Light | Dark | Icon |
|---|---|---|---|
| Deep work | `#007AFF` | `#0A84FF` | `center_focus_strong_outlined` |
| Learning | `#5E5CE6` | `#7D7AFF` | `school_outlined` |
| Meeting | `#FF9500` | `#FF9F0A` | `groups_outlined` |
| Personal | `#34C759` | `#30D158` | `person_outline` |
| Health | `#FF375F` | `#FF375F` | `favorite_outline` |
| Admin | `#8E8E93` | `#98989D` | `inbox_outlined` |

**Shape:** cards 18px · controls/buttons 14px.
**Type:** Inter everywhere; Space Grotesk for the dashboard clock.

---

## ⏰ Timeline Constants

**File:** `features/home/widgets/timeline_view.dart`

| Constant | Value |
|---|---|
| `_timelineStartHour` | 0 |
| `_timelineEndHour` | 23 |
| `_hourHeight` | 76px |
| `_labelWidth` | 58px |
| `_gapWidth` | 8px |
| Canvas height | 24 × 76 = **1,824px** |
| Compact-layout threshold | block height < 46px |
| Minimum block height | 26px |

---

## 📊 State Management

**Pattern:** `provider` + `ChangeNotifier`, all instances hoisted to the
`MultiProvider` in `app.dart`.

```
user action
  → store method
  → await repository → ApiClient → server
  → adopt the server's response      (no optimistic local edit)
  → notifyListeners()
  → Consumer/Consumer2 rebuilds only that subtree
```

**On failure:**
```
catch → _describe(e) → store.error   (held, never thrown into a build)
  → UI reads it after the await → snackbar → clearError()
```

**Purely visual ticks** bypass all of this: `Timer.periodic(30s)` in
`TimelineView` for the now line, `Timer.periodic(1s)` in `DashboardPage` for the
clock, both plain `setState`.

---

## 💾 Storage

### Server (PostgreSQL, per Firebase account)
Tasks · fixed commitments · scheduled slots · task events · behaviour profile.

### SharedPreferences — local, and only this

```
"user_name_v1"                 → String
"user_primary_task_v1"         → String   (written empty; vestigial)
"user_onboarding_complete_v1"  → bool
```

⚠️ These keys are **not namespaced by user**. `UserProfileStore.clear()` must be
called on sign-out, or the next person to sign in on the device sees the previous
user's name and skips onboarding.

---

## 🚨 Invariants

| Rule | Why |
|---|---|
| Never call `.toLocal()` on a backend timestamp | Double conversion. It looks right in India and shifts everywhere else |
| Never mint a task id client-side | The server assigns the UUID |
| Never offer "un-complete" | `completed` is terminal; the server would answer 422 |
| Never assume one block per task | CP-SAT splits long tasks into sessions sharing a `taskId` |
| Never swallow `dropped[]` | Those are tasks the solver could not fit |
| Always `refresh()` after `planDay()` | The solver's response carries no slot ids |
| Always reload tasks after planning | Planning changes statuses; the unplanned count goes stale |
| Always convert weekdays across the boundary | Dart is 1–7, Python is 0–6 |
| Treat 503 as a server problem, not a sign-out | Missing service-account key; retrying will not help |
| Treat `actualDuration == null` as unmeasured | Never as zero |
| `if (!mounted) return;` after every `await` | Before any `setState` or navigation |

---

## 🔄 Common Workflows

### Add and schedule a task
1. Home → timeline page → FAB → **Add task**
2. Fill title, category, energy, duration, priority, deadline → **Create**
3. `POST /tasks` → snackbar: *"added. Plan your day to place it."*
4. FAB → **Plan my day** → `POST /schedule/cpsat`
5. Blocks appear on the timeline; anything dropped is named in the snackbar

### Work a task
1. Tap its block on the timeline (or open it from **Unplanned**)
2. **Start working** → `in_progress`, `started_at` stamped
3. Block gains a 2px border and a play icon
4. Tap again → **Finish** → `actualDuration` recorded

### Edit the fixed schedule
1. App bar → calendar icon → `WeeklySetupPage` (no "Finish setup" button here)
2. Pick a weekday → **Add fixed slot** → title, start, end
3. `POST /schedule/commitments` — replan for it to take effect on existing blocks

### Change day
Tap a day in the `WeekStrip`, or the date pill → system date picker. Either calls
`ScheduleSlotStore.loadDay`. The **dashboard keeps reporting today** regardless.

### Point at a different backend
```bash
flutter run --dart-define=AURA_API_BASE_URL=http://192.168.1.7:8000
```

---

## 📞 Files That Change Together

| Change | Touch |
|---|---|
| **New task field** | `dto/task_dto.dart` (DTO + create/update requests) → `task_repository.dart` → `task_store.dart` → `task_creation_dialog.dart` → wherever it is displayed |
| **New endpoint** | the matching repository → its store → the UI that triggers it |
| **New task status** | `TaskStatus` enum → `isTerminal`/`isResolved` → `task_action_sheet.dart` → `timeline_view._buildSessionBlock` |
| **New task category** | `TaskCategory` enum → `category_palette.dart` (**both** light and dark maps + `iconOf`) |
| **Slot shape** | `dto/slot_dto.dart` → `schedule_slot_store.dart` → `timeline_view.dart` → `dashboard_page.dart` |
| **Commitment shape** | `dto/commitment_dto.dart` → `commitment_store.dart` → `weekly_setup_page.dart` → `timeline_view.dart` |
| **Theme / colors** | `app.dart` (both themes) — single source of truth |
| **Base URL rules** | `api_config.dart` only |
| **Sign-out** | `home_screen._signOut` — every store's `clear()` plus `UserProfileStore.clear()` |

---

## 🧪 Testing

```bash
flutter analyze     # currently: No issues found
flutter test
```

| Suite | Status |
|---|---|
| `test/api_integration_test.dart` | 15 real-HTTP tests. **Skips itself** unless the backend is up and a token exists at `/tmp/e2e_token.txt` |
| `test/widget_test.dart` | ⚠️ **Failing** — asserts the splash shows `S.A.A.R.T.H.I`; the word wall renders `SAARTHI` |

Mint a token:
```bash
cd ../Aura-backend
docker compose exec -T api python scripts/mint_test_token.py <WEB_API_KEY> <uid> <email>
```

---

**Last Updated:** September 7, 2026
**App Version:** 1.0.0+1 — backend-integrated (Phase 6)
