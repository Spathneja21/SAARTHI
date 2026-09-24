import 'package:flutter_test/flutter_test.dart';

import 'package:saarthi/core/api/api_client.dart';
import 'package:saarthi/core/api/dto/slot_dto.dart';
import 'package:saarthi/core/data/repositories/schedule_repository.dart';
import 'package:saarthi/core/data/stores/schedule_slot_store.dart';

/// Throws for the first [failures] calls, then answers normally.
///
/// Subclasses the real repository rather than mocking an interface, and gets
/// its `ApiClient` from `withTokenProvider` — the constructor that exists so a
/// plain `flutter test` never has to boot Firebase.
class _FlakyRepository extends ScheduleRepository {
  _FlakyRepository({required this.failures})
      : super(ApiClient.withTokenProvider(() async => null));

  int failures;
  int calls = 0;

  @override
  Future<DayScheduleDto> getDaySchedule(DateTime day) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw Exception('backend down');
    }
    return const DayScheduleDto(
      date: '2026-09-07',
      bookedSlots: [],
      freeGaps: [],
      totalBookedMinutes: 0,
    );
  }
}

void main() {
  final date = DateTime(2026, 9, 7);

  test('a day that fails to load is retried, not abandoned', () async {
    final repo = _FlakyRepository(failures: 1);
    final store = ScheduleSlotStore(
      repo,
      retryDelay: const Duration(milliseconds: 10),
    );

    await store.ensureDay(date);
    expect(repo.calls, 1);
    expect(store.isDayLoaded(date), isFalse,
        reason: 'the first attempt failed, so nothing should be cached');

    // Immediately afterwards the gate is still shut, so a timeline rebuilding
    // every frame cannot turn a down backend into a request per frame.
    await store.ensureDay(date);
    expect(repo.calls, 1, reason: 'must not re-ask before the backoff elapses');

    await Future<void>.delayed(const Duration(milliseconds: 40));

    // Once the backoff has passed the day is askable again. This is the
    // regression: it used to stay shut forever, leaving the column blank and
    // indistinguishable from a day with nothing scheduled.
    await store.ensureDay(date);
    expect(repo.calls, 2);
    expect(store.isDayLoaded(date), isTrue);
  });

  test('a successful day is never re-fetched', () async {
    final repo = _FlakyRepository(failures: 0);
    final store = ScheduleSlotStore(
      repo,
      retryDelay: const Duration(milliseconds: 10),
    );

    await store.ensureDay(date);
    await store.ensureDay(date);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await store.ensureDay(date);

    expect(repo.calls, 1);
    expect(store.isDayLoaded(date), isTrue);
  });
}
