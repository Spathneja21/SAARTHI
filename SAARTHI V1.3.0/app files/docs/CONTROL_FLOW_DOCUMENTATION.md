# Saarthi — Control Flow & Architecture Documentation

## Project Overview

Saarthi is a Flutter client for the **AURA backend**. The app collects what a
task needs — category, energy, duration, priority, deadline — and the server's
CP-SAT solver decides *when* it happens, working around the user's fixed weekly
commitments.

The single most important architectural fact: **the server is the source of
truth.** Tasks have no local `date` field; a task's day comes from
`scheduled_slots`, which only the scheduler writes. `SharedPreferences` retains
just the display name and the onboarding-complete flag.

**Stack:** Flutter + Firebase Auth ↔ FastAPI + PostgreSQL + CP-SAT + XGBoost/LightGBM

**Layering:**

```
features/ (UI)  →  stores/ (ChangeNotifier)  →  repositories/  →  ApiClient  →  HTTP
                        ▲                                                        │
                        └──────────────── DTOs ◀─────────────────────────────────┘
```

Each layer has one job. Stores hold state and errors; repositories know endpoint
paths and shapes; `ApiClient` knows HTTP, auth headers and error decoding; DTOs
know the wire format. UI never touches `ApiClient` directly.

---

## 1. Entry Point

### `lib/main.dart`

```
main() async
  ├─> WidgetsFlutterBinding.ensureInitialized()
  ├─> Firebase.initializeApp(DefaultFirebaseOptions.currentPlatform)
  └─> runApp(SaarthiApp)
```

Firebase must initialize **before** `runApp`. Without it, the first call to
`FirebaseAuth.instance` — which happens as soon as the splash screen checks who
is signed in — throws.

### `lib/app.dart`

```
SaarthiApp (StatelessWidget)
  └─> MultiProvider
       ├─ Provider<ApiClient>          (disposed with the app)
       ├─ Provider<TaskRepository>     (reads ApiClient)
       ├─ Provider<ScheduleRepository> (reads ApiClient)
       ├─ ChangeNotifierProvider<TaskStore>
       ├─ ChangeNotifierProvider<ScheduleSlotStore>
       └─ ChangeNotifierProvider<CommitmentStore>
            └─> ValueListenableBuilder<ThemeMode>(themeNotifier)
                 └─> MaterialApp(theme: lightTheme, darkTheme: darkTheme)
                      └─> home: SplashScreen()
```

**Why the stores are hoisted here.** `OnboardingFlow` and `HomeScreen` used to
each construct their own `ScheduleStore`, and they agreed only because both read
the same `SharedPreferences` key. With server state that breaks immediately: two
copies would drift the moment either wrote. Hoisting also means a screen no
longer disposes state another screen still needs.

`themeNotifier` is a top-level `ValueNotifier<ThemeMode>` in `app.dart`, toggled
from the home app bar. It is deliberately not in a store — it is view state, not
data.

---

## 2. The API Layer — `lib/core/api/`

### `api_config.dart` — where the backend lives

```
ApiConfig.baseUrl
  ├─> --dart-define=AURA_API_BASE_URL, if set          → use it verbatim
  ├─> kIsWeb                                            → http://localhost:8000
  ├─> TargetPlatform.android                            → http://10.0.2.2:8000
  └─> otherwise (iOS Sim, macOS, Windows, Linux)        → http://localhost:8000
```

`kIsWeb` is checked **first**: `defaultTargetPlatform` reports the underlying OS
even in a browser, so a Chrome tab on an Android device would otherwise be handed
the emulator's NAT alias. Platform detection uses `defaultTargetPlatform` rather
than `dart:io`'s `Platform` because importing `dart:io` breaks the web build at
compile time even when every use is guarded.

`ApiConfig.timeout` is **30 seconds** — generous because `POST /schedule/cpsat`
runs the solver, which has a 3-second budget *per solve* across a seven-day
horizon.

### `api_client.dart` — one thin JSON client

```
ApiClient
  ├─ ApiClient()                      → token from FirebaseAuth.instance
  ├─ ApiClient.withTokenProvider(fn)  → token from anywhere (used by tests)
  │
  ├─ get / post / patch / delete → _send(method, path, body?, query?)
  │   │
  │   ├─> _headers()
  │   │    ├─> await _tokenProvider()        # throws ApiException(401) if signed out
  │   │    └─> {Authorization: Bearer …, Accept, Content-Type?}
  │   │
  │   ├─> http.Request → _http.send().timeout(30s)
  │   │    ├─ TimeoutException  → ApiUnreachableException
  │   │    └─ Socket/Handshake/ClientException → ApiUnreachableException
  │   │
  │   └─> _decode(response)
  │        ├─ 204 or empty body → null  (DELETE answers empty; jsonDecode('') throws)
  │        ├─ status ≥ 400      → ApiException(status, _extractDetail(body))
  │        └─ else              → decoded JSON
  │
  └─ _extractDetail() → flattens FastAPI's two error shapes:
        {"detail": "Task not found"}                        → "Task not found"
        {"detail": [{"loc": [...], "msg": "..."} , …]}      → "field: msg; field: msg"
```

Tokens are fetched **per request, never cached**. `user.getIdToken()` already
returns a cached value until ~5 minutes before expiry and refreshes
transparently, so caching again would only risk sending a stale one.

### Error taxonomy

Two exception types, and the distinction matters:

| Type | Meaning | What the app should do |
|---|---|---|
| `ApiUnreachableException` | The request never got an answer | "Cannot reach the server. Is the backend running?" |
| `ApiException.isUnauthorized` (401/403) | Missing, expired or rejected token | Send the user back to sign-in |
| `ApiException.isNotFound` (404) | Gone — **or someone else's**. The backend returns 404 rather than 403 for another user's task, so it does not leak whether that id exists | Refresh the list |
| `ApiException.isValidationError` (422) | Body failed validation; `message` holds the field detail | Show it in the form |
| `ApiException.isServerMisconfigured` (503) | Missing Firebase service-account key on the server | **Do not treat as a sign-out.** Retrying will not help |

The 401-vs-503 split is the whole reason 503 exists as a separate case: a missing
server key is not the user's fault, and reporting it as 401 would put the app in
a loop trying to re-authenticate against a broken server.

### `backend_time.dart` — the timezone trap

The backend is hardcoded to IST. Every timestamp arrives as e.g.
`2026-09-03T15:50:00+05:30`, and the scheduler chose that slot meaning **15:50
India time**.

```
parseBackendTime(iso)
  ├─> DateTime.parse(iso).toUtc()     # correct instant, wrong fields
  ├─> .add(istOffset)                 # fields now read IST — but still flagged isUtc
  └─> DateTime(y, m, d, h, min, s, ms)   # rebuild as *local-flagged* wall clock

formatBackendTime(wallClock) → "YYYY-MM-DDTHH:MM:SS+05:30"
```

Two bugs this shape exists to prevent:

1. **`.toLocal()` looks correct in India and silently shifts everything
   elsewhere.** The device timezone is irrelevant; the scheduler's intent is
   expressed in IST, so the UI must render IST.
2. **Double conversion.** An earlier version ended in `.toLocal()`. Because the
   value was still flagged `isUtc`, Dart applied the offset a *second* time when
   formatting — on a machine already set to IST, 15:50 rendered as 21:20. The
   rebuild through the plain `DateTime` constructor produces a local-flagged
   value nothing will move again.

Outgoing, the explicit `+05:30` matters: a bare `toIso8601String()` on a local
`DateTime` emits no offset, and FastAPI would then mix naive and aware timestamps
in the same comparison.

### DTOs — `lib/core/api/dto/`

**`task_dto.dart`**

| Type | Notes |
|---|---|
| `TaskCategory` | `deep_work`, `admin`, `learning`, `meeting`, `personal`, `health`. Not decoration — a training feature for both ML models, and it picks the solver's focus limit |
| `EnergyLevel` | `very_low` … `peak`. Matched against an energy curve peaking ~10am, so it decides *when in the day* a task lands |
| `TaskStatus` | The server's state machine: `draft`, `scheduled`, `in_progress`, `paused`, `completed`, `partially_done`, `postponed`, `skipped`, `abandoned`. `completed` is **terminal** (`isTerminal`) |
| `TaskDto` | Mirrors `TaskRead`. `actualDuration` is **null when unmeasured**, never zero |
| `TaskCreateRequest` | `POST /tasks` body |
| `TaskUpdateRequest` | `PATCH /tasks/{id}` body; only non-null fields are sent. Because the server uses `exclude_unset`, a deadline can be *changed* but not *cleared* through this route |

Every `fromWire` falls back to a default rather than throwing, so a new
server-side enum value degrades instead of crashing the list.

**`slot_dto.dart`**

- `ScheduledSlotDto` — one placed block. **A task can own several**: CP-SAT
  splits anything past its focus limit into sessions sharing a `taskId`, which is
  why blocks are keyed by `slotId`. `status` is the parent *task's* status; slots
  have none. `createdBy` is `"ai"` or `"user"`.
- `FreeGapDto` — an unbooked stretch inside working hours.
- `DayScheduleDto` — the `GET /schedule/day` response.
- `CpsatAssignmentDto` — one chunk from a solver run. **Deliberately carries no
  `slotId`**: the solver's response does not include the database ids of the rows
  it just wrote. Re-fetch the day when ids are needed.
- `CpsatResultDto` — `scheduled`, `dropped`, `warnings`, `solveStatus`
  (`OPTIMAL` / `FEASIBLE` / `INFEASIBLE` / `UNKNOWN` / `SKIPPED`), `solveTimeMs`.

**`commitment_dto.dart`**

`FixedCommitmentDto` uses **minutes from midnight**, not timestamps, because a
recurring commitment has no single date — it is a wall-clock pattern projected
onto days.

⚠️ **Weekday indices differ between the two ends.** Python's `datetime.weekday()`
is 0 = Monday … 6 = Sunday; Dart's `DateTime.weekday` is 1 = Monday … 7 = Sunday.
`fromDartWeekday()` / `toDartWeekday()` convert, and every crossing must use them.

An `endMinute` of exactly `1440` means midnight, which `TimeOfDay` cannot express
as hour 24, so `endTime` clamps to 23:59 **for display only**.

---

## 3. Repositories — `lib/core/data/repositories/`

### `task_repository.dart`

| Method | Endpoint | Notes |
|---|---|---|
| `listTasks()` | `GET /tasks` | |
| `getTask(id)` | `GET /tasks/{id}` | |
| `createTask(req)` | `POST /tasks` | Server assigns the UUID — never mint one client-side |
| `updateTask(id, req)` | `PATCH /tasks/{id}` | Throws locally on an empty patch rather than eating a 422 round trip |
| `deleteTask(id)` | `DELETE /tasks/{id}` | |
| `completeTask(id)` | `POST /tasks/{id}/complete` | Idempotent |
| `postponeTask(id)` | `POST /tasks/{id}/postpone` | Increments `procrastinationCount` |
| `skipTask(id)` | `POST /tasks/{id}/skip` | Increments `skipCount` **and** `procrastinationCount` |
| `transition(id, to)` | `PATCH /tasks/{id}/transition` | Low-level; 422 on an illegal move |
| `startTask(id)` | *(two transitions)* | `draft → scheduled → in_progress` |
| `getHistory(id)` | `GET /tasks/{id}/history` | |

The dedicated `/complete`, `/postpone` and `/skip` endpoints exist because the
state machine forbids `draft → completed`; the server walks the intermediate
steps itself. Every method returns the server's view after the change — callers
replace their copy rather than guessing, because counters are computed
server-side.

**`startTask` is load-bearing.** It is the only path that produces a real
`actualDuration`: `started_at` is stamped on entering `in_progress`, and the
duration is derived from it at completion. Without a start, the behaviour
profile's `avg_estimation_error_minutes` stays permanently empty and the app can
never learn how badly the user estimates.

### `schedule_repository.dart`

| Method | Endpoint | Notes |
|---|---|---|
| `listCommitments()` | `GET /schedule/commitments` | |
| `createCommitment(req)` | `POST /schedule/commitments` | |
| `deleteCommitment(id)` | `DELETE /schedule/commitments/{id}` | Soft delete; 404 if already gone |
| `getDaySchedule(day)` | `GET /schedule/day?date=YYYY-MM-DD` | Only the date part is sent |
| `planSchedule({taskIds})` | `POST /schedule/cpsat` | With no ids, plans every pending task |
| `bookSlot(...)` | `POST /schedule/book` | 409 on overlap. *No UI yet* |
| `moveSlot(...)` | `POST /schedule/preference/move` | *No UI yet* |
| `clearAllSlots()` | `DELETE /schedule/slots` | Tasks are untouched |

`moveSlot` is not merely an edit. The backend stores the suggested time alongside
the chosen one, and a nightly job turns the eventual outcome into a reward that
biases future slot scoring — moving a block is how the scheduler learns this
user's preferences.

---

## 4. Stores — `lib/core/data/stores/`

All three server-backed stores share the same shape: `isLoading`, `error`,
`clear()` for sign-out, `clearError()`, and a static `_describe(Object)` that
turns exceptions into sentences a user can read.

**Errors are held on the store, never thrown into a build.** A failed request
must not tear down the screen mid-frame; the UI reads `error`, shows a snackbar,
and calls `clearError()`.

### `task_store.dart`

```
TaskStore (ChangeNotifier)
  ├─ tasks / isLoading / error / hasLoaded
  ├─ unplanned   → status is draft or postponed
  ├─ active      → !status.isResolved
  ├─ completed   → status == completed
  ├─ byId(id)
  │
  ├─ load()                          → GET /tasks
  ├─ create(req) → TaskDto?          → prepends on success, null + error on failure
  ├─ complete/start/skip/postpone/update  → _mutate()
  ├─ delete(id)                      → removes locally after a 204
  └─ _mutate(action)                 → await the server, swap the local copy for
                                       its response, notifyListeners()
```

There is **no local `date` field**. "Which tasks are on Tuesday" is a question
for `ScheduleSlotStore`, not this one.

`unplanned` matters because a task exists the moment it is created but has no
slot until planning runs — without a home in the UI it would simply be invisible.

### `schedule_slot_store.dart`

```
ScheduleSlotStore (ChangeNotifier)
  ├─ day / slots / freeGaps / totalBookedMinutes / loadedDate / lastPlan
  ├─ isLoading / isPlanning / error
  ├─ slotsForTask(taskId)   → sorted by start; can return several sessions
  │
  ├─ loadDay(date)
  │   └─> guards against an out-of-order response: if the user swiped to another
  │       day mid-flight, the stale answer is discarded rather than overwriting
  │
  ├─ refresh()              → reload loadedDate
  ├─ planDay() → CpsatResultDto?
  │   ├─> POST /schedule/cpsat
  │   ├─> sets error when !solved && !hadNothingToDo
  │   └─> finally: always refresh() — the solver returns no slot ids, so the
  │       timeline needs a fresh GET before a block can be moved
  ├─ moveSlot(...)          → then refresh()
  └─ clearAll()             → then refresh()
```

### `commitment_store.dart`

```
CommitmentStore (ChangeNotifier)
  ├─ commitments / hasAny / isLoading / hasLoaded / error
  ├─ forDate(date)                → occursOn() filter, sorted by startMinute
  ├─ weeklyForDartWeekday(1-7)    → converts to the backend's 0-6
  ├─ load() / addWeekly(...) / remove(id)
```

`hasAny` gates the end of onboarding: the scheduler needs some shape of a week to
work around, or every hour looks equally free and the plan is meaningless.

### `user_profile_store.dart`

The only remaining `SharedPreferences` user:

```
"user_name_v1"                 → String
"user_primary_task_v1"         → String   (written empty; vestigial)
"user_onboarding_complete_v1"  → bool
```

`clear()` **must** be called on sign-out. These keys are not namespaced by user,
and sign-out used to leave them in place — a real data leak: signing in as a
different account on the same device showed the previous person's name and,
because `isOnboardingComplete` was still true, skipped onboarding entirely,
dropping the new user into a home screen greeting someone else.

### ⚠️ Dead files

`daily_task.dart`, `schedule_entry.dart`, `daily_task_store.dart` and
`schedule_store.dart` are the pre-backend local-storage layer. They import only
each other; nothing live references them. They survived the Phase 6 rewrite only
because the app had no git history at the time. Safe to delete.

---

## 5. Splash & Authentication

### `lib/features/splash/splash_screen.dart`

```
SplashScreen (StatefulWidget)
  ├─ initState()
  │  ├─> AnimationController(6000ms) driving an 11-word "word wall"
  │  └─> _loadAuthState()  (runs in parallel with the animation)
  │       ├─> AuthService().currentUser
  │       └─> if signed in: UserProfileStore().load()
  │
  ├─ _handleLapCompleted(status)
  │  ├─ if data ready → _navigate()
  │  └─ else          → forward(from: 0)   # another full lap rather than a cut
  │
  └─ _navigate()
     ├─ user == null                  → LoginScreen
     ├─ profile.isOnboardingComplete  → HomeScreen(profile)
     └─ otherwise                     → OnboardingFlow
```

The animation is not a fixed delay dressed up as loading — if the auth check has
not finished, the word wall runs another complete lap rather than being cut off
mid-way.

### `lib/core/services/auth_service.dart`

A thin wrapper over `FirebaseAuth`: `currentUser`, `authStateChanges`,
`signUpWithEmailPassword`, `signInWithEmailPassword`, `signOut`, and
`_handleAuthException` which translates Firebase's error codes
(`email-already-in-use`, `invalid-credential`, `network-request-failed`, …) into
sentences. The UI never touches Firebase directly.

### `lib/features/auth/login_screen.dart`

One screen, both modes, toggled by `_isLoginMode`.

```
_submit()
  ├─> _formKey.validate()          # email has '@', password ≥ 6 on signup
  ├─ login  → signInWithEmailPassword → SplashScreen (which re-routes)
  └─ signup → signUpWithEmailPassword → signOut() → SignupSuccessScreen
```

Sign-up deliberately signs the user straight back out and sends them to a
confirmation screen, forcing a manual login so the credentials are verified once.

Validation runs before any network call, so an obviously bad email never costs a
round trip.

---

## 6. Onboarding

### `lib/features/onboarding/onboarding_flow.dart`

```
OnboardingFlow (StatefulWidget)
  ├─ initState() → postFrame: context.read<CommitmentStore>().load()
  │
  ├─ PageView (4 pages)
  │  ├─ 0 NamePage         — required input, blocks progression when empty
  │  ├─ 1 IntroPage        — auto-advances after 2400ms
  │  ├─ 2 StartPage        — auto-advances after 2400ms
  │  └─ 3 WeeklySetupPage  — with onFinish
  │
  ├─ _blended(index, child)  → opacity + 32px parallax driven by controller.page
  │
  └─ _finishOnboarding()
     ├─> name empty            → message + animate back to page 0
     ├─> !commitmentStore.hasAny → "add at least one fixed weekly slot"
     ├─> UserProfileStore.save(profile with isOnboardingComplete: true)
     └─> OnboardingCompleteScreen → (2200ms) → HomeScreen
```

Pages 1 and 2 carry no required input, so they advance themselves rather than
making the user tap through. The commitment store is *read*, not constructed —
the old code created a second `ScheduleStore` here and agreed with the home
screen only by sharing a preferences key.

### `lib/features/onboarding/pages/weekly_setup_page.dart`

Doubles as the standalone editor reached from the home app bar: `onFinish` is
null there, which hides the "Finish setup" button.

```
WeeklySetupPage
  ├─ _selectedWeekday (Dart 1-7, defaults to today)
  ├─ Consumer<CommitmentStore> → store.weeklyForDartWeekday(_selectedWeekday)
  ├─ "Add fixed slot" → dialog
  │    ├─ title, start picker, end picker
  │    ├─ picking a start ≥ end auto-pushes end to start + 1h
  │    ├─ validates: title non-empty, end > start
  │    └─> store.addWeekly(title, dartWeekday, start, end)   # POST to the server
  └─ delete icon → store.remove(id)
```

These go to the server because they are what CP-SAT treats as immovable. Kept
locally, the scheduler could never see them — before this, *every* user was
scheduled around one hardcoded university timetable.

---

## 7. Home Screen

### `lib/features/home/home_screen.dart`

```
HomeScreen (StatefulWidget)
  ├─ initState()
  │  ├─> _selectedDate = today (date only)
  │  └─> postFrame → _loadEverything()
  │       └─> Future.wait([TaskStore.load(),
  │                        CommitmentStore.load(),
  │                        ScheduleSlotStore.loadDay(_selectedDate)])
  │           └─> _reportAnyError()   # first non-null store error → snackbar
  │
  ├─ dispose() → only _pageController. Stores are NOT disposed here; they live
  │              in the root MultiProvider
  │
  ├─ build()
  │  ├─ AppBar: "Hello, {name}" · theme toggle · edit fixed schedule · logout
  │  └─ Stack
  │     ├─ FluidMorphBackground (full bleed)
  │     └─ Column → PageDots(count: 2) → PageView
  │        ├─ page 0: _buildDashboardPage()
  │        └─ page 1: _buildTimelinePage()
  │
  ├─ _buildDashboardPage()   → Consumer2<TaskStore, ScheduleSlotStore>
  │     └─ passes slots ONLY when loadedDate is really today, so the counters
  │        never silently describe a day the user merely browsed to
  │
  └─ _buildTimelinePage()    → Consumer2<ScheduleSlotStore, CommitmentStore>
        ├─ TimelineView(selectedDate, commitments, slots, onSlotTap)
        ├─ loading spinner  /  empty-day hint
        ├─ WeekStrip (top)  ·  date pill (blurred, opens DatePicker)
        └─ action menu FAB (bottom-right)
```

### Actions

| Action | Flow |
|---|---|
| **Add task** | `TaskCreationDialog` → `TaskStore.create()` → snackbar *"added. Plan your day to place it."* |
| **Unplanned** | `UnplannedTasksSheet` → tap a task opens its action sheet, or "Plan my day" |
| **Plan my day** | `ScheduleSlotStore.planDay()` → **then `TaskStore.load()`**, because planning changes task statuses and the unplanned count would go stale → reports `dropped` by name |
| **Clear schedule** | Confirm dialog → `clearAll()` → reload tasks → "Cleared N blocks" |
| **Tap a block** | `_onSlotTap` → `_openTaskActions` |
| **Sign out** | `AuthService().signOut()` → `taskStore.clear()`, `slotStore.clear()`, `commitmentStore.clear()`, `UserProfileStore().clear()` → `pushAndRemoveUntil(SplashScreen)` |

```
_openTaskActions()
  ├─> TaskActionSheet.show() → TaskAction?
  ├─> dispatch to TaskStore (start / complete / skip / postpone / delete)
  ├─> on failure: snackbar with store.error, then clearError()
  └─> on success: slotStore.refresh()
         # a status change alters what the timeline draws (a completed block
         # renders struck through) and a delete removes its slots entirely
```

`TaskAction.edit` currently returns without doing anything — the repository
method exists, the UI does not.

### `widgets/timeline_view.dart`

```
TimelineView (StatefulWidget)
  ├─ Props: selectedDate, commitments, slots, onSlotTap
  │
  ├─ initState()
  │  ├─> Timer.periodic(30s) → setState()      # moves the now line only
  │  └─> postFrame → _scrollToCurrentTime()    # today only, offset −200px
  │
  ├─ Constants: startHour 0, endHour 23, hourHeight 76, labelWidth 58, gap 8
  │             canvas = 24 × 76 = 1824px
  │
  ├─ build()
  │  ├─ group slots by taskId → sessionsPerTask, orderedByTask (for "n of m")
  │  └─ Stack
  │     ├─ hour labels 00:00–24:00 + dividers
  │     ├─ _buildCommitmentBlock()  → solid blue gradient, white text
  │     ├─ _buildSessionBlock()     → surface card, category accent spine
  │     └─ _buildNowLine()          → #FF8FA3 dot + fading line (today only)
  │
  └─ _blockGeometry(start, end, rangeStart, rangeEnd)
     ├─ clamps to the visible range, returns null if zero height
     └─ shared by both block types so equal-length blocks always line up
```

**Why the two block styles differ.** A user has to tell at a glance what is
immovable (a class) from what the app decided (their own work), because only the
latter can be started, finished or moved. Commitments own the solid blue; task
sessions get a surface card with a 4px category spine. Blocks under ~46px switch
to a compact single-row layout.

A completed session renders struck through at 40% opacity; a running one gets a
2px accent border and a filled play icon.

### `widgets/dashboard_page.dart`

```
DashboardPage (StatefulWidget)
  ├─ Timer.periodic(1s) → live clock
  ├─ taskIdsToday = todaySlots.map(taskId).toSet()
  │     # DISTINCT tasks, not slots — a task split into 3 sessions is still one
  │       thing to do, and "3 tasks today" would be misleading
  ├─ completed = ids whose TaskDto.status == completed
  ├─ minutesPlanned = Σ slot.durationMinutes
  └─ Stat cards · progress card · _UnplannedHint (only when count > 0)
```

`FlipClock` is imported-out: the split-flap style is on hold, and the code is
commented rather than deleted.

### `widgets/task_creation_dialog.dart`

Collects title, **category**, **energy**, duration (15–480m, 31 divisions),
priority (1–5), and a deadline date + time (defaults to 14:00).

Two fields are new and not optional — `category` trains both ML models and picks
the solver's focus limit; `energy` is matched against the energy curve to choose
the time of day. Two were deliberately **removed**:

- **Flexibility** — the backend has no such field; it infers flexibility from
  duration. A control that changes nothing is worse than no control.
- **Which day the task sits on** — that is the scheduler's entire job.

The deadline label reads *"not when it runs"* for exactly that reason.

### `widgets/task_action_sheet.dart`

Returns a `TaskAction?`. Offers Start → Mark done → Postpone → Skip → Delete,
with Start hidden while a task is already running and *"Finish"* replacing *"Mark
done"* in that state.

**Un-complete is deliberately absent**: `completed` is terminal in the server's
state machine, so offering it would produce a 422 the user could not act on. A
completed task shows *"Completed tasks cannot be reopened."* instead of actions.

### `widgets/unplanned_tasks_sheet.dart`

Lists tasks with no slot, each with category, duration and an overdue-aware
deadline, plus a "Plan my day" button. Has no equivalent in the old local-only
app and is needed precisely because the user no longer chooses a day.

---

## 8. Error Handling & Edge Cases

| Scenario | Location | Handling |
|---|---|---|
| Backend not running | `api_client.dart` | `ApiUnreachableException` → "Cannot reach the server. Is the backend running?" |
| Missing service-account key on the server | stores' `_describe` | 503 → "The server is not fully configured yet." Never a sign-out |
| Token expired / rejected | stores' `_describe` | 401/403 → "Your session expired. Please sign in again." |
| Account disabled while the app is open | `api_client.dart` | `FirebaseAuthException` during refresh → surfaced as 401, not a crash |
| Empty `PATCH` body | `task_repository.dart` | Throws locally instead of a pointless 422 round trip |
| Illegal status transition | server | 422, message shown as-is |
| Day swapped mid-request | `schedule_slot_store.dart` | Stale response discarded via the `loadedDate` guard |
| Solver could not fit tasks | `home_screen._planDay` | `dropped` names listed in the snackbar — never silently missing |
| Solver returns no slot ids | `schedule_slot_store.planDay` | Always `refresh()` in `finally` |
| Task split into sessions | `timeline_view` / `dashboard_page` | Keyed by `slotId`, labelled "session n of m"; counters use distinct task ids |
| Unknown enum value from the server | all DTOs | `fromWire` falls back to a default rather than throwing |
| `endMinute == 1440` | `commitment_dto.dart` | Clamped to 23:59 for display |
| Block outside the visible range | `timeline_view._blockGeometry` | Clamped; returns null (not rendered) at zero height |
| Empty name / no commitments | `onboarding_flow.dart` | Message, progression blocked |
| End time ≤ start time | `weekly_setup_page.dart` | Auto-adjust, then validate before submit |
| Widget disposed during async | everywhere | `if (!mounted) return;` before every `setState`/navigation |
| Signing in as a different user | `home_screen._signOut` | All three stores cleared + `UserProfileStore.clear()` |

---

## 9. Key Design Patterns

**1. Server as source of truth.** No optimistic local mutation. Every mutating
call awaits the server and adopts its response, because counters like
`procrastinationCount` are computed server-side and guessing would drift.

**2. Store / repository / client separation.** UI never constructs a request;
repositories never hold state; the client never knows what a task is.

**3. Errors as state, not exceptions.** Stores catch, translate via `_describe`,
and expose `error`. The UI reads it after an `await` and calls `clearError()`.

**4. One instance of everything, at the root.** `MultiProvider` in `app.dart`.
Screens `read`/`watch`; they neither create nor dispose.

**5. `Consumer2` over `AnimatedBuilder`.** Rebuild scope is the widget that
actually depends on the data, not the whole page.

**6. Enums that carry their wire value.** `TaskCategory.deepWork.wire ==
'deep_work'`, with a `label` for display. Serialization lives on the enum, not in
a switch somewhere.

**7. Explicit timezone handling.** Never `.toLocal()`. See `backend_time.dart`.

---

## 10. Testing

### `test/api_integration_test.dart` — 15 tests, real HTTP

Not a unit test with mocks. It verifies what mocks cannot: that DTO field names
match the wire format, that IST timestamps round-trip, that error bodies decode
into useful messages, and that status codes mean what the client assumes.

Groups: *time conversion*, *auth*, *task lifecycle*, *commitments and planning* —
including that completing without starting leaves the duration unmeasured, that
an illegal transition is rejected, and that a long task is split into multiple
sessions sharing a task id.

Requires the backend up and a token at `/tmp/e2e_token.txt`; it **skips itself
with a clear message** otherwise, so `flutter test` stays green on a machine with
no backend.

### `test/widget_test.dart` — ⚠️ currently failing

Asserts the splash screen shows the literal text `S.A.A.R.T.H.I`. The word-wall
animation renders `SAARTHI` among ten other words, so the finder matches nothing.
The assertion needs updating.

---

## 11. Code Metrics

- **Total Dart files:** 47 (~7,300 lines)
- **API layer:** 6 files — client, config, time, 3 DTO files
- **Data layer:** 9 files — 2 repositories, 4 live stores, 1 live model, 2 dead
- **Feature files:** 17 across splash, auth, onboarding, home
- **Shared:** 8 widgets + 1 theme file
- **State management:** `provider` / `ChangeNotifier`, hoisted to the root
- **Persistence:** the AURA backend, with `SharedPreferences` for the local
  profile only
- **`flutter analyze`:** No issues found

---

**Last Updated:** September 7, 2026
**App Version:** 1.0.0+1 — backend-integrated (Phase 6)
