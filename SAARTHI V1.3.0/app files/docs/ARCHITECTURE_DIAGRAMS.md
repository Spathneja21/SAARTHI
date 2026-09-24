# Saarthi — Visual Architecture Diagrams

Diagrams for the **backend-integrated** app. The server is the source of truth;
tasks have no local day, and the scheduler decides placement.

---

## 1. Layered Architecture

```mermaid
graph TB
    subgraph UI["features/ — UI"]
        SPL["SplashScreen"]
        AUTH_UI["LoginScreen"]
        ONB["OnboardingFlow"]
        HOME["HomeScreen"]
    end

    subgraph STORES["core/data/stores/ — ChangeNotifier"]
        TS["TaskStore"]
        SS["ScheduleSlotStore"]
        CS["CommitmentStore"]
        UPS["UserProfileStore"]
    end

    subgraph REPOS["core/data/repositories/"]
        TR["TaskRepository"]
        SR["ScheduleRepository"]
    end

    subgraph APILAYER["core/api/"]
        AC["ApiClient"]
        CFG["ApiConfig"]
        BT["backend_time"]
        DTO["DTOs"]
    end

    FB["Firebase Auth<br/>holds the credential"]
    BE["AURA backend<br/>FastAPI"]
    SP["SharedPreferences<br/>name + onboarding flag only"]

    SPL --> UPS
    AUTH_UI --> FB
    ONB --> CS
    ONB --> UPS
    HOME --> TS
    HOME --> SS
    HOME --> CS

    TS --> TR
    SS --> SR
    CS --> SR

    TR --> AC
    SR --> AC

    AC --> CFG
    AC --> DTO
    DTO --> BT

    AC -->|"ID token"| FB
    AC -->|"HTTPS + Bearer"| BE
    UPS --> SP

    style UI fill:#e8f5e9
    style STORES fill:#f3e5f5
    style REPOS fill:#e0f2f1
    style APILAYER fill:#e3f2fd
    style BE fill:#fff3e0
    style FB fill:#fff9c4
```

Each layer has one job. UI never touches `ApiClient`. Repositories never hold
state. `ApiClient` never knows what a task is.

---

## 2. Navigation & Auth Routing

```mermaid
graph TD
    A["main.dart<br/>Firebase.initializeApp"] --> B["SaarthiApp<br/>MultiProvider + themes"]
    B --> C["SplashScreen<br/>word-wall animation"]

    C --> D{"AuthService<br/>currentUser?"}
    D -->|"null"| E["LoginScreen"]
    D -->|"signed in"| F{"profile.isOnboarding<br/>Complete?"}

    E -->|"login"| C
    E -->|"sign up"| G["SignupSuccessScreen"]
    G --> E

    F -->|"NO"| H["OnboardingFlow<br/>4 pages"]
    F -->|"YES"| I["HomeScreen"]

    H --> J["OnboardingCompleteScreen"]
    J --> I

    I -->|"sign out<br/>clear all stores"| C

    style C fill:#fff9c4
    style E fill:#ffe0b2
    style H fill:#f3e5f5
    style I fill:#e8f5e9
```

Sign-up deliberately routes **back to login** rather than into the app, forcing
the credentials to be verified once. The splash screen re-runs its routing after
a successful login, so there is one routing decision, in one place.

---

## 3. Project File Structure

```mermaid
graph TD
    subgraph ROOT["lib/"]
        main["main.dart"]
        app["app.dart"]
        fbopts["firebase_options.dart"]
    end

    subgraph CORE["core/"]
        subgraph API["api/"]
            a1["api_client.dart"]
            a2["api_config.dart"]
            a3["backend_time.dart"]
            subgraph DTOS["dto/"]
                d1["task_dto.dart"]
                d2["slot_dto.dart"]
                d3["commitment_dto.dart"]
            end
        end
        subgraph DATA["data/"]
            subgraph REPO["repositories/"]
                r1["task_repository.dart"]
                r2["schedule_repository.dart"]
            end
            subgraph STORE["stores/"]
                s1["task_store.dart"]
                s2["schedule_slot_store.dart"]
                s3["commitment_store.dart"]
                s4["user_profile_store.dart"]
                s5["daily_task_store.dart ⚠️ dead"]
                s6["schedule_store.dart ⚠️ dead"]
            end
            subgraph MODEL["models/"]
                m1["user_profile.dart"]
                m2["daily_task.dart ⚠️ dead"]
                m3["schedule_entry.dart ⚠️ dead"]
            end
        end
        subgraph SVC["services/ + utils/"]
            v1["auth_service.dart"]
            v2["time_utils.dart"]
        end
    end

    subgraph SHARED["shared/"]
        t1["theme/category_palette.dart"]
        w1["widgets/ — 8 files"]
    end

    subgraph FEATURES["features/"]
        f1["splash/"]
        f2["auth/ — 2 screens"]
        f3["onboarding/ — flow + 4 pages"]
        f4["home/ — screen + 6 widgets"]
    end

    style API fill:#e3f2fd
    style DATA fill:#e0f2f1
    style SHARED fill:#f3e5f5
    style FEATURES fill:#e8f5e9
    style STORE fill:#b2dfdb
    style DTOS fill:#bbdefb
```

---

## 4. HomeScreen — Component Structure

```mermaid
graph TB
    HS["HomeScreen<br/>features/home/home_screen.dart"]

    HS -->|"initState → postFrame"| INIT["_loadEverything<br/>Future.wait of 3 store loads<br/>→ _reportAnyError"]

    HS --> STACK["Stack"]
    STACK -->|"layer 1"| BG["FluidMorphBackground"]
    STACK -->|"layer 2"| PV["PageView + PageDots"]

    PV -->|"page 0"| DASH["DashboardPage<br/>Consumer2 TaskStore + SlotStore"]
    PV -->|"page 1"| TLP["Timeline page<br/>Consumer2 SlotStore + CommitmentStore"]

    DASH --> D1["live clock — 1s ticker"]
    DASH --> D2["distinct tasks today"]
    DASH --> D3["completed · planned time"]
    DASH --> D4["_UnplannedHint<br/>only when count > 0"]

    TLP --> T1["TimelineView"]
    TLP --> T2["WeekStrip"]
    TLP --> T3["date pill → DatePicker"]
    TLP --> T4["action menu FAB"]
    TLP --> T5["empty-day hint / spinner"]

    T4 --> M1["Add task → TaskCreationDialog"]
    T4 --> M2["Unplanned → UnplannedTasksSheet"]
    T4 --> M3["Plan my day → planDay"]
    T4 --> M4["Clear schedule → confirm"]

    T1 -->|"onSlotTap"| AS["TaskActionSheet"]
    M2 -->|"tap a task"| AS

    AS --> ACT["TaskStore:<br/>start · complete · skip<br/>postpone · delete"]
    ACT --> REF["slotStore.refresh"]

    style HS fill:#e8f5e9
    style DASH fill:#f0f4c3
    style TLP fill:#f0f4c3
    style AS fill:#e0f2f1
    style ACT fill:#ffccbc
```

The dashboard receives slots **only when the loaded day is really today** — a
counter that silently described a day the user merely browsed to would be worse
than no counter.

---

## 5. "Plan my day" — Sequence

```mermaid
sequenceDiagram
    actor U as User
    participant H as HomeScreen
    participant S as ScheduleSlotStore
    participant R as ScheduleRepository
    participant A as ApiClient
    participant B as AURA backend
    participant T as TaskStore

    U->>H: Menu → "Plan my day"
    H->>S: planDay()
    S->>S: isPlanning = true, notify
    S->>R: planSchedule()
    R->>A: POST /schedule/cpsat
    A->>A: getIdToken() → Bearer header
    A->>B: HTTP (30s timeout)
    B->>B: CP-SAT over every pending task
    B-->>A: scheduled[], dropped[], solve_status
    A-->>R: JSON
    R-->>S: CpsatResultDto

    Note over S: response carries NO slot ids
    S->>R: getDaySchedule(loadedDate)
    R->>B: GET /schedule/day?date=...
    B-->>S: booked_slots (with slot ids), free_gaps
    S->>S: isPlanning = false, notify

    S-->>H: CpsatResultDto
    H->>T: load()
    Note over H,T: planning changed task statuses;<br/>the unplanned count would go stale

    alt dropped is not empty
        H->>U: "Placed N. Could not fit: X, Y"
    else nothing pending
        H->>U: "Nothing to plan — add a task first."
    else success
        H->>U: "Placed N sessions."
    end
```

The refresh is not optional and the task reload is not optional. Those two
follow-ups are what keep block ids available and the unplanned badge honest.

---

## 6. Task State Machine

```mermaid
stateDiagram-v2
    [*] --> draft: POST /tasks
    draft --> scheduled: transition
    scheduled --> in_progress: START — stamps started_at
    in_progress --> paused
    paused --> in_progress
    in_progress --> completed: actualDuration measured
    scheduled --> completed: no duration recorded
    draft --> postponed
    scheduled --> postponed
    postponed --> scheduled: replan
    scheduled --> skipped
    in_progress --> partially_done
    scheduled --> abandoned
    completed --> [*]

    note right of in_progress
        The only path that yields a real
        actualDuration. Without it the
        behaviour profile stays empty.
    end note

    note right of completed
        TERMINAL. No transitions out,
        so the UI offers no un-complete.
    end note
```

Transitions are enforced **server-side**. `draft → completed` is rejected, which
is why the client uses `/complete`, `/postpone` and `/skip` — the server walks
the intermediate steps itself.

---

## 7. Timeline Rendering

```mermaid
graph TD
    TV["TimelineView<br/>StatefulWidget"]

    TV -->|"initState"| I1["ScrollController"]
    TV -->|"initState"| I2["Timer.periodic 30s → setState<br/>moves the now line only"]
    TV -->|"postFrame"| I3["_scrollToCurrentTime<br/>today only, −200px lead"]

    TV --> BUILD["build()"]
    BUILD --> GRP["group slots by taskId<br/>→ 'session n of m'"]
    BUILD --> CANVAS["Stack — 24 × 76px = 1824px"]

    CANVAS --> L1["Layer 1: hour grid<br/>00:00 – 24:00 + dividers"]
    CANVAS --> L2["Layer 2: fixed commitments<br/>SOLID BLUE — immovable"]
    CANVAS --> L3["Layer 3: task sessions<br/>SURFACE CARD + category spine"]
    CANVAS --> L4["Layer 4: now line<br/>#FF8FA3, today only"]

    L2 --> G["_blockGeometry<br/>clamp to range · null if zero height"]
    L3 --> G

    L3 --> ST{"slot.status"}
    ST -->|"completed"| S1["struck through, 40% opacity"]
    ST -->|"in_progress"| S2["2px accent border, play icon"]
    ST -->|"else"| S3["1px accent 40%, empty circle"]

    L3 -->|"onTap"| TAP["onSlotTap → TaskActionSheet"]

    style L2 fill:#bbdefb
    style L3 fill:#c8e6c9
    style L4 fill:#ffcdd2
    style G fill:#fff9c4
```

The two block styles are deliberately different: a user must tell at a glance
what is immovable from what the app decided, because only the latter can be
started, finished or moved. Both share `_blockGeometry`, so equal-length blocks
always line up exactly.

---

## 8. Request Lifecycle & Error Taxonomy

```mermaid
graph TD
    CALL["repository method"] --> HDR["_headers()"]
    HDR --> TOK{"token available?"}
    TOK -->|"no user"| E401A["ApiException 401<br/>'Not signed in.'"]
    TOK -->|"refresh failed"| E401B["ApiException 401<br/>'Could not refresh sign-in'"]
    TOK -->|"yes"| SEND["http.send().timeout(30s)"]

    SEND -->|"TimeoutException"| UNREACH["ApiUnreachableException"]
    SEND -->|"Socket / Handshake / Client"| UNREACH
    SEND -->|"response"| DEC["_decode()"]

    DEC --> ST{"status"}
    ST -->|"204 / empty"| NULLR["null"]
    ST -->|"2xx"| OK["decoded JSON → DTO"]
    ST -->|"401 / 403"| E401["isUnauthorized"]
    ST -->|"404"| E404["isNotFound<br/>also returned for<br/>another user's task"]
    ST -->|"422"| E422["isValidationError<br/>_extractDetail flattens<br/>FastAPI's field errors"]
    ST -->|"503"| E503["isServerMisconfigured<br/>missing service-account key"]

    E401 --> MSG1["'Your session expired.<br/>Please sign in again.'"]
    E503 --> MSG2["'The server is not<br/>fully configured yet.'<br/>NOT a sign-out"]
    UNREACH --> MSG3["'Cannot reach the server.<br/>Is the backend running?'"]

    MSG1 --> STORE["store.error<br/>never thrown into a build"]
    MSG2 --> STORE
    MSG3 --> STORE
    E422 --> STORE
    STORE --> SNACK["UI reads it after await<br/>→ snackbar → clearError()"]

    style UNREACH fill:#ffcdd2
    style E503 fill:#ffe0b2
    style OK fill:#c8e6c9
    style STORE fill:#fff9c4
```

Separating 503 from 401 is the point of the whole taxonomy: a missing server key
is not the user's fault, and reporting it as 401 would loop the app trying to
re-authenticate against a broken server.

---

## 9. Timezone Conversion

```mermaid
graph LR
    W["Backend<br/>2026-09-03T15:50:00+05:30<br/>means 15:50 IST"]
    W --> P1["DateTime.parse().toUtc()<br/>10:20 UTC<br/>right instant, wrong fields"]
    P1 --> P2["+ istOffset<br/>fields read 15:50<br/>but still flagged isUtc"]
    P2 --> P3["rebuild via DateTime(y,m,d,h,mi,s,ms)<br/>LOCAL-flagged wall clock"]
    P3 --> UI["Timeline draws 15:50<br/>on any device, any timezone"]

    P2 -.->|"❌ .toLocal() here"| BUG["Dart shifts it AGAIN<br/>15:50 renders as 21:20"]

    UI --> OUT["formatBackendTime()<br/>explicit +05:30"]
    OUT --> W2["Backend receives an<br/>offset-aware timestamp"]
    OUT -.->|"❌ bare toIso8601String()"| BUG2["No offset — FastAPI mixes<br/>naive and aware values"]

    style BUG fill:#ffcdd2
    style BUG2 fill:#ffcdd2
    style P3 fill:#c8e6c9
    style UI fill:#e8f5e9
```

The device timezone is irrelevant. The scheduler's intent is expressed in IST, so
the UI renders IST — never `.toLocal()`.

---

## 10. Onboarding Flow

```mermaid
graph LR
    OF["OnboardingFlow<br/>PageController"]
    OF -->|"postFrame"| LOAD["CommitmentStore.load()"]

    OF -->|"page 0"| P0["NamePage"]
    P0 -->|"next"| C1{"name entered?"}
    C1 -->|"NO"| E1["message, blocked"]
    E1 --> P0
    C1 -->|"YES"| P1["IntroPage<br/>auto-advance 2.4s"]
    P1 --> P2["StartPage<br/>auto-advance 2.4s"]
    P2 --> P3["WeeklySetupPage"]

    P3 -->|"add slot"| ADD["POST /schedule/commitments"]
    P3 -->|"Finish setup"| FIN["_finishOnboarding"]

    FIN --> C2{"name empty?"}
    C2 -->|"YES"| BACK["animate back to page 0"]
    C2 -->|"NO"| C3{"commitmentStore.hasAny?"}
    C3 -->|"NO"| E2["'Add at least one<br/>fixed weekly slot'"]
    C3 -->|"YES"| SAVE["UserProfileStore.save<br/>isOnboardingComplete = true"]

    SAVE --> DONE["OnboardingCompleteScreen"]
    DONE -->|"2.2s"| HOME["HomeScreen"]

    style P3 fill:#fff3e0
    style ADD fill:#e3f2fd
    style HOME fill:#e8f5e9
```

At least one commitment is required because the scheduler needs some shape of a
week to work around — otherwise every hour looks equally free and the plan is
meaningless. These go to the **server**, not local storage: kept locally, CP-SAT
could never see them, and every user was scheduled around one hardcoded
timetable.

---

## 11. State Update Flow

```mermaid
graph TD
    subgraph ROOTP["app.dart — MultiProvider"]
        AC["ApiClient (singleton)"]
        TS["TaskStore"]
        SS["ScheduleSlotStore"]
        CS["CommitmentStore"]
    end

    ACT["user action"] --> STORE["store method"]
    STORE --> AWAIT["await repository → server"]
    AWAIT --> ADOPT["adopt the server's response<br/>no optimistic local edit"]
    ADOPT --> NOTIFY["notifyListeners()"]

    NOTIFY --> C1["Consumer2 in _buildDashboardPage"]
    NOTIFY --> C2["Consumer2 in _buildTimelinePage"]
    NOTIFY --> C3["Consumer in WeeklySetupPage"]

    C1 --> RB["only that subtree rebuilds"]
    C2 --> RB
    C3 --> RB

    ERR["failure"] --> DESC["_describe(e) → sentence"]
    DESC --> HELD["store.error<br/>held, not thrown"]
    HELD --> READ["UI reads after await<br/>→ snackbar → clearError()"]

    TICK["Timer.periodic<br/>30s timeline / 1s dashboard"] --> LOCAL["setState — visual only"]

    style ROOTP fill:#f3e5f5
    style ADOPT fill:#c8e6c9
    style HELD fill:#fff9c4
    style ERR fill:#ffcdd2
```

Counters such as `procrastinationCount` are computed server-side, so a local
guess would drift. Every mutation awaits the server and swaps the local copy for
what comes back.

---

## Summary

| Diagram | Shows |
|---|---|
| 1 | Layer boundaries and what talks to what |
| 2 | Auth routing and where sign-up goes |
| 3 | File structure, including the four dead files |
| 4 | HomeScreen composition and its actions |
| 5 | Why "Plan my day" needs two follow-up fetches |
| 6 | The server-enforced task state machine |
| 7 | Timeline layers and why block styles differ |
| 8 | The error taxonomy, especially 401 vs 503 |
| 9 | IST handling and the two bugs it prevents |
| 10 | Onboarding gates and where commitments go |
| 11 | How a mutation reaches the screen |

---

**Last Updated:** September 7, 2026
**App Version:** 1.0.0+1 — backend-integrated (Phase 6)
