enum TaskFlexibility { flexible, rigid }

class DailyTask {
  DailyTask({
    required this.id,
    required this.title,
    required this.date,
    required this.deadline,
    required this.durationMinutes,
    required this.priority,
    required this.flexibility,
    this.isDone = false,
  });

  final String id;
  final String title;
  final DateTime date;
  final DateTime deadline;
  final int durationMinutes;
  final int priority;
  final TaskFlexibility flexibility;
  final bool isDone;

  DailyTask copyWith({
    String? id,
    String? title,
    DateTime? date,
    DateTime? deadline,
    int? durationMinutes,
    int? priority,
    TaskFlexibility? flexibility,
    bool? isDone,
  }) {
    return DailyTask(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      deadline: deadline ?? this.deadline,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      priority: priority ?? this.priority,
      flexibility: flexibility ?? this.flexibility,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'date': DateTime(date.year, date.month, date.day).toIso8601String(),
      'deadline': deadline.toIso8601String(),
      'durationMinutes': durationMinutes,
      'priority': priority,
      'flexibility': flexibility.toString(),
      'isDone': isDone,
    };
  }

  static DailyTask fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.parse(json['date'] as String);
    final parsedDeadline = DateTime.parse(json['deadline'] as String);
    final flexibilityStr = (json['flexibility'] as String?)?? 'TaskFlexibility.flexible';
    final flexibility = flexibilityStr.contains('rigid')
        ? TaskFlexibility.rigid
        : TaskFlexibility.flexible;

    return DailyTask(
      id: json['id'] as String,
      title: json['title'] as String,
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      deadline: parsedDeadline,
      durationMinutes: json['durationMinutes'] as int? ?? 60,
      priority: json['priority'] as int? ?? 3,
      flexibility: flexibility,
      isDone: json['isDone'] as bool? ?? false,
    );
  }
}
