# S.A.A.R.T.H.I

**Smart Automated Assistant for Routine Task Handling & Intelligent scheduling**

A Flutter-based productivity app that intelligently schedules tasks into your day by working around your fixed weekly schedule. Saarthi collects task details — duration, priority, flexibility, and deadline — and uses a scheduling algorithm to place tasks optimally into free time slots.

---

## 📱 Features

### Current (v1.0)
- **Onboarding Flow** — 4-page interactive setup (name entry, introduction, schedule instructions, weekly schedule builder)
- **Weekly Schedule Builder** — Define fixed recurring activities for each day of the week (classes, meetings, gym, etc.)
- **Timeline View** — 24-hour scrollable timeline displaying fixed schedule blocks and task deadlines
- **Task Management** — Create tasks with title, deadline, duration (15 min – 8 hrs), priority (1–5), and flexibility (rigid/flexible)
- **Live Time Indicator** — Real-time "now" line on today's timeline, auto-scrolling to current time
- **Week Navigation** — Horizontal week strip + date picker for browsing different days
- **Local Persistence** — All data persisted via SharedPreferences with JSON serialization

### Planned
- **Intelligent Scheduling** — Python-based algorithm (via FastAPI) to auto-place tasks into optimal free slots, with fragmentation for large tasks
- **Firebase Authentication** — Google Sign-In / Email login with per-user data sync
- **Push Notifications** — Task reminders via Firebase Cloud Messaging
- **Scheduled Task Blocks** — Visual time blocks on the timeline for algorithm-placed tasks
- **Task Editing** — Modify existing tasks and schedule entries
- **Progress Tracking** — Completion stats and streaks

---

## 🏗️ Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌────────────┐
│   Flutter App   │ ──API──▶│   FastAPI Server  │ ──SQL──▶│  PostgreSQL │
│                 │◀──JSON──│                   │◀────────│            │
│  • UI/Timeline  │         │  • Scheduling     │         │  • Users   │
│  • Local cache  │         │    algorithm      │         │  • Tasks   │
│  • Auth (soon)  │         │  • CRUD endpoints │         │  • Schedule│
└─────────────────┘         │  • Auth verify    │         │  • Blocks  │
                            └──────────────────┘         └────────────┘
```

---

## 📁 Project Structure

```
lib/
├── main.dart                                    # App entry point
├── app.dart                                     # MaterialApp + theme configuration
│
├── core/                                        # Business logic & data layer
│   ├── data/
│   │   ├── models/
│   │   │   ├── daily_task.dart                  # DailyTask model + TaskFlexibility enum
│   │   │   ├── schedule_entry.dart              # ScheduleEntry model + ScheduleRecurrence enum
│   │   │   └── user_profile.dart                # UserProfile model
│   │   └── stores/
│   │       ├── daily_task_store.dart             # DailyTaskStore (ChangeNotifier)
│   │       ├── schedule_store.dart               # ScheduleStore (ChangeNotifier)
│   │       └── user_profile_store.dart           # UserProfileStore
│   └── utils/
│       └── time_utils.dart                      # Date/time helper functions
│
├── shared/                                      # Reusable UI components
│   └── widgets/
│       ├── circle_button.dart                   # Circular icon button
│       ├── page_dots.dart                       # Page indicator dots
│       ├── page_shell.dart                      # Scrollable page layout wrapper
│       ├── primary_button.dart                  # Styled primary action button
│       ├── soft_blob.dart                       # Decorative background blob
│       ├── typewriter_block.dart                # Multi-line typewriter animation
│       └── typewriter_text.dart                 # Single-line typewriter animation
│
└── features/                                    # Feature-based screen modules
    ├── home/
    │   ├── home_screen.dart                     # Main home screen
    │   └── widgets/
    │       ├── timeline_view.dart               # 24-hour scrollable timeline
    │       ├── task_creation_dialog.dart         # Task creation form dialog
    │       └── week_strip.dart                  # Horizontal week day selector
    ├── onboarding/
    │   ├── onboarding_flow.dart                 # 4-page onboarding container
    │   ├── onboarding_complete_screen.dart       # Post-onboarding transition
    │   └── pages/
    │       ├── intro_page.dart                  # Welcome / introduction
    │       ├── name_page.dart                   # Name input with typewriter
    │       ├── start_page.dart                  # Schedule upload instructions
    │       └── weekly_setup_page.dart            # Fixed weekly schedule builder
    └── splash/
        └── splash_screen.dart                   # Animated splash + routing
```

---

## 🎨 Design System

| Token | Value | Usage |
|---|---|---|
| Base Background | `#FAF9F5` | Scaffold background |
| Primary | `#1E1A16` | Text, dark UI elements |
| Accent | `#8226E5` | Purple highlights, schedule blocks |
| Soft | `#DCD2E9` | Input fields, subtle backgrounds |
| Menu Button | `#C9B8A8` | FAB and popup menu |
| Danger | `#D00000` | Task deadlines, current time line |

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter (Dart) |
| **Backend** | FastAPI (Python) — planned |
| **Database** | PostgreSQL — planned |
| **Auth** | Firebase Auth — planned |
| **Notifications** | Firebase Cloud Messaging — planned |
| **Local Storage** | SharedPreferences |
| **Fonts** | Google Fonts (Google Sans Code) |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK `^3.10.7`
- Dart SDK (included with Flutter)

### Run Locally
```bash
# Clone the repository
git clone <repo-url>
cd saarthi

# Install dependencies
flutter pub get

# Run on connected device / emulator
flutter run
```

### Verify Code Quality
```bash
flutter analyze
```

---

## 📦 Dependencies

| Package | Version | Purpose |
|---|---|---|
| `google_fonts` | ^8.0.1 | Custom typography |
| `shared_preferences` | ^2.5.3 | Local data persistence |
| `intl` | ^0.19.0 | Date formatting |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |

---

## 👥 Team

| Role | Responsibility |
|---|---|
| **Frontend** | Flutter app UI, functionality, and integration |
| **Backend** | FastAPI server, PostgreSQL database, API endpoints |
| **Algorithm** | Python scheduling logic (task placement, fragmentation) |

---

## 📄 Documentation

- [Architecture Diagrams](docs/ARCHITECTURE_DIAGRAMS.md) — Visual Mermaid diagrams of navigation, components, data flow
- [Control Flow Documentation](docs/CONTROL_FLOW_DOCUMENTATION.md) — Detailed file-by-file control flow analysis
- [Quick Reference](docs/QUICK_REFERENCE.md) — File index, code lookups, common workflows

---

**Version:** 1.0.0  
**Last Updated:** April 10, 2026
