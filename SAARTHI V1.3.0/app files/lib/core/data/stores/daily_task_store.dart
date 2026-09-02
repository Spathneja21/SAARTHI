import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_task.dart';

class DailyTaskStore extends ChangeNotifier {
  static const String _storageKey = 'daily_tasks_v1';
  final List<DailyTask> _tasks = [];

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

    final restored = <DailyTask>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        restored.add(DailyTask.fromJson(item));
      } else if (item is Map) {
        restored.add(DailyTask.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    _tasks
      ..clear()
      ..addAll(restored);
    notifyListeners();
  }

  List<DailyTask> tasksForDate(DateTime date) {
    final list = _tasks.where((task) => _isSameDate(task.date, date)).toList();
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  void addTask({
    required String title,
    required DateTime date,
    required DateTime deadline,
    required int durationMinutes,
    required int priority,
    required TaskFlexibility flexibility,
  }) {
    _tasks.add(
      DailyTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        date: DateTime(date.year, date.month, date.day),
        deadline: deadline,
        durationMinutes: durationMinutes,
        priority: priority,
        flexibility: flexibility,
      ),
    );
    _persist();
    notifyListeners();
  }

  void toggleTask(String id, bool isDone) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1) {
      return;
    }
    _tasks[index] = _tasks[index].copyWith(isDone: isDone);
    _persist();
    notifyListeners();
  }

  void deleteTask(String id) {
    _tasks.removeWhere((task) => task.id == id);
    _persist();
    notifyListeners();
  }

  void deleteAllTasksForDate(DateTime date) {
    _tasks.removeWhere((task) => _isSameDate(task.deadline, date));
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = _tasks.map((task) => task.toJson()).toList();
    await preferences.setString(_storageKey, jsonEncode(payload));
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}
