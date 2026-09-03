import '../backend_time.dart';

/// The backend's `TaskCategory`. Wire values are lowercase snake_case.
///
/// This is not decoration: `category` is one of the features both ML models
/// train on (`ml/ml_features.py` encodes it via `category_map`), and
/// `cpsat_bridge.aura_task_to_saarthi` reads it to pick a focus limit. The task
/// creation UI has to collect it.
enum TaskCategory {
  deepWork('deep_work', 'Deep work'),
  admin('admin', 'Admin'),
  learning('learning', 'Learning'),
  meeting('meeting', 'Meeting'),
  personal('personal', 'Personal'),
  health('health', 'Health');

  const TaskCategory(this.wire, this.label);
  final String wire;
  final String label;

  static TaskCategory fromWire(String value) => TaskCategory.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => TaskCategory.deepWork,
      );
}

/// The backend's `EnergyLevel`.
///
/// Drives slot choice: `cpsat_bridge` matches this against a `DEFAULT_ENERGY`
/// curve that peaks around 10am, so a `peak` task is pushed toward the user's
/// sharpest hours and a `veryLow` one toward the dregs of the day.
enum EnergyLevel {
  veryLow('very_low', 'Very low'),
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  peak('peak', 'Peak');

  const EnergyLevel(this.wire, this.label);
  final String wire;
  final String label;

  static EnergyLevel fromWire(String value) => EnergyLevel.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => EnergyLevel.medium,
      );
}

/// The backend's `TaskStatus` state machine.
///
/// Transitions are enforced server-side (`task_service.VALID_TRANSITIONS`), so
/// the client must not assume it can jump between arbitrary states — notably
/// `draft -> completed` is rejected. Use the `/complete`, `/postpone` and
/// `/skip` endpoints, which walk the machine internally.
enum TaskStatus {
  draft('draft', 'Draft'),
  scheduled('scheduled', 'Scheduled'),
  inProgress('in_progress', 'In progress'),
  paused('paused', 'Paused'),
  completed('completed', 'Completed'),
  partiallyDone('partially_done', 'Partly done'),
  postponed('postponed', 'Postponed'),
  skipped('skipped', 'Skipped'),
  abandoned('abandoned', 'Abandoned');

  const TaskStatus(this.wire, this.label);
  final String wire;
  final String label;

  static TaskStatus fromWire(String value) => TaskStatus.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => TaskStatus.draft,
      );

  /// Terminal: the server allows no transitions out of `completed`, so the UI
  /// must not offer an "un-complete" action.
  bool get isTerminal => this == TaskStatus.completed;

  bool get isResolved =>
      this == TaskStatus.completed ||
      this == TaskStatus.abandoned ||
      this == TaskStatus.skipped ||
      this == TaskStatus.partiallyDone;
}

/// Mirrors the backend's `TaskRead` schema exactly.
class TaskDto {
  const TaskDto({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    required this.energyRequirement,
    required this.estimatedDuration,
    this.actualDuration,
    required this.priority,
    this.deadline,
    required this.status,
    required this.procrastinationCount,
    required this.rescheduleCount,
    required this.skipCount,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
  });

  /// Server-assigned UUID. Never mint this client-side.
  final String id;
  final String title;
  final String? description;
  final TaskCategory category;
  final EnergyLevel energyRequirement;

  /// Minutes.
  final int estimatedDuration;

  /// Minutes actually spent, or null when unknown.
  ///
  /// Null is the *normal* case for a task that was simply ticked off: the
  /// backend only records a duration when the task genuinely passed through
  /// `in_progress`, rather than inventing one. Treat null as "not measured",
  /// never as zero.
  final int? actualDuration;

  final int priority;
  final DateTime? deadline;
  final TaskStatus status;
  final int procrastinationCount;
  final int rescheduleCount;
  final int skipCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isDone => status == TaskStatus.completed;

  factory TaskDto.fromJson(Map<String, dynamic> json) {
    return TaskDto(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: TaskCategory.fromWire(json['category'] as String),
      energyRequirement: EnergyLevel.fromWire(json['energy_requirement'] as String),
      estimatedDuration: json['estimated_duration'] as int,
      actualDuration: json['actual_duration'] as int?,
      priority: json['priority'] as int,
      deadline: parseBackendTimeOrNull(json['deadline'] as String?),
      status: TaskStatus.fromWire(json['status'] as String),
      procrastinationCount: json['procrastination_count'] as int? ?? 0,
      rescheduleCount: json['reschedule_count'] as int? ?? 0,
      skipCount: json['skip_count'] as int? ?? 0,
      createdAt: parseBackendTime(json['created_at'] as String),
      updatedAt: parseBackendTime(json['updated_at'] as String),
      startedAt: parseBackendTimeOrNull(json['started_at'] as String?),
      completedAt: parseBackendTimeOrNull(json['completed_at'] as String?),
    );
  }
}

/// Request body for `POST /tasks`.
class TaskCreateRequest {
  const TaskCreateRequest({
    required this.title,
    required this.category,
    required this.energyRequirement,
    required this.estimatedDuration,
    this.priority = 5,
    this.deadline,
    this.description,
  });

  final String title;
  final TaskCategory category;
  final EnergyLevel energyRequirement;
  final int estimatedDuration;
  final int priority;
  final DateTime? deadline;
  final String? description;

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category.wire,
        'energy_requirement': energyRequirement.wire,
        'estimated_duration': estimatedDuration,
        'priority': priority,
        if (deadline != null) 'deadline': formatBackendTime(deadline!),
        if (description != null) 'description': description,
      };
}

/// Request body for `PATCH /tasks/{id}`.
///
/// Only non-null fields are sent. The backend uses `exclude_unset`, so an
/// omitted key leaves that column untouched — which also means a deadline
/// cannot be *cleared* through this route, only changed.
class TaskUpdateRequest {
  const TaskUpdateRequest({
    this.title,
    this.category,
    this.energyRequirement,
    this.estimatedDuration,
    this.priority,
    this.deadline,
    this.description,
  });

  final String? title;
  final TaskCategory? category;
  final EnergyLevel? energyRequirement;
  final int? estimatedDuration;
  final int? priority;
  final DateTime? deadline;
  final String? description;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (category != null) 'category': category!.wire,
        if (energyRequirement != null) 'energy_requirement': energyRequirement!.wire,
        if (estimatedDuration != null) 'estimated_duration': estimatedDuration,
        if (priority != null) 'priority': priority,
        if (deadline != null) 'deadline': formatBackendTime(deadline!),
        if (description != null) 'description': description,
      };

  bool get isEmpty => toJson().isEmpty;
}
