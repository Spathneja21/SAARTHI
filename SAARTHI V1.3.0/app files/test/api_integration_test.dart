/// Drives the real AURA backend through the Dart API layer.
///
/// Not a unit test with mocks — it makes genuine HTTP calls, so it verifies the
/// things mocks cannot: that DTO field names match the server's wire format,
/// that IST timestamps round-trip, that error bodies decode into useful
/// messages, and that status codes mean what the client assumes.
///
/// Requires:
///   * the backend running on localhost:8000  (docker compose up -d)
///   * a Firebase ID token in /tmp/e2e_token.txt
///       docker compose exec -T api python scripts/mint_test_token.py `<WEB_API_KEY>` `<uid>` `<email>`
///
/// Skips itself with a clear message if either is missing, so `flutter test`
/// stays green on a machine with no backend.
library;

import 'dart:io';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:saarthi/core/api/api_client.dart';
import 'package:saarthi/core/api/backend_time.dart';
import 'package:saarthi/core/api/dto/commitment_dto.dart';
import 'package:saarthi/core/api/dto/task_dto.dart';
import 'package:saarthi/core/data/repositories/schedule_repository.dart';
import 'package:saarthi/core/data/repositories/task_repository.dart';

const String kBaseUrl = 'http://localhost:8000';
const String kTokenPath = '/tmp/e2e_token.txt';

void main() {
  final tokenFile = File(kTokenPath);
  if (!tokenFile.existsSync()) {
    test('backend integration (skipped)', () {
      markTestSkipped('No token at $kTokenPath — see the file header.');
    });
    return;
  }
  final token = tokenFile.readAsStringSync().trim();

  late ApiClient api;
  late TaskRepository tasks;
  late ScheduleRepository schedule;

  setUpAll(() {
    api = ApiClient.withTokenProvider(() async => token, baseUrl: kBaseUrl);
    tasks = TaskRepository(api);
    schedule = ScheduleRepository(api);
  });

  tearDownAll(() => api.dispose());

  group('time conversion', () {
    test('IST timestamps parse to IST wall-clock, not device-local', () {
      // 15:50 IST is 10:20 UTC. Whatever timezone this machine is in, the
      // fields must read 15:50 — that is what the scheduler meant and what the
      // timeline has to draw.
      final parsed = parseBackendTime('2026-09-03T15:50:00+05:30');
      expect(parsed.hour, 15);
      expect(parsed.minute, 50);
    });

    test('a UTC-expressed instant still renders as IST', () {
      final parsed = parseBackendTime('2026-09-03T10:20:00Z');
      expect(parsed.hour, 15);
      expect(parsed.minute, 50);
    });

    test('outgoing timestamps carry an explicit +05:30 offset', () {
      final s = formatBackendTime(DateTime(2026, 9, 8, 18, 0));
      expect(s, '2026-09-08T18:00:00+05:30');
      // A bare toIso8601String() would emit no offset, and FastAPI would then
      // build a naive datetime and compare it against aware ones.
      expect(s.endsWith('+05:30'), isTrue);
    });
  });

  group('auth', () {
    test('a bad token surfaces as unauthorized', () async {
      final bad = ApiClient.withTokenProvider(
        () async => 'not-a-real-token',
        baseUrl: kBaseUrl,
      );
      await expectLater(
        bad.get('/tasks'),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)),
      );
      bad.dispose();
    });

    test('an unreachable backend is distinguishable from an auth failure', () async {
      final dead = ApiClient.withTokenProvider(
        () async => token,
        baseUrl: 'http://localhost:59999',
      );
      await expectLater(dead.get('/tasks'), throwsA(isA<ApiUnreachableException>()));
      dead.dispose();
    });
  });

  group('task lifecycle', () {
    test('create, read, update, delete', () async {
      final created = await tasks.createTask(TaskCreateRequest(
        title: 'Dart integration task',
        category: TaskCategory.learning,
        energyRequirement: EnergyLevel.high,
        estimatedDuration: 75,
        priority: 6,
        deadline: DateTime(2026, 9, 20, 17, 0),
        description: 'created from a Flutter test',
      ));

      expect(created.id, isNotEmpty);
      expect(created.title, 'Dart integration task');
      expect(created.category, TaskCategory.learning);
      expect(created.energyRequirement, EnergyLevel.high);
      expect(created.estimatedDuration, 75);
      expect(created.priority, 6);
      expect(created.description, 'created from a Flutter test');
      // Every task starts as a draft server-side, regardless of what is sent.
      expect(created.status, TaskStatus.draft);
      expect(created.actualDuration, isNull);
      expect(created.deadline?.hour, 17);

      final fetched = await tasks.getTask(created.id);
      expect(fetched.id, created.id);

      final updated = await tasks.updateTask(
        created.id,
        const TaskUpdateRequest(priority: 9, title: 'Renamed'),
      );
      expect(updated.priority, 9);
      expect(updated.title, 'Renamed');
      // An omitted field must be left alone, not nulled.
      expect(updated.estimatedDuration, 75);
      expect(updated.description, 'created from a Flutter test');

      await tasks.deleteTask(created.id);
      await expectLater(
        tasks.getTask(created.id),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true)),
      );
    });

    test('validation errors arrive as readable messages', () async {
      await expectLater(
        tasks.createTask(TaskCreateRequest(
          title: '',
          category: TaskCategory.admin,
          energyRequirement: EnergyLevel.low,
          estimatedDuration: 30,
        )),
        throwsA(isA<ApiException>()
            .having((e) => e.isValidationError, 'isValidationError', true)
            // FastAPI's nested detail list must be flattened, not shown raw.
            .having((e) => e.message, 'message', contains('title'))),
      );
    });

    test('completing without starting leaves the duration unmeasured', () async {
      final t = await tasks.createTask(TaskCreateRequest(
        title: 'Tapped done',
        category: TaskCategory.admin,
        energyRequirement: EnergyLevel.low,
        estimatedDuration: 25,
      ));
      final done = await tasks.completeTask(t.id);

      expect(done.status, TaskStatus.completed);
      // Null, never 0: a single tap cannot know how long the work took, and a
      // fabricated zero would corrupt the behaviour profile's estimation error.
      expect(done.actualDuration, isNull);

      // Terminal, so the UI must not offer un-completing.
      expect(done.status.isTerminal, isTrue);
      // ...and it is idempotent, which matters for a retrying mobile client.
      final again = await tasks.completeTask(t.id);
      expect(again.status, TaskStatus.completed);

      await tasks.deleteTask(t.id);
    });

    test('starting a task is what makes a real duration possible', () async {
      final t = await tasks.createTask(TaskCreateRequest(
        title: 'Actually started',
        category: TaskCategory.deepWork,
        energyRequirement: EnergyLevel.peak,
        estimatedDuration: 50,
      ));

      final started = await tasks.startTask(t.id, currentStatus: t.status);
      expect(started.status, TaskStatus.inProgress);
      expect(started.startedAt, isNotNull);

      final done = await tasks.completeTask(t.id);
      expect(done.actualDuration, isNotNull);
      expect(done.actualDuration, greaterThanOrEqualTo(0),
          reason: 'a duration derived from a real start must never be negative');

      await tasks.deleteTask(t.id);
    });

    test('skip bumps both counters server-side', () async {
      final t = await tasks.createTask(TaskCreateRequest(
        title: 'Skipped',
        category: TaskCategory.personal,
        energyRequirement: EnergyLevel.medium,
        estimatedDuration: 20,
      ));
      final skipped = await tasks.skipTask(t.id);
      expect(skipped.status, TaskStatus.skipped);
      expect(skipped.skipCount, 1);
      expect(skipped.procrastinationCount, 1);
      await tasks.deleteTask(t.id);
    });

    test('an illegal transition is rejected rather than silently applied', () async {
      final t = await tasks.createTask(TaskCreateRequest(
        title: 'Illegal jump',
        category: TaskCategory.admin,
        energyRequirement: EnergyLevel.low,
        estimatedDuration: 15,
      ));
      // draft -> completed is not in VALID_TRANSITIONS.
      await expectLater(
        tasks.transition(t.id, TaskStatus.completed),
        throwsA(isA<ApiException>().having((e) => e.isValidationError, 'is422', true)),
      );
      await tasks.deleteTask(t.id);
    });
  });

  group('commitments and planning', () {
    test('weekday conversion between Dart 1-7 and backend 0-6', () {
      expect(FixedCommitmentDto.fromDartWeekday(DateTime.monday), 0);
      expect(FixedCommitmentDto.fromDartWeekday(DateTime.sunday), 6);
      expect(FixedCommitmentDto.toDartWeekday(0), DateTime.monday);
      expect(FixedCommitmentDto.toDartWeekday(6), DateTime.sunday);
    });

    test('create a weekly commitment and see it block time', () async {
      final created = await schedule.createCommitment(
        FixedCommitmentCreateRequest.weekly(
          title: 'Dart test lecture',
          dartWeekday: DateTime.wednesday,
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 11, minute: 30),
        ),
      );

      expect(created.recurrence, CommitmentRecurrence.weekly);
      expect(created.weekday, 2, reason: 'Wednesday is 2 in the backend 0-6 scheme');
      expect(created.startMinute, 540);
      expect(created.endMinute, 690);
      expect(created.durationMinutes, 150);
      expect(created.startTime.hour, 9);

      // occursOn must agree with the weekday it was created for.
      final aWednesday = DateTime(2026, 9, 9);
      expect(aWednesday.weekday, DateTime.wednesday);
      expect(created.occursOn(aWednesday), isTrue);
      expect(created.occursOn(aWednesday.add(const Duration(days: 1))), isFalse);

      final all = await schedule.listCommitments();
      expect(all.map((c) => c.id), contains(created.id));

      await schedule.deleteCommitment(created.id);
      final after = await schedule.listCommitments();
      expect(after.map((c) => c.id), isNot(contains(created.id)));

      // Already gone -> 404, so a UI cannot show success for a no-op.
      await expectLater(
        schedule.deleteCommitment(created.id),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true)),
      );
    });

    test('planning places tasks and the day schedule reflects it', () async {
      final t = await tasks.createTask(TaskCreateRequest(
        title: 'Plan me',
        category: TaskCategory.deepWork,
        energyRequirement: EnergyLevel.high,
        estimatedDuration: 60,
        priority: 8,
        deadline: DateTime.now().add(const Duration(days: 3)),
      ));

      final result = await schedule.planSchedule(taskIds: [t.id]);
      expect(result.solved, isTrue, reason: 'status was ${result.solveStatus}');
      expect(result.scheduled, isNotEmpty);
      expect(result.dropped, isEmpty);

      final a = result.scheduled.first;
      expect(a.taskId, t.id);
      expect(a.end.isAfter(a.start), isTrue);
      expect(a.behavioralScore, inInclusiveRange(0, 100));
      expect(a.completionProbability, inInclusiveRange(0, 1));
      expect(a.procrastinationRisk, inInclusiveRange(0, 1));

      // The solver's response carries no slot ids, so a re-fetch is how the UI
      // gets something it can later move.
      final day = await schedule.getDaySchedule(a.start);
      final mine = day.bookedSlots.where((s) => s.taskId == t.id);
      expect(mine, isNotEmpty, reason: 'the planned slot should appear on its day');
      expect(mine.first.slotId, isNotEmpty);
      expect(mine.first.durationMinutes, greaterThan(0));
      expect(mine.first.isAiPlaced, isTrue);

      await tasks.deleteTask(t.id);
    });

    test('a long task is split into multiple sessions sharing a task id', () async {
      final t = await tasks.createTask(TaskCreateRequest(
        title: 'Long haul',
        category: TaskCategory.deepWork,
        energyRequirement: EnergyLevel.high,
        // Comfortably above the 90-minute focus limit, so the chunker splits it.
        estimatedDuration: 240,
        priority: 7,
        deadline: DateTime.now().add(const Duration(days: 5)),
      ));

      final result = await schedule.planSchedule(taskIds: [t.id]);
      expect(result.solved, isTrue);
      expect(result.scheduled.length, greaterThan(1),
          reason: 'a 240-minute task must not be one unbroken block');
      expect(result.scheduled.map((a) => a.taskId).toSet(), {t.id});
      expect(result.scheduled.map((a) => a.chunkIndex).toSet().length,
          result.scheduled.length,
          reason: 'chunk indices should be distinct');

      await tasks.deleteTask(t.id);
    });
  });
}
