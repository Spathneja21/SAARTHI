import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saarthi/core/api/dto/slot_dto.dart';
import 'package:saarthi/core/api/dto/task_dto.dart';
import 'package:saarthi/features/home/widgets/dashboard_page.dart';

/// Slots are built relative to `now` rather than to fixed wall-clock times:
/// the card under test picks between "happening now" and "up next" by
/// comparing against the real clock, so a hard-coded 9am slot would flip
/// meaning depending on when the suite happened to run.
ScheduledSlotDto _slot({
  required String taskId,
  required String title,
  required Duration startsIn,
  Duration length = const Duration(minutes: 45),
  TaskStatus status = TaskStatus.scheduled,
}) {
  final start = DateTime.now().add(startsIn);
  return ScheduledSlotDto(
    slotId: 'slot-$taskId',
    taskId: taskId,
    title: title,
    category: TaskCategory.deepWork,
    priority: 5,
    start: start,
    end: start.add(length),
    createdBy: 'ai',
    status: status,
    estimatedDuration: length.inMinutes,
  );
}

TaskDto _task(String id, {TaskStatus status = TaskStatus.scheduled}) {
  final now = DateTime.now();
  return TaskDto(
    id: id,
    title: 'Task $id',
    category: TaskCategory.deepWork,
    energyRequirement: EnergyLevel.medium,
    estimatedDuration: 45,
    priority: 5,
    status: status,
    procrastinationCount: 0,
    rescheduleCount: 0,
    skipCount: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required List<ScheduledSlotDto> slots,
  required List<TaskDto> tasks,
  int unplannedCount = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DashboardPage(
          todaySlots: slots,
          tasks: tasks,
          unplannedCount: unplannedCount,
        ),
      ),
    ),
  );
  // A single pump, not pumpAndSettle: the page runs a one-second repeating
  // ticker for the clock, so settling would never terminate.
  await tester.pump();
}

void main() {
  testWidgets('surfaces the soonest future session as "up next"',
      (tester) async {
    await _pumpDashboard(
      tester,
      slots: [
        _slot(taskId: 'b', title: 'Later thing', startsIn: const Duration(hours: 3)),
        _slot(taskId: 'a', title: 'Sooner thing', startsIn: const Duration(hours: 1)),
      ],
      tasks: [_task('a'), _task('b')],
    );

    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Sooner thing'), findsOneWidget);
    expect(find.text('Later thing'), findsNothing);
  });

  testWidgets('a session straddling now wins over a later one', (tester) async {
    await _pumpDashboard(
      tester,
      slots: [
        _slot(
          taskId: 'a',
          title: 'Running thing',
          startsIn: const Duration(minutes: -10),
        ),
        _slot(taskId: 'b', title: 'Later thing', startsIn: const Duration(hours: 2)),
      ],
      tasks: [_task('a'), _task('b')],
    );

    expect(find.text('HAPPENING NOW'), findsOneWidget);
    expect(find.text('Running thing'), findsOneWidget);
  });

  testWidgets('completed sessions are never offered as next', (tester) async {
    await _pumpDashboard(
      tester,
      slots: [
        _slot(taskId: 'a', title: 'Done thing', startsIn: const Duration(hours: 1)),
      ],
      tasks: [_task('a', status: TaskStatus.completed)],
    );

    expect(find.text('Done thing'), findsNothing);
    expect(find.text("Today's work is done"), findsOneWidget);
  });

  testWidgets('an unplanned day prompts planning rather than going blank',
      (tester) async {
    await _pumpDashboard(
      tester,
      slots: const [],
      tasks: const [],
      unplannedCount: 2,
    );

    expect(find.text('Nothing scheduled today'), findsOneWidget);
    expect(find.text('2 tasks are waiting for a time slot.'), findsOneWidget);
  });

  testWidgets('the unplanned count is stated once, not twice', (tester) async {
    await _pumpDashboard(
      tester,
      slots: [
        _slot(taskId: 'a', title: 'Upcoming', startsIn: const Duration(hours: 1)),
      ],
      tasks: [_task('a')],
      unplannedCount: 3,
    );

    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('3 tasks are waiting for a time slot.'), findsOneWidget);
  });
}
