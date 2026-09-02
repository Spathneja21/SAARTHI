# Saarthi — Control Flow & Architecture Documentation

## Project Overview

Saarthi (S.A.A.R.T.H.I — Smart Automated Assistant for Routine Task Handling & Intelligent scheduling) is a Flutter-based productivity app built with a feature-based architecture. The app follows a clean separation between data models, state stores, shared widgets, and feature screens.

**Current stack:** Flutter + SharedPreferences (local cache)  
**Planned stack:** Flutter ↔ FastAPI ↔ PostgreSQL + Firebase Auth

---

## 1. Application Entry Point & Navigation Flow

### File: `lib/main.dart`
**Purpose:** Application entry point  
**Responsibility:** Initialize Flutter application

```
main() 
  └─> runApp(SaarthiApp)
```

---

### File: `lib/app.dart`
**Purpose:** Root widget configuration  
**Responsibility:** Set up theme, colors, and typography

**Control Flow:**
```
SaarthiApp (StatelessWidget)
  └─> MaterialApp
       ├─> Theme Configuration
       │    ├─ Base Color: #FAF9F5 (warm cream)
       │    ├─ Primary: #1E1A16 (dark brown)
       │    ├─ Accent: #8226E5 (purple)
       │    └─ Soft: #DCD2E9 (light purple)
       └─> home: SplashScreen()
```

**Import:** `features/splash/splash_screen.dart`

---

## 2. Splash Screen & Navigation Logic

### File: `lib/features/splash/splash_screen.dart`
**Purpose:** Initial loading screen with navigation routing  
**Responsibility:** Load user profile and route to appropriate screen

**Control Flow:**
```
SplashScreen (StatefulWidget)
  │
  ├─ initState()
  │  ├─> AnimationController (2200ms)
  │  └─> onStatusListener
  │      └─> if COMPLETED → _navigateToNextScreen()
  │
  ├─ _navigateToNextScreen()
  │  ├─> UserProfileStore.load()
  │  ├─> if (profile.isOnboardingComplete)
  │  │    └─> NavigateTo: HomeScreen(profile)
  │  └─> else
  │       └─> NavigateTo: OnboardingFlow()
  │
  └─ build()
     └─> Animated "S.A.A.R.T.H.I" text + progress bar
```

**Data Dependencies:**
- `core/data/stores/user_profile_store.dart` → Load user profile

---

## 3. Onboarding Flow

### File: `lib/features/onboarding/onboarding_flow.dart`
**Purpose:** Multi-step onboarding process  
**Responsibility:** Collect user information and set up default schedule

**Control Flow:**
```
OnboardingFlow (StatefulWidget)
  │
  ├─ initState()
  │  └─> _scheduleStore.load()
  │
  ├─ PageView Controller (4 pages, 0-3)
  │  ├─ Page 0 → NamePage (name input)
  │  ├─ Page 1 → IntroPage (welcome message)
  │  ├─ Page 2 → StartPage (schedule upload instructions)
  │  └─ Page 3 → WeeklySetupPage (schedule setup)
  │
  ├─ _goNext()
  │  ├─> if (page 0 & name empty) → Show error, block
  │  └─> else → PageController.nextPage()
  │
  ├─ _finishOnboarding() [triggered on page 3]
  │  ├─> Validate name not empty
  │  ├─> Validate at least 1 weekly entry
  │  ├─> UserProfileStore.save(profile)
  │  ├─> Mark isOnboardingComplete = true
  │  └─> NavigateTo: OnboardingCompleteScreen(profile)
  │
  ├─ UI structure
  │  ├─> SoftBlob decorations (top-left, bottom-right)
  │  ├─> PageDots indicator (shared/widgets/)
  │  ├─> PageView with 4 pages
  │  └─> CircleButton navigation (back/forward/check)
  │
  └─ dispose()
     ├─> _controller.dispose()
     └─> _nameController.dispose()
```

**Data Dependencies:**
- `core/data/stores/user_profile_store.dart` → Save profile
- `core/data/stores/schedule_store.dart` → Load/save weekly schedule
- `shared/widgets/` → PageDots, CircleButton, SoftBlob

---

### File: `lib/features/onboarding/pages/name_page.dart`
**Purpose:** Collect user's name (Page 0)
```
NamePage (StatelessWidget)
  ├─> TypewriterBlock animation: "HI! There," / "Tell us your name"
  └─> TextField(nameController) centered
      └─> PageShell wrapper with centered layout
```

---

### File: `lib/features/onboarding/pages/intro_page.dart`
**Purpose:** Welcome message (Page 1)
```
IntroPage (StatelessWidget)
  └─> ValueListenableBuilder (reads name in real-time)
      ├─> "Hello, [name]" title
      ├─> "I am S.A.A.R.T.H.I." (accent color)
      └─> "Your friend/guide for your productive future."
```

---

### File: `lib/features/onboarding/pages/start_page.dart`
**Purpose:** Schedule upload instructions (Page 2)
```
StartPage (StatelessWidget)
  └─> "Upload your Everyday schedule in the next section."
      └─> "Everyday" highlighted in accent color
```

---

### File: `lib/features/onboarding/pages/weekly_setup_page.dart`
**Purpose:** Configure weekly fixed schedule (Page 3)
```
WeeklySetupPage (StatefulWidget)
  │
  ├─ _selectedWeekday (1-7, default: today)
  │
  ├─ _WeekdaySelector (ChoiceChips: Mon-Sun)
  │  └─> Changes _selectedWeekday
  │
  ├─ "Add fixed slot" button
  │  └─> _showAddWeeklyEntryDialog()
  │      ├─> TextField: task name
  │      ├─> ListTile: start time picker
  │      ├─> ListTile: end time picker
  │      ├─> Validation: name not empty, end > start
  │      └─> scheduleStore.addWeeklyEntry()
  │
  ├─ AnimatedBuilder (listens to scheduleStore)
  │  └─> List of entries for selected weekday
  │      └─> Card with title, times, delete button
  │
  └─ Uses: compareTimes() from core/utils/time_utils.dart
```

---

### File: `lib/features/onboarding/onboarding_complete_screen.dart`
**Purpose:** Transition screen after onboarding
```
OnboardingCompleteScreen (StatefulWidget)
  │
  ├─ AnimationController (1800ms, repeat reverse)
  │  └─> Pulsing CircularProgressIndicator
  │
  ├─ Timer (2200ms) → auto-navigate to HomeScreen
  │
  └─ Display: "Now that I have your fixed schedule, lets get started"
```

---

## 4. Home Screen — Main Application

### File: `lib/features/home/home_screen.dart`
**Purpose:** Main timeline-based task management interface  
**Responsibility:** Orchestrate stores, display timeline, handle user interactions

**Control Flow:**
```
HomeScreen (StatefulWidget)
  │
  ├─ initState()
  │  ├─> _selectedDate = Today (date only, no time)
  │  ├─> _scheduleStore.load()
  │  └─> _dailyTaskStore.load()
  │
  ├─ build()
  │  ├─> AppBar
  │  │   ├─> "Hello, [name]" title
  │  │   └─> Edit fixed schedule icon button
  │  │
  │  └─> Body: AnimatedBuilder (listens to both stores)
  │     └─> Stack layout
  │        ├─ Layer 1: Column
  │        │  ├─ WeekStrip (widgets/week_strip.dart)
  │        │  │  └─> onDateSelected → setState
  │        │  └─ TimelineView (widgets/timeline_view.dart)
  │        │     ├─> fixedEntries from scheduleStore
  │        │     ├─> dayTasks from dailyTaskStore
  │        │     ├─> onTaskToggle → dailyTaskStore.toggleTask()
  │        │     └─> onTaskDelete → dailyTaskStore.deleteTask()
  │        │
  │        ├─ Layer 2: Date Pill (top-right, positioned)
  │        │  └─> "SUNDAY, 12th Feb" format → opens date picker
  │        │
  │        └─ Layer 3: PopupMenuButton FAB (bottom-right)
  │           ├─> "Add Task" → _showAddTaskDialog()
  │           └─> "Delete Task" → _showTaskDeletionDialog()
  │
  ├─ _showAddTaskDialog()
  │  └─> Opens TaskCreationDialog (widgets/task_creation_dialog.dart)
  │      └─> onTaskCreated → dailyTaskStore.addTask()
  │
  ├─ _showTaskDeletionDialog()
  │  ├─> Get tasks for selected date
  │  ├─> if empty → snackbar "No tasks to delete"
  │  └─> Dialog with ListView of tasks + delete buttons
  │
  ├─ _openFixedScheduleEditor()
  │  └─> Navigate to WeeklySetupPage with scheduleStore
  │
  ├─ dispose()
  │  ├─> _scheduleStore.dispose()
  │  └─> _dailyTaskStore.dispose()
  │
  └─ Helper methods
     ├─ _formatDatePill() → "SUNDAY, 12th Feb" format
     └─ _ordinal() → 1st, 2nd, 3rd, etc.
```

---

### File: `lib/features/home/widgets/timeline_view.dart`
**Purpose:** 24-hour scrollable timeline with schedule blocks and task markers
```
TimelineView (StatefulWidget) — PUBLIC widget
  │
  ├─ Props: selectedDate, fixedEntries, dayTasks, onTaskToggle, onTaskDelete
  │
  ├─ initState()
  │  ├─> Create ScrollController
  │  ├─> Timer.periodic(30 seconds) → setState() to update NOW line
  │  └─> WidgetsBinding.addPostFrameCallback()
  │      └─> _scrollToCurrentTime() → Auto-scroll to NOW (today only)
  │
  ├─ build()
  │  └─ SingleChildScrollView
  │     └─ Stack (height: 24 × 76px = 1824px)
  │        ├─ Hour labels (00:00 - 24:00) with dividers
  │        ├─ _buildFixedEntry() for each ScheduleEntry → purple blocks
  │        ├─ _buildTaskMarker() for each DailyTask → red deadline lines
  │        └─ _buildNowLine() → red circle + line (today only)
  │
  ├─ Constants
  │  ├─ _timelineStartHour = 0
  │  ├─ _timelineEndHour = 23
  │  ├─ _hourHeight = 76px
  │  ├─ _labelWidth = 58px
  │  └─ _gapWidth = 8px
  │
  └─ dispose()
     ├─> _minuteTicker.cancel()
     └─> _scrollController.dispose()
```

---

### File: `lib/features/home/widgets/task_creation_dialog.dart`
**Purpose:** Dialog for creating new daily tasks
```
TaskCreationDialog (StatefulWidget) — PUBLIC widget
  │
  ├─ Props: initialDate, onTaskCreated callback
  │
  ├─ State variables
  │  ├─ _titleController (task name)
  │  ├─ _deadline (DateTime, default: initialDate)
  │  ├─ _deadlineTime (TimeOfDay, default: 14:00)
  │  ├─ _duration (int, range: 15-480 min, default: 60)
  │  ├─ _priority (int, range: 1-5, default: 3)
  │  └─ _flexibility (TaskFlexibility.flexible)
  │
  ├─ Dialog (AlertDialog, 350×500)
  │  ├─ TextField: task name
  │  ├─ ListTile: deadline date → showDatePicker()
  │  ├─ ListTile: deadline time → showTimePicker()
  │  ├─ Slider: duration (15-480 min, 30 divisions)
  │  ├─ Slider: priority (1-5, 4 divisions + badge)
  │  └─ ChoiceChips: Flexible / Rigid
  │
  └─ Actions
     ├─ Cancel → pop dialog
     └─ Create → validate name → build deadline DateTime → callback
```

---

### File: `lib/features/home/widgets/week_strip.dart`
**Purpose:** Horizontal scrollable week day selector
```
WeekStrip (StatelessWidget) — PUBLIC widget
  │
  ├─ Props: selectedDate, onDateSelected callback
  │
  └─ ListView.separated (horizontal, 7 items)
     └─> For each day of the week:
         ├─ Container (64×72, rounded 14px)
         ├─ Weekday short name (Mon, Tue, ...)
         ├─ Day number
         ├─ Selected: purple bg + white text
         └─ onTap → onDateSelected(date)
```

---

## 5. Core Data Layer

### File: `lib/core/data/models/user_profile.dart`
```
UserProfile (Immutable Data Class)
  ├─ name: String
  ├─ primaryTask: String
  ├─ isOnboardingComplete: bool
  └─ static empty → default values
```

### File: `lib/core/data/models/daily_task.dart`
```
enum TaskFlexibility { flexible, rigid }

DailyTask (Immutable Data Class)
  ├─ id: String (microsecondsSinceEpoch)
  ├─ title: String
  ├─ date: DateTime (date only)
  ├─ deadline: DateTime (date + time)
  ├─ durationMinutes: int (15-480)
  ├─ priority: int (1-5)
  ├─ flexibility: TaskFlexibility
  ├─ isDone: bool
  ├─ copyWith() → immutable updates
  ├─ toJson() → Map<String, dynamic>
  └─ fromJson() → DailyTask (static factory)
```

### File: `lib/core/data/models/schedule_entry.dart`
```
enum ScheduleRecurrence { oneTime, daily, weekly }

ScheduleEntry (Immutable Data Class)
  ├─ id: String
  ├─ title: String
  ├─ date: DateTime (anchor date for weekday)
  ├─ startTime: TimeOfDay
  ├─ endTime: TimeOfDay
  ├─ recurrence: ScheduleRecurrence
  ├─ occursOn(DateTime) → bool
  ├─ startMinutes / endMinutes (computed getters)
  ├─ toJson() → Map<String, dynamic>
  └─ fromJson() → ScheduleEntry (static factory)
```

---

## 6. Core Data Stores

### File: `lib/core/data/stores/user_profile_store.dart`
```
UserProfileStore (plain class, NOT ChangeNotifier)
  │
  ├─ SharedPreferences keys:
  │  ├─ 'user_name_v1'
  │  ├─ 'user_primary_task_v1'
  │  └─ 'user_onboarding_complete_v1'
  │
  ├─ load() → Future<UserProfile>
  │  └─> Read from SharedPreferences, return UserProfile
  │
  └─ save(UserProfile) → Future<void>
     └─> Write all fields to SharedPreferences
```

### File: `lib/core/data/stores/daily_task_store.dart`
```
DailyTaskStore (ChangeNotifier)
  │
  ├─ _tasks: List<DailyTask> (in-memory cache)
  ├─ _storageKey = 'daily_tasks_v1'
  │
  ├─ load() → Read JSON from SharedPreferences, populate _tasks
  ├─ tasksForDate(DateTime) → filtered + sorted by title
  ├─ addTask(title, date, deadline, duration, priority, flexibility)
  │  └─> Add to _tasks → _persist() → notifyListeners()
  ├─ toggleTask(id, isDone)
  │  └─> Update in _tasks → _persist() → notifyListeners()
  ├─ deleteTask(id)
  │  └─> Remove from _tasks → _persist() → notifyListeners()
  ├─ deleteAllTasksForDate(date) [exists but unused in UI]
  │
  └─ _persist() → Encode _tasks to JSON, write to SharedPreferences
```

### File: `lib/core/data/stores/schedule_store.dart`
```
ScheduleStore (ChangeNotifier)
  │
  ├─ _entries: List<ScheduleEntry> (in-memory cache)
  ├─ _storageKey = 'schedule_entries_v1'
  │
  ├─ load() → Read JSON from SharedPreferences, populate _entries
  ├─ entriesForDate(DateTime) → filtered by occursOn() + sorted by startMinutes
  ├─ weeklyEntriesForWeekday(int) → filtered weekly entries for day
  ├─ hasAnyWeeklyEntry() → bool
  ├─ addWeeklyEntry(weekday, title, startTime, endTime)
  │  └─> Creates ScheduleEntry with weekly recurrence → addEntry()
  ├─ addEntry(ScheduleEntry) → Add → _persist() → notifyListeners()
  ├─ deleteEntryById(id) → Remove → _persist() → notifyListeners()
  │
  └─ _persist() → Encode _entries to JSON, write to SharedPreferences
```

---

## 7. Core Utilities

### File: `lib/core/utils/time_utils.dart`
```
compareTimes(TimeOfDay a, TimeOfDay b) → int
  └─> Compare two times by total minutes

formatHourLabel(int hour24) → String
  └─> "12 am", "1 pm", etc.

dayHeader(DateTime) → String
  └─> "27 Mar 2026"

isSameDate(DateTime a, DateTime b) → bool
  └─> Compare year, month, day only

minutesFromTime(TimeOfDay) → int
minutesFromDate(DateTime) → int
```

---

## 8. Shared Widgets

### Directory: `lib/shared/widgets/`

| Widget | File | Purpose |
|---|---|---|
| `PageShell` | `page_shell.dart` | Scrollable page layout with title + child, used by all onboarding pages |
| `TypewriterText` | `typewriter_text.dart` | Character-by-character text reveal animation |
| `TypewriterBlock` | `typewriter_block.dart` | Multi-line typewriter with per-line styles |
| `PageDots` | `page_dots.dart` | Animated page indicator dots (active = wider) |
| `CircleButton` | `circle_button.dart` | Round icon button (used for onboarding nav) |
| `PrimaryButton` | `primary_button.dart` | Styled elevated button with accent color |
| `SoftBlob` | `soft_blob.dart` | Decorative circular background blob |

---

## 9. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Entry Point                              │
│                    main() → SaarthiApp                       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│             features/splash/splash_screen.dart              │
│  (Check isOnboardingComplete via UserProfileStore)          │
│                                                             │
│  ├─ If COMPLETE → HomeScreen(profile)                      │
│  └─ If NOT      → OnboardingFlow()                         │
└─────────────────────────────────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌────────────────────────┐   ┌────────────────────────────┐
│  OnboardingFlow        │   │  HomeScreen                │
│  (4 pages)             │   │                            │
│                        │   │ ┌────────────────────────┐ │
│ Page 0: NamePage       │   │ │ WeekStrip              │ │
│ Page 1: IntroPage      │   │ │ (week_strip.dart)      │ │
│ Page 2: StartPage      │   │ └────────────────────────┘ │
│ Page 3: WeeklySetupPage│   │ ┌────────────────────────┐ │
│         ↓              │   │ │ TimelineView           │ │
│ OnboardingComplete     │   │ │ (timeline_view.dart)   │ │
│ Screen → HomeScreen    │   │ │ - Fixed blocks         │ │
│                        │   │ │ - Task markers         │ │
│                        │   │ │ - NOW line             │ │
│                        │   │ └────────────────────────┘ │
│                        │   │ ┌────────────────────────┐ │
│                        │   │ │ TaskCreationDialog     │ │
│                        │   │ │ (FAB → Add Task)       │ │
│                        │   │ └────────────────────────┘ │
└────────────────────────┘   └────────────────────────────┘
         │                               │
         └───────────────┬───────────────┘
                         │
                         ▼
              ┌──────────────────┐
              │  core/data/      │
              │                  │
              │  models/         │
              │  ├ daily_task    │
              │  ├ schedule_entry│
              │  └ user_profile  │
              │                  │
              │  stores/         │
              │  ├ DailyTaskStore│
              │  ├ ScheduleStore │
              │  └ UserProfile   │
              │    Store         │
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │ SharedPreferences│
              │ (Local JSON)     │
              └──────────────────┘
```

---

## 10. Error Handling & Edge Cases

### Handled Scenarios

| Scenario | Location | Handling |
|----------|----------|----------|
| Empty name on onboarding | `onboarding_flow.dart` | Show error, block page progression |
| No weekly entries | `onboarding_flow.dart` | Show error, block finish |
| Empty task name | `task_creation_dialog.dart` | Show snackbar, stay in dialog |
| End time ≤ start time | `weekly_setup_page.dart` | Show error, auto-adjust end time |
| Delete with no tasks | `home_screen.dart` | Show snackbar "No tasks to delete" |
| Task deadline outside 0-23h | `timeline_view.dart` | Not rendered (silently filtered) |
| Widget disposed during async | All screens | Check `if (mounted)` before setState |
| Missing persistent data | All stores | Return defaults (empty profile, empty lists) |
| Scroll overflow | `timeline_view.dart` | Clamped using `.clamp(0, maxScroll)` |
| Fixed entry outside range | `timeline_view.dart` | Clamped start/end, skip if zero height |

---

## 11. Architecture Summary Table

| Layer | Component | File Location |
|-------|-----------|---------------|
| **Entry** | main, SaarthiApp | `lib/main.dart`, `lib/app.dart` |
| **Features** | SplashScreen | `features/splash/` |
| | OnboardingFlow + pages | `features/onboarding/` |
| | HomeScreen + widgets | `features/home/` |
| **Core Data** | Models (DailyTask, ScheduleEntry, UserProfile) | `core/data/models/` |
| | Stores (DailyTaskStore, ScheduleStore, UserProfileStore) | `core/data/stores/` |
| **Core Utils** | Time helpers | `core/utils/` |
| **Shared UI** | Reusable widgets | `shared/widgets/` |
| **Storage** | SharedPreferences | via `shared_preferences` package |

---

## 12. Key Design Patterns

### 1. ChangeNotifier Pattern
- `DailyTaskStore` and `ScheduleStore` extend `ChangeNotifier`
- UI listens via `AnimatedBuilder(animation: Listenable.merge([...]))`
- Stores call `notifyListeners()` on every data mutation

### 2. Feature-Based Architecture
- Each feature (`home`, `onboarding`, `splash`) has its own directory
- Feature-specific widgets live under `feature/widgets/`
- Shared widgets live under `shared/widgets/`

### 3. Model-Store Separation
- Models are pure data classes with serialization (no side effects)
- Stores manage collections of models + persistence + notifications

### 4. Immutable Data Classes
- Models use `final` fields + `copyWith()` for updates
- `fromJson()` / `toJson()` for persistence

### 5. Callback-Based Communication
- Widgets communicate upward via callbacks (`onTaskToggle`, `onDateSelected`)
- Downward via constructor parameters

---

## 13. SharedPreferences Storage Schema

```
USER PROFILE:
  "user_name_v1"                     → String
  "user_primary_task_v1"             → String
  "user_onboarding_complete_v1"      → bool

SCHEDULE (Weekly Fixed):
  "schedule_entries_v1"              → JSON Array<ScheduleEntry>

TASKS (Daily):
  "daily_tasks_v1"                   → JSON Array<DailyTask>
```

---

## 14. Code Metrics

- **Total Dart files:** 24
- **Feature files:** 10 (screens + feature widgets)
- **Core files:** 7 (models + stores + utils)
- **Shared widget files:** 7
- **Architecture:** Feature-based with MVC-like separation
- **State Management:** ChangeNotifier + AnimatedBuilder
- **Data Persistence:** SharedPreferences with JSON serialization

---

**Documentation Generated:** April 10, 2026  
**App Version:** v1.0 (Onboarding + Timeline)  
**Last Updated:** April 10, 2026
