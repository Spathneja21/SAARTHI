import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saarthi/core/api/dto/task_dto.dart';
import 'package:saarthi/features/home/widgets/task_editor_dialog.dart';

TaskDto _task() {
  final now = DateTime(2026, 9, 24, 9);
  return TaskDto(
    id: 'task-1',
    title: 'Write the report',
    category: TaskCategory.deepWork,
    energyRequirement: EnergyLevel.high,
    estimatedDuration: 90,
    priority: 4,
    deadline: DateTime(2026, 9, 25, 14),
    status: TaskStatus.scheduled,
    procrastinationCount: 0,
    rescheduleCount: 0,
    skipCount: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Future<TaskUpdateRequest?> _pumpAndSave(
  WidgetTester tester, {
  String? newTitle,
}) async {
  TaskUpdateRequest? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TaskEditorDialog.edit(
          task: _task(),
          onUpdate: (r) => captured = r,
        ),
      ),
    ),
  );
  await tester.pump();

  if (newTitle != null) {
    await tester.enterText(find.byType(TextField).first, newTitle);
    await tester.pump();
  }

  await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
  await tester.pump();
  return captured;
}

void main() {
  testWidgets('edit mode prefills from the task', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskEditorDialog.edit(task: _task(), onUpdate: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Write the report'), findsOneWidget);
    // The create-mode labels must not leak into edit mode.
    expect(find.text('Create task'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Create'), findsNothing);
  });

  testWidgets('saving an untouched form produces an empty patch',
      (tester) async {
    final request = await _pumpAndSave(tester);

    expect(request, isNotNull);
    // This is what stops the app firing a request the backend answers with 422,
    // and what lets the caller say "nothing changed" instead.
    expect(request!.isEmpty, isTrue);
  });

  testWidgets('only the changed field is sent', (tester) async {
    final request = await _pumpAndSave(tester, newTitle: 'Write the summary');

    expect(request, isNotNull);
    final json = request!.toJson();
    expect(json, {'title': 'Write the summary'});
    // Untouched values must be absent, not resent: a patch carrying every field
    // would overwrite anything changed elsewhere while this dialog was open.
    expect(json.containsKey('priority'), isFalse);
    expect(json.containsKey('estimated_duration'), isFalse);
    expect(json.containsKey('deadline'), isFalse);
  });
}
