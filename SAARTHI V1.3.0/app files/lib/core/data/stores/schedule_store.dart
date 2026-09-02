import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_entry.dart';

class ScheduleStore extends ChangeNotifier {
  static const String _storageKey = 'schedule_entries_v1';
  final List<ScheduleEntry> _entries = [];

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return;
    }

    final restored = <ScheduleEntry>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        restored.add(ScheduleEntry.fromJson(item));
      } else if (item is Map) {
        restored.add(ScheduleEntry.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    _entries
      ..clear()
      ..addAll(restored);
    notifyListeners();
  }

  List<ScheduleEntry> entriesForDate(DateTime date) {
    final list = _entries.where((entry) => entry.occursOn(date)).toList();
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  List<ScheduleEntry> weeklyEntriesForWeekday(int weekday) {
    final list = _entries
        .where(
          (entry) =>
              entry.recurrence == ScheduleRecurrence.weekly &&
              entry.date.weekday == weekday,
        )
        .toList();
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  bool hasAnyWeeklyEntry() {
    return _entries.any((entry) => entry.recurrence == ScheduleRecurrence.weekly);
  }

  void addWeeklyEntry({
    required int weekday,
    required String title,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
  }) {
    final today = DateTime.now();
    final offset = weekday - today.weekday;
    final anchorDate = DateTime(
      today.year,
      today.month,
      today.day + offset,
    );

    addEntry(
      ScheduleEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        date: anchorDate,
        startTime: startTime,
        endTime: endTime,
        recurrence: ScheduleRecurrence.weekly,
      ),
    );
  }

  void addEntry(ScheduleEntry entry) {
    _entries.add(entry);
    _persist();
    notifyListeners();
  }

  void deleteEntryById(String id) {
    _entries.removeWhere((entry) => entry.id == id);
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = _entries.map((entry) => entry.toJson()).toList();
    await preferences.setString(_storageKey, jsonEncode(payload));
  }
}
