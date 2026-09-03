import '../backend_time.dart';
import 'task_dto.dart';

/// One block of time the scheduler assigned to a task.
///
/// Mirrors an entry of `booked_slots` from `GET /schedule/day`. Note that a
/// single task can own **several** slots: CP-SAT splits anything longer than its
/// focus limit into multiple sessions that share a `taskId`, so the timeline
/// must render them as separate blocks rather than assuming one block per task.
class ScheduledSlotDto {
  const ScheduledSlotDto({
    required this.slotId,
    required this.taskId,
    required this.title,
    required this.category,
    required this.priority,
    required this.start,
    required this.end,
    required this.createdBy,
    required this.status,
    required this.estimatedDuration,
    this.deadline,
  });

  final String slotId;
  final String taskId;
  final String title;
  final TaskCategory category;
  final int priority;
  final DateTime start;
  final DateTime end;

  /// "ai" when CP-SAT placed it, "user" when booked by hand.
  final String createdBy;

  /// The parent *task's* status, not the slot's — slots have no status.
  final TaskStatus status;
  final int estimatedDuration;
  final DateTime? deadline;

  bool get isAiPlaced => createdBy == 'ai';

  int get durationMinutes => end.difference(start).inMinutes;

  /// Minutes from midnight — what the timeline uses to position a block.
  int get startMinutes => start.hour * 60 + start.minute;
  int get endMinutes => end.hour * 60 + end.minute;

  factory ScheduledSlotDto.fromJson(Map<String, dynamic> json) {
    return ScheduledSlotDto(
      slotId: json['slot_id'] as String,
      taskId: json['task_id'] as String,
      title: json['title'] as String,
      category: TaskCategory.fromWire(json['category'] as String),
      priority: json['priority'] as int? ?? 5,
      start: parseBackendTime(json['start'] as String),
      end: parseBackendTime(json['end'] as String),
      createdBy: json['created_by'] as String? ?? 'ai',
      status: TaskStatus.fromWire(json['status'] as String),
      estimatedDuration: json['estimated_duration'] as int? ?? 0,
      deadline: parseBackendTimeOrNull(json['deadline'] as String?),
    );
  }
}

/// A stretch of unbooked time inside working hours.
class FreeGapDto {
  const FreeGapDto({
    required this.start,
    required this.end,
    required this.durationMinutes,
  });

  final DateTime start;
  final DateTime end;
  final int durationMinutes;

  factory FreeGapDto.fromJson(Map<String, dynamic> json) => FreeGapDto(
        start: parseBackendTime(json['start'] as String),
        end: parseBackendTime(json['end'] as String),
        durationMinutes: json['duration_minutes'] as int,
      );
}

/// The full `GET /schedule/day` response.
class DayScheduleDto {
  const DayScheduleDto({
    required this.date,
    required this.bookedSlots,
    required this.freeGaps,
    required this.totalBookedMinutes,
  });

  final String date;
  final List<ScheduledSlotDto> bookedSlots;
  final List<FreeGapDto> freeGaps;
  final int totalBookedMinutes;

  factory DayScheduleDto.fromJson(Map<String, dynamic> json) => DayScheduleDto(
        date: json['date'] as String,
        bookedSlots: (json['booked_slots'] as List<dynamic>? ?? [])
            .map((e) => ScheduledSlotDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        freeGaps: (json['free_gaps'] as List<dynamic>? ?? [])
            .map((e) => FreeGapDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalBookedMinutes: json['total_booked_minutes'] as int? ?? 0,
      );
}

/// One chunk placed by a `POST /schedule/cpsat` run.
///
/// Deliberately has no `slotId`: the solver's response does not include the
/// database ids of the rows it just wrote. Re-fetch `GET /schedule/day` when
/// slot ids are needed (for example to move a block).
class CpsatAssignmentDto {
  const CpsatAssignmentDto({
    required this.taskId,
    required this.title,
    required this.chunkIndex,
    required this.start,
    required this.end,
    required this.overrunMinutes,
    required this.onTime,
    required this.behavioralScore,
    required this.completionProbability,
    required this.procrastinationRisk,
  });

  final String taskId;
  final String title;

  /// 0-based index of this session within its task, for "session 2 of 3".
  final int chunkIndex;
  final DateTime start;
  final DateTime end;

  /// Minutes past the deadline this placement runs, when the solver had to
  /// overshoot to fit everything.
  final double overrunMinutes;
  final bool onTime;

  /// 0-100 blend of energy match, urgency and the ML predictions.
  final double behavioralScore;

  /// 0-1 from the XGBoost model. Flat 0.5 until the model has been trained on
  /// at least ten resolved tasks, so early values are not meaningful.
  final double completionProbability;

  /// 0-1 from LightGBM, with a heuristic fallback before training.
  final double procrastinationRisk;

  factory CpsatAssignmentDto.fromJson(Map<String, dynamic> json) =>
      CpsatAssignmentDto(
        taskId: json['task_id'] as String,
        title: json['title'] as String,
        chunkIndex: json['chunk_index'] as int? ?? 0,
        start: parseBackendTime(json['start'] as String),
        end: parseBackendTime(json['end'] as String),
        overrunMinutes: (json['overrun'] as num?)?.toDouble() ?? 0,
        onTime: json['on_time'] as bool? ?? true,
        behavioralScore: (json['behavioral_score'] as num?)?.toDouble() ?? 0,
        completionProbability:
            (json['completion_prob'] as num?)?.toDouble() ?? 0.5,
        procrastinationRisk:
            (json['procrastination_risk'] as num?)?.toDouble() ?? 0,
      );
}

/// The full `POST /schedule/cpsat` response.
class CpsatResultDto {
  const CpsatResultDto({
    required this.scheduled,
    required this.dropped,
    required this.warnings,
    required this.solveStatus,
    required this.solveTimeMs,
  });

  final List<CpsatAssignmentDto> scheduled;

  /// Titles of tasks the solver could not fit. Must be surfaced to the user —
  /// silently dropping them is how a task disappears without explanation.
  final List<String> dropped;
  final List<String> warnings;

  /// "OPTIMAL", "FEASIBLE", "INFEASIBLE", "UNKNOWN", or "SKIPPED" when there
  /// was nothing pending to schedule.
  final String solveStatus;
  final double solveTimeMs;

  bool get solved => solveStatus == 'OPTIMAL' || solveStatus == 'FEASIBLE';
  bool get hadNothingToDo => solveStatus == 'SKIPPED';

  factory CpsatResultDto.fromJson(Map<String, dynamic> json) => CpsatResultDto(
        scheduled: (json['scheduled'] as List<dynamic>? ?? [])
            .map((e) => CpsatAssignmentDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        dropped: (json['dropped'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        warnings: (json['warnings'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        solveStatus: json['solve_status'] as String? ?? 'UNKNOWN',
        solveTimeMs: (json['solve_time_ms'] as num?)?.toDouble() ?? 0,
      );
}
