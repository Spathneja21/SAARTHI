import 'package:flutter/material.dart';

enum ScheduleRecurrence {
  oneTime,
  daily,
  weekly,
}

class ScheduleEntry {
  ScheduleEntry({
    required this.id,
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.recurrence,
  });

  final String id;
  final String title;
  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final ScheduleRecurrence recurrence;

  bool occursOn(DateTime day) {
    if (recurrence == ScheduleRecurrence.daily) {
      return true;
    }
    if (recurrence == ScheduleRecurrence.weekly) {
      return day.weekday == date.weekday;
    }
    return day.year == date.year && day.month == date.month && day.day == date.day;
  }

  int get startMinutes => startTime.hour * 60 + startTime.minute;
  int get endMinutes => endTime.hour * 60 + endTime.minute;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
      'recurrence': recurrence.name,
    };
  }

  static ScheduleEntry fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.parse(json['date'] as String);
    final recurrenceName = json['recurrence'] as String;
    final parsedRecurrence = ScheduleRecurrence.values.firstWhere(
      (item) => item.name == recurrenceName,
      orElse: () => ScheduleRecurrence.oneTime,
    );

    return ScheduleEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      startTime: TimeOfDay(
        hour: json['startHour'] as int,
        minute: json['startMinute'] as int,
      ),
      endTime: TimeOfDay(
        hour: json['endHour'] as int,
        minute: json['endMinute'] as int,
      ),
      recurrence: parsedRecurrence,
    );
  }
}
