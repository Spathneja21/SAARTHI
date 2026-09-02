import 'package:flutter/material.dart';

// Time helpers for schedule layout and formatting.
int compareTimes(TimeOfDay a, TimeOfDay b) {
  final aMinutes = a.hour * 60 + a.minute;
  final bMinutes = b.hour * 60 + b.minute;
  return aMinutes.compareTo(bMinutes);
}

String formatHourLabel(int hour24) {
  final suffix = hour24 < 12 ? 'am' : 'pm';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12 $suffix';
}

String dayHeader(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

bool isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

int minutesFromTime(TimeOfDay time) {
  return time.hour * 60 + time.minute;
}

int minutesFromDate(DateTime time) {
  return time.hour * 60 + time.minute;
}
