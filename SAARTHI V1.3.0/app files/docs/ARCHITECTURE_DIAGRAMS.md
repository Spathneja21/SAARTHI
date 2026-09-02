# Saarthi — Visual Architecture Diagrams

## 1. Application Navigation Flow

```mermaid
graph TD
    A["main.dart"] -->|runApp| B["SaarthiApp"]
    B -->|theme setup| C["SplashScreen"]
    C -->|load profile| D{Is Onboarding<br/>Complete?}
    D -->|NO| E["OnboardingFlow<br/>4 Pages"]
    D -->|YES| F["HomeScreen<br/>Main App"]
    
    E -->|page 0| E1["NamePage<br/>Enter Name"]
    E -->|page 1| E2["IntroPage<br/>Welcome"]
    E -->|page 2| E3["StartPage<br/>Instructions"]
    E -->|page 3| E4["WeeklySetupPage<br/>Schedule Setup"]
    
    E4 -->|finish| G["OnboardingCompleteScreen<br/>Save Profile + Schedule"]
    G -->|auto-navigate| F
    
    F -->|displays| F1["Timeline<br/>Task Management"]
    
    style A fill:#e1f5ff
    style C fill:#fff3e0
    style E fill:#f3e5f5
    style F fill:#e8f5e9
```

---

## 2. Project File Structure

```mermaid
graph TD
    subgraph ROOT["lib/"]
        main["main.dart"]
        app["app.dart"]
    end

    subgraph CORE["core/"]
        subgraph MODELS["data/models/"]
            m1["daily_task.dart"]
            m2["schedule_entry.dart"]
            m3["user_profile.dart"]
        end
        subgraph STORES["data/stores/"]
            s1["daily_task_store.dart"]
            s2["schedule_store.dart"]
            s3["user_profile_store.dart"]
        end
        subgraph UTILS["utils/"]
            u1["time_utils.dart"]
        end
    end

    subgraph SHARED["shared/widgets/"]
        w1["page_shell.dart"]
        w2["typewriter_text.dart"]
        w3["typewriter_block.dart"]
        w4["page_dots.dart"]
        w5["circle_button.dart"]
        w6["primary_button.dart"]
        w7["soft_blob.dart"]
    end

    subgraph FEATURES["features/"]
        subgraph HOME["home/"]
            h1["home_screen.dart"]
            subgraph HOME_W["widgets/"]
                hw1["timeline_view.dart"]
                hw2["task_creation_dialog.dart"]
                hw3["week_strip.dart"]
            end
        end
        subgraph ONB["onboarding/"]
            o1["onboarding_flow.dart"]
            o2["onboarding_complete_screen.dart"]
            subgraph ONB_P["pages/"]
                op1["intro_page.dart"]
                op2["name_page.dart"]
                op3["start_page.dart"]
                op4["weekly_setup_page.dart"]
            end
        end
        subgraph SPL["splash/"]
            sp1["splash_screen.dart"]
        end
    end

    style CORE fill:#e0f2f1
    style SHARED fill:#f3e5f5
    style FEATURES fill:#e8f5e9
    style MODELS fill:#c8e6c9
    style STORES fill:#b2dfdb
```

---

## 3. HomeScreen — Component Structure

```mermaid
graph TB
    HS["HomeScreen<br/>(Stateful Widget)<br/>features/home/home_screen.dart"]
    
    HS -->|initState| INIT["Initialize:<br/>- Selected Date<br/>- Load ScheduleStore<br/>- Load DailyTaskStore"]
    
    HS -->|build| AB["AnimatedBuilder<br/>listens to:<br/>ScheduleStore<br/>DailyTaskStore"]
    
    AB --> STACK["Stack<br/>Overlays"]
    
    STACK -->|layer 1| COL["Column<br/>Main Layout"]
    STACK -->|layer 2| DATE_PILL["Date Selector Pill<br/>top-right"]
    STACK -->|layer 3| FAB["Menu FAB<br/>bottom-right"]
    
    COL -->|child 1| WEEK["WeekStrip<br/>widgets/week_strip.dart"]
    COL -->|child 2| TL["TimelineView<br/>widgets/timeline_view.dart"]
    
    WEEK -->|action| WEEK_ACTION["onDateSelected<br/>setState _selectedDate"]
    
    TL -->|displays| TL1["Hour Labels 0-23"]
    TL -->|displays| TL2["Fixed Schedule Entries<br/>Purple blocks"]
    TL -->|displays| TL3["User Tasks<br/>Red deadline lines"]
    TL -->|displays| TL4["NOW Line<br/>Red Circle + Line"]
    
    DATE_PILL -->|action| DATE_ACTION["Open DatePicker"]
    
    FAB -->|menu item 1| FAB1["Add Task"]
    FAB -->|menu item 2| FAB2["Delete Task"]
    
    FAB1 -->|opens| MODAL1["TaskCreationDialog<br/>widgets/task_creation_dialog.dart"]
    FAB2 -->|opens| MODAL2["Task Deletion Dialog<br/>AlertDialog"]
    
    MODAL1 -->|onTaskCreated| ACTION1["dailyTaskStore.addTask()"]
    MODAL2 -->|delete| ACTION2["dailyTaskStore.deleteTask()"]
    
    ACTION1 -->|persist| SP1["SharedPreferences"]
    ACTION2 -->|persist| SP1
    
    ACTION1 -->|notify| AB
    ACTION2 -->|notify| AB
    
    style HS fill:#e8f5e9
    style AB fill:#fff9c4
    style WEEK fill:#f0f4c3
    style TL fill:#f0f4c3
    style FAB fill:#ffccbc
    style MODAL1 fill:#e0f2f1
    style MODAL2 fill:#e0f2f1
```

---

## 4. Timeline View — Detailed Structure

```mermaid
graph TD
    TV["TimelineView<br/>(StatefulWidget)<br/>features/home/widgets/timeline_view.dart"]
    
    TV -->|initState| TV_INIT["1. Create ScrollController<br/>2. Start 30s Timer<br/>3. Queue AUTO_SCROLL"]
    
    TV_INIT -->|post frame| TV_SCROLL["_scrollToCurrentTime():<br/>if today → animate scroll<br/>to current time"]
    
    TV -->|build| TV_SCROLL_VW["SingleChildScrollView"]
    
    TV_SCROLL_VW -->|contains| TV_STACK["Stack<br/>24-hour canvas<br/>Height: 24 × 76px = 1824px"]
    
    TV_STACK -->|renders| TV_LABELS["For hour 0-23:<br/>time label + divider"]
    
    TV_STACK -->|renders| TV_FIXED["For each ScheduleEntry:<br/>_buildFixedEntry()<br/>Purple colored blocks"]
    
    TV_STACK -->|renders| TV_TASKS["For each DailyTask:<br/>_buildTaskMarker()<br/>Red lines + controls"]
    
    TV_STACK -->|renders| TV_NOW["if today:<br/>_buildNowLine()<br/>Red circle + line"]
    
    TV -->|every 30s| TV_TIMER["Timer.periodic<br/>setState()"]
    
    TV_TIMER -->|update| TV_NOW
    
    style TV fill:#f0f4c3
    style TV_INIT fill:#d1c4e9
    style TV_STACK fill:#c8e6c9
    style TV_FIXED fill:#e1bee7
    style TV_TASKS fill:#ffcdd2
    style TV_NOW fill:#ffcdd2
```

---

## 5. Task Creation Dialog Flow

```mermaid
graph LR
    TCD["TaskCreationDialog<br/>features/home/widgets/<br/>task_creation_dialog.dart"]
    
    TCD --> INPUT["Input Collection:<br/>- Task name<br/>- Deadline date<br/>- Deadline time<br/>- Duration slider<br/>15-480 min<br/>- Priority slider<br/>1-5<br/>- Flexibility toggle"]
    
    INPUT --> VALIDATE["Validation:<br/>- Name not empty?"]
    
    VALIDATE -->|FAIL| ERROR["Show error<br/>Stay in dialog"]
    VALIDATE -->|PASS| BUILD["Build DateTime<br/>from date + time"]
    
    BUILD --> CREATE_CALL["onTaskCreated()<br/>callback"]
    
    CREATE_CALL --> ADD_TASK["DailyTaskStore<br/>.addTask()"]
    
    ADD_TASK --> PERSIST["_persist():<br/>Write JSON<br/>to SharedPreferences"]
    
    PERSIST --> NOTIFY["notifyListeners()"]
    
    NOTIFY --> REBUILD["AnimatedBuilder<br/>rebuilds"]
    
    REBUILD --> APPEAR["Task appears<br/>on timeline<br/>as red deadline line"]
    
    style TCD fill:#e0f2f1
    style INPUT fill:#e1f5fe
    style VALIDATE fill:#fff9c4
    style ERROR fill:#ffcdd2
    style PERSIST fill:#c8e6c9
    style APPEAR fill:#f0f4c3
```

---

## 6. Data Architecture

```mermaid
graph TB
    subgraph MODELS["Data Models<br/>core/data/models/"]
        UP["UserProfile<br/>- name<br/>- primaryTask<br/>- isOnboardingComplete"]
        SE["ScheduleEntry<br/>- id, title<br/>- date<br/>- startTime, endTime<br/>- recurrence"]
        DT["DailyTask<br/>- id, title<br/>- date, deadline<br/>- durationMinutes<br/>- priority<br/>- flexibility<br/>- isDone"]
    end
    
    subgraph STORES["Data Stores<br/>core/data/stores/<br/>(ChangeNotifier)"]
        UPS["UserProfileStore<br/>- load()<br/>- save()"]
        SS["ScheduleStore<br/>- load(), addEntry()<br/>- deleteEntryById()<br/>- entriesForDate()<br/>- addWeeklyEntry()"]
        DTS["DailyTaskStore<br/>- load(), addTask()<br/>- deleteTask()<br/>- toggleTask()<br/>- tasksForDate()"]
    end
    
    subgraph STORAGE["Persistent Storage"]
        SP["SharedPreferences<br/>JSON Serialization"]
    end
    
    UPS -.->|manages| UP
    SS -.->|manages| SE
    DTS -.->|manages| DT
    
    UPS -->|read/write| SP
    SS -->|read/write| SP
    DTS -->|read/write| SP
    
    style MODELS fill:#e8eaf6
    style STORES fill:#f3e5f5
    style STORAGE fill:#c8e6c9
```

---

## 7. File Dependencies Graph

```mermaid
graph TD
    main["main.dart"]
    app["app.dart"]
    
    subgraph SPLASH["features/splash/"]
        splash["splash_screen.dart"]
    end
    
    subgraph ONBOARDING["features/onboarding/"]
        onb_flow["onboarding_flow.dart"]
        onb_complete["onboarding_complete_screen.dart"]
        intro["pages/intro_page.dart"]
        name["pages/name_page.dart"]
        start["pages/start_page.dart"]
        weekly["pages/weekly_setup_page.dart"]
    end
    
    subgraph HOME["features/home/"]
        home["home_screen.dart"]
        timeline["widgets/timeline_view.dart"]
        task_dlg["widgets/task_creation_dialog.dart"]
        week_strip["widgets/week_strip.dart"]
    end
    
    subgraph CORE["core/"]
        models["data/models/*"]
        stores["data/stores/*"]
        utils["utils/time_utils.dart"]
    end
    
    subgraph SHARED_W["shared/widgets/"]
        widgets["page_shell, page_dots,<br/>circle_button, soft_blob,<br/>typewriter_text/block,<br/>primary_button"]
    end
    
    main --> app
    app --> splash
    splash --> home
    splash --> onb_flow
    
    onb_flow --> onb_complete
    onb_flow --> intro
    onb_flow --> name
    onb_flow --> start
    onb_flow --> weekly
    onb_flow --> stores
    onb_flow --> widgets
    
    onb_complete --> home
    
    home --> stores
    home --> timeline
    home --> task_dlg
    home --> week_strip
    home --> weekly
    
    timeline --> models
    timeline --> utils
    task_dlg --> models
    week_strip --> utils
    weekly --> stores
    weekly --> utils
    weekly --> widgets
    
    intro --> widgets
    name --> widgets
    start --> widgets
    
    stores --> models
    
    style CORE fill:#e0f2f1
    style SHARED_W fill:#f3e5f5
    style HOME fill:#e8f5e9
    style ONBOARDING fill:#fff3e0
    style SPLASH fill:#fff9c4
```

---

## 8. Onboarding Flow — Page Progression

```mermaid
graph LR
    OF["OnboardingFlow<br/>PageController<br/>features/onboarding/<br/>onboarding_flow.dart"]
    
    OF -->|page 0| P0["NamePage<br/>Enter Name"]
    P0 -->|next| CHECK1{Name<br/>entered?}
    
    CHECK1 -->|NO| ERROR1["Show error<br/>Block progression"]
    ERROR1 -->|retry| P0
    
    CHECK1 -->|YES| P1["IntroPage<br/>Welcome Message"]
    P1 -->|next| P2["StartPage<br/>Schedule Instructions"]
    
    P2 -->|next| P3["WeeklySetupPage<br/>7-day schedule<br/>Add time slots"]
    
    P3 -->|finish button| FINISH["_finishOnboarding()"]
    
    FINISH -->|validate| CHECK2{Has weekly<br/>entries?}
    CHECK2 -->|NO| ERROR2["Show error:<br/>Add at least 1 slot"]
    CHECK2 -->|YES| SAVE["Save UserProfile<br/>isOnboardingComplete=true"]
    
    SAVE --> COMPLETE["OnboardingCompleteScreen<br/>Loading transition"]
    COMPLETE -->|auto 2.2s| HOME["HomeScreen"]
    
    style OF fill:#f3e5f5
    style P0 fill:#ede7f6
    style P1 fill:#e1f5fe
    style P2 fill:#f1f8e9
    style P3 fill:#fff3e0
    style HOME fill:#e8f5e9
```

---

## 9. State Update Flow

```mermaid
graph TD
    subgraph STORES["Stores (ChangeNotifier)<br/>core/data/stores/"]
        DS1["ScheduleStore"]
        DS2["DailyTaskStore"]
    end
    
    subgraph HOME["HomeScreen"]
        AB["AnimatedBuilder<br/>Listenable.merge<br/>[ScheduleStore, DailyTaskStore]"]
    end
    
    DS1 -->|notifyListeners| AB
    DS2 -->|notifyListeners| AB
    
    AB -->|rebuild| SUBTREE["Rebuilds only<br/>this subtree:<br/>WeekStrip + TimelineView"]
    
    SUBTREE -.->|does NOT rebuild| PARENT["AppBar, FAB,<br/>Date Pill"]
    
    subgraph TIMELINE["TimelineView"]
        TIMER["Timer.periodic(30s)<br/>setState()"]
        NOW["NOW line position<br/>visual-only update"]
    end
    
    TIMER -->|lightweight| NOW
    
    style STORES fill:#f3e5f5
    style AB fill:#fff9c4
    style SUBTREE fill:#c8e6c9
    style TIMELINE fill:#f0f4c3
```

---

## 10. Planned Architecture — With Backend

```mermaid
graph TB
    subgraph CLIENT["Flutter App"]
        UI["UI Layer<br/>features/*"]
        AUTH["Firebase Auth"]
        CACHE["Local Cache<br/>SharedPreferences"]
        API_SVC["API Service Layer<br/>(planned)"]
    end
    
    subgraph BACKEND["FastAPI Server (planned)"]
        ENDPOINTS["REST Endpoints"]
        SCHEDULER["Python Scheduling<br/>Algorithm"]
        FB_ADMIN["Firebase Admin SDK<br/>Token Verification"]
    end
    
    subgraph DB["PostgreSQL (planned)"]
        USERS["users table"]
        TASKS["tasks table"]
        SCHEDULE["schedule table"]
        BLOCKS["scheduled_blocks table"]
    end
    
    UI --> API_SVC
    UI --> AUTH
    UI --> CACHE
    
    API_SVC -->|HTTP + Bearer token| ENDPOINTS
    AUTH -->|ID token| API_SVC
    
    ENDPOINTS --> FB_ADMIN
    ENDPOINTS --> SCHEDULER
    ENDPOINTS --> DB
    
    SCHEDULER -->|reads| SCHEDULE
    SCHEDULER -->|reads| TASKS
    SCHEDULER -->|writes| BLOCKS
    
    style CLIENT fill:#e8f5e9
    style BACKEND fill:#e3f2fd
    style DB fill:#fff3e0
```

---

## Summary

These diagrams provide visual representation of:
- ✅ Application navigation & lifecycle
- ✅ Project file structure & organization
- ✅ Component hierarchy & data flow
- ✅ User interaction flows
- ✅ State management patterns
- ✅ Persistence & storage architecture
- ✅ File dependencies
- ✅ Planned backend architecture

---

**Last Updated:** April 10, 2026  
**App Version:** v1.0 (Onboarding + Timeline)
