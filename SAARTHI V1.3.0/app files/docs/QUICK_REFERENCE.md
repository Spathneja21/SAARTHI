# Saarthi — Quick Reference & File Index

## 📋 Documentation Files

| File | Content |
|---|---|
| **CONTROL_FLOW_DOCUMENTATION.md** | File-by-file control flow analysis, data structures, persistence, architecture patterns |
| **ARCHITECTURE_DIAGRAMS.md** | Visual Mermaid diagrams — navigation, components, data flow, dependencies, planned backend |
| **QUICK_REFERENCE.md** | This file — quick lookups, file index, code locations, common workflows |

---

## 📁 Project File Structure

```
lib/
├── main.dart ............................ Entry point (8 lines)
├── app.dart ............................. MaterialApp + theme (67 lines)
│
├── core/
│   ├── data/
│   │   ├── models/
│   │   │   ├── daily_task.dart .......... DailyTask + TaskFlexibility enum
│   │   │   ├── schedule_entry.dart ...... ScheduleEntry + ScheduleRecurrence enum
│   │   │   └── user_profile.dart ........ UserProfile data class
│   │   └── stores/
│   │       ├── daily_task_store.dart ..... DailyTaskStore (ChangeNotifier)
│   │       ├── schedule_store.dart ...... ScheduleStore (ChangeNotifier)
│   │       └── user_profile_store.dart .. UserProfileStore
│   └── utils/
│       └── time_utils.dart .............. isSameDate, compareTimes, etc.
│
├── shared/
│   └── widgets/
│       ├── circle_button.dart ........... Circular icon button
│       ├── page_dots.dart ............... Page indicator dots
│       ├── page_shell.dart .............. Scrollable page layout wrapper
│       ├── primary_button.dart .......... Styled primary button
│       ├── soft_blob.dart ............... Decorative background circle
│       ├── typewriter_block.dart ........ Multi-line typewriter animation
│       └── typewriter_text.dart ......... Single-line typewriter animation
│
└── features/
    ├── home/
    │   ├── home_screen.dart ............. Main home screen
    │   └── widgets/
    │       ├── timeline_view.dart ....... 24-hour scrollable timeline
    │       ├── task_creation_dialog.dart . Task creation form
    │       └── week_strip.dart .......... Horizontal week selector
    │
    ├── onboarding/
    │   ├── onboarding_flow.dart ......... 4-page onboarding container
    │   ├── onboarding_complete_screen.dart Post-onboarding transition
    │   └── pages/
    │       ├── intro_page.dart .......... Welcome page
    │       ├── name_page.dart ........... Name input page
    │       ├── start_page.dart .......... Schedule instructions
    │       └── weekly_setup_page.dart ... Weekly schedule builder
    │
    └── splash/
        └── splash_screen.dart ........... Animated splash + routing
```

---

## 🎯 Key Files by Purpose

### Entry & Navigation
| File | Purpose |
|---|---|
| `main.dart` | App entry point |
| `app.dart` | Theme + MaterialApp |
| `features/splash/splash_screen.dart` | Route to onboarding or home |

### Onboarding (4 pages in order)
| Page | File | Function |
|---|---|---|
| 0 | `features/onboarding/pages/name_page.dart` | Name input |
| 1 | `features/onboarding/pages/intro_page.dart` | Welcome |
| 2 | `features/onboarding/pages/start_page.dart` | Instructions |
| 3 | `features/onboarding/pages/weekly_setup_page.dart` | Schedule setup |

### Home Screen
| File | Widget | Purpose |
|---|---|---|
| `features/home/home_screen.dart` | `HomeScreen` | Main orchestrator |
| `features/home/widgets/timeline_view.dart` | `TimelineView` | 24h timeline |
| `features/home/widgets/task_creation_dialog.dart` | `TaskCreationDialog` | Task form |
| `features/home/widgets/week_strip.dart` | `WeekStrip` | Week selector |

### Data Layer
| File | Class | Type |
|---|---|---|
| `core/data/models/daily_task.dart` | `DailyTask` | Model |
| `core/data/models/schedule_entry.dart` | `ScheduleEntry` | Model |
| `core/data/models/user_profile.dart` | `UserProfile` | Model |
| `core/data/stores/daily_task_store.dart` | `DailyTaskStore` | ChangeNotifier |
| `core/data/stores/schedule_store.dart` | `ScheduleStore` | ChangeNotifier |
| `core/data/stores/user_profile_store.dart` | `UserProfileStore` | Plain class |

---

## 🔍 Quick Code Lookups

### Task Creation
**File:** `features/home/widgets/task_creation_dialog.dart`  
**Class:** `TaskCreationDialog`
```dart
_titleController              // task name
_deadline                     // task date (DateTime)
_deadlineTime                 // task time (TimeOfDay, default: 14:00)
_duration                     // 15-480 minutes (default: 60)
_priority                     // 1-5 slider (default: 3)
_flexibility                  // TaskFlexibility.flexible / .rigid
```

### Timeline Display
**File:** `features/home/widgets/timeline_view.dart`  
**Class:** `TimelineView`
```dart
_buildFixedEntry()           // Render purple schedule block
_buildTaskMarker()           // Render red deadline line
_buildNowLine()              // Render current time indicator
_scrollToCurrentTime()       // Auto-scroll to now (today only)
_offsetForMinute()           // Convert minutes to Y-position
```

### Data Persistence
**File:** `core/data/stores/daily_task_store.dart`  
**Class:** `DailyTaskStore`
```dart
load()                       // Load tasks from SharedPreferences
addTask()                    // Create + persist + notify
deleteTask(id)               // Remove + persist + notify
toggleTask(id, done)         // Update isDone + persist + notify
tasksForDate(date)           // Filter by date, sort by title
```

### Schedule Management
**File:** `core/data/stores/schedule_store.dart`  
**Class:** `ScheduleStore`
```dart
load()                       // Load from SharedPreferences
entriesForDate(date)         // All entries occurring on date
weeklyEntriesForWeekday(wd)  // Weekly entries for specific day
addWeeklyEntry(...)          // Create weekly recurring entry
deleteEntryById(id)          // Remove entry
hasAnyWeeklyEntry()          // Validation check
```

---

## 🎨 Color Palette

| Name | Hex | Usage |
|---|---|---|
| Base Background | `#FAF9F5` | Scaffold background |
| Primary | `#1E1A16` | Text, dark UI elements |
| Accent | `#8226E5` | Purple highlights, schedule blocks, active dots |
| Soft | `#DCD2E9` | Input field backgrounds |
| Menu Button | `#C9B8A8` | FAB and popup menu |
| Danger / Deadline | `#D00000` | Task deadlines, NOW line |
| Divider | `#B8B6B0` | Timeline hour lines |
| Week Border | `#E0D6C7` | Week strip day borders |
| Inactive Dot | `#B9AB9D` | Page dots, disabled buttons |

---

## ⏰ Timeline Constants

**File:** `features/home/widgets/timeline_view.dart`

| Constant | Value | Notes |
|---|---|---|
| `_timelineStartHour` | 0 | Midnight |
| `_timelineEndHour` | 23 | 11 PM |
| `_hourHeight` | 76px | Pixels per hour |
| `_labelWidth` | 58px | Time label column width |
| `_gapWidth` | 8px | Gap between label + content |

**Total canvas height:** 24 hours × 76px = **1,824px**

---

## 📊 State Management Pattern

**Pattern:** ChangeNotifier + AnimatedBuilder

```
Store.method()
  → _persist() (SharedPreferences)
  → notifyListeners()
  → AnimatedBuilder rebuilds
  → Fresh data read from store
```

**Local state (timer):**
```
TimelineView.Timer.periodic(30s)
  → setState({})
  → Lightweight rebuild: NOW line position only
```

---

## 💾 Storage Schema

### SharedPreferences Keys

```
USER PROFILE:
  "user_name_v1"                     → String
  "user_primary_task_v1"             → String
  "user_onboarding_complete_v1"      → bool

SCHEDULE:
  "schedule_entries_v1"              → JSON Array<ScheduleEntry>

TASKS:
  "daily_tasks_v1"                   → JSON Array<DailyTask>
```

### DailyTask JSON Structure
```json
{
  "id": "1712345678901234",
  "title": "Task name",
  "date": "2026-04-10T00:00:00.000",
  "deadline": "2026-04-10T14:30:00.000",
  "durationMinutes": 60,
  "priority": 3,
  "flexibility": "TaskFlexibility.flexible",
  "isDone": false
}
```

### ScheduleEntry JSON Structure
```json
{
  "id": "1712345678901234",
  "title": "Morning Class",
  "date": "2026-04-07T00:00:00.000",
  "startHour": 9,
  "startMinute": 0,
  "endHour": 10,
  "endMinute": 30,
  "recurrence": "weekly"
}
```

---

## 🚨 Safety Checks

### Delete Task Safety ✅
```
FAB → Delete Task
  → dailyTaskStore.deleteTask(id)     ✅ Only user tasks
  → scheduleStore is NEVER touched    ✅ Fixed schedule safe
```

### Mounted Check ✅
All async callbacks check `if (mounted)` before `setState()` or navigation.

### Overflow Clamping ✅
Timeline entries clamped to 0-23h range. Scroll position clamped to valid bounds.

---

## 🔄 Common Workflows

### Add a Task
1. HomeScreen → tap beige FAB menu
2. Select "Add Task"
3. Fill TaskCreationDialog (title, deadline, duration, priority, flexibility)
4. Tap "Create"
5. Task appears as red deadline line on timeline

### Delete a Task
1. HomeScreen → tap beige FAB menu
2. Select "Delete Task"
3. Dialog shows task list for selected date
4. Tap red delete icon on task
5. Confirmation snackbar, task disappears

### Change Date
1. Tap day in WeekStrip, OR
2. Tap date pill (top-right) → system DatePicker
3. Timeline updates with new date's entries + tasks
4. If today: NOW line shown + auto-scroll

### Edit Fixed Schedule
1. HomeScreen → AppBar → Edit calendar icon
2. Opens WeeklySetupPage with ScheduleStore
3. Select weekday → Add/delete fixed slots
4. Return → timeline reflects changes

---

## 📞 Files That Must Be Modified Together

| Change | Files to update |
|---|---|
| **Task model fields** | `core/data/models/daily_task.dart` + `core/data/stores/daily_task_store.dart` + `features/home/widgets/task_creation_dialog.dart` + `features/home/widgets/timeline_view.dart` |
| **Schedule model fields** | `core/data/models/schedule_entry.dart` + `core/data/stores/schedule_store.dart` + `features/home/widgets/timeline_view.dart` + `features/onboarding/pages/weekly_setup_page.dart` |
| **User profile fields** | `core/data/models/user_profile.dart` + `core/data/stores/user_profile_store.dart` |
| **Navigation flow** | `features/splash/splash_screen.dart` + `app.dart` |
| **Theme / colors** | `app.dart` (single source of truth) |

---

## 🔐 Current Constraints

- ✅ Priority enforced: 1-5 range
- ✅ Duration enforced: 15-480 minutes
- ✅ Name required for onboarding completion
- ✅ At least 1 weekly entry required
- ✅ All data stored locally (SharedPreferences, unencrypted)
- ⚠️ No authentication/login system (planned: Firebase Auth)
- ⚠️ No cloud sync (planned: FastAPI + PostgreSQL)
- ⚠️ No push notifications (planned: Firebase Cloud Messaging)

---

**Last Updated:** April 10, 2026  
**Version:** 1.0  
**Total Dart files:** 24
