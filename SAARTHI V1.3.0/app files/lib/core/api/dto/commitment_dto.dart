import 'package:flutter/material.dart' show TimeOfDay;

/// How a fixed commitment repeats. Mirrors the backend's
/// `CommitmentRecurrence`; wire values are lowercase snake_case.
enum CommitmentRecurrence {
  oneTime('one_time', 'One time'),
  daily('daily', 'Daily'),
  weekly('weekly', 'Weekly');

  const CommitmentRecurrence(this.wire, this.label);
  final String wire;
  final String label;

  static CommitmentRecurrence fromWire(String value) =>
      CommitmentRecurrence.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => CommitmentRecurrence.weekly,
      );
}

/// A recurring block of unavailable time — a class, a shift, a standing meeting.
///
/// CP-SAT treats these as immovable, so together they define the gaps that
/// tasks get scheduled into. They replace the old global `fixed_tasks.json`,
/// which applied one hardcoded university timetable to every account.
///
/// Times are minutes from midnight rather than timestamps, because a recurring
/// commitment has no single date — it is a wall-clock pattern projected onto
/// concrete days. This matches `ScheduleEntry.startMinutes` on the app side, so
/// neither end has to convert.
class FixedCommitmentDto {
  const FixedCommitmentDto({
    required this.id,
    required this.title,
    required this.recurrence,
    this.weekday,
    this.specificDate,
    required this.startMinute,
    required this.endMinute,
    required this.isActive,
  });

  final String id;
  final String title;
  final CommitmentRecurrence recurrence;

  /// 0 = Monday … 6 = Sunday, matching Python's `datetime.weekday()`.
  ///
  /// Careful: Dart's `DateTime.weekday` is 1 = Monday … 7 = Sunday, so a
  /// conversion is required in both directions. See [fromDartWeekday].
  final int? weekday;

  /// Set only for one-time commitments.
  final DateTime? specificDate;

  final int startMinute;
  final int endMinute;
  final bool isActive;

  TimeOfDay get startTime =>
      TimeOfDay(hour: startMinute ~/ 60, minute: startMinute % 60);

  /// An end of exactly 1440 means midnight, which `TimeOfDay` cannot express as
  /// hour 24, so it is clamped to 23:59 for display purposes only.
  TimeOfDay get endTime => endMinute >= 1440
      ? const TimeOfDay(hour: 23, minute: 59)
      : TimeOfDay(hour: endMinute ~/ 60, minute: endMinute % 60);

  int get durationMinutes => endMinute - startMinute;

  /// Convert Dart's 1-7 weekday into the backend's 0-6.
  static int fromDartWeekday(int dartWeekday) => dartWeekday - 1;

  /// Convert the backend's 0-6 weekday into Dart's 1-7.
  static int toDartWeekday(int backendWeekday) => backendWeekday + 1;

  /// Does this commitment fall on the given day?
  bool occursOn(DateTime day) {
    switch (recurrence) {
      case CommitmentRecurrence.daily:
        return true;
      case CommitmentRecurrence.weekly:
        return weekday != null && weekday == fromDartWeekday(day.weekday);
      case CommitmentRecurrence.oneTime:
        final d = specificDate;
        return d != null &&
            d.year == day.year &&
            d.month == day.month &&
            d.day == day.day;
    }
  }

  factory FixedCommitmentDto.fromJson(Map<String, dynamic> json) {
    final rawDate = json['specific_date'] as String?;
    return FixedCommitmentDto(
      id: json['id'] as String,
      title: json['title'] as String,
      recurrence: CommitmentRecurrence.fromWire(json['recurrence'] as String),
      weekday: json['weekday'] as int?,
      // A plain `YYYY-MM-DD` date, not a timestamp — parse as a wall-clock day
      // with no timezone shifting.
      specificDate: rawDate == null ? null : DateTime.parse(rawDate),
      startMinute: json['start_minute'] as int,
      endMinute: json['end_minute'] as int,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Request body for `POST /schedule/commitments`.
///
/// The backend validates the shape and rejects a weekly commitment with no
/// weekday, a one-time one with no date, or `end_minute <= start_minute`.
class FixedCommitmentCreateRequest {
  const FixedCommitmentCreateRequest({
    required this.title,
    required this.recurrence,
    this.weekday,
    this.specificDate,
    required this.startMinute,
    required this.endMinute,
  });

  FixedCommitmentCreateRequest.weekly({
    required this.title,
    required int dartWeekday,
    required TimeOfDay start,
    required TimeOfDay end,
  })  : recurrence = CommitmentRecurrence.weekly,
        weekday = FixedCommitmentDto.fromDartWeekday(dartWeekday),
        specificDate = null,
        startMinute = start.hour * 60 + start.minute,
        endMinute = end.hour * 60 + end.minute;

  final String title;
  final CommitmentRecurrence recurrence;
  final int? weekday;
  final DateTime? specificDate;
  final int startMinute;
  final int endMinute;

  Map<String, dynamic> toJson() => {
        'title': title,
        'recurrence': recurrence.wire,
        if (weekday != null) 'weekday': weekday,
        if (specificDate != null)
          'specific_date':
              '${specificDate!.year.toString().padLeft(4, '0')}-'
              '${specificDate!.month.toString().padLeft(2, '0')}-'
              '${specificDate!.day.toString().padLeft(2, '0')}',
        'start_minute': startMinute,
        'end_minute': endMinute,
      };
}
