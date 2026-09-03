import '../../api/api_client.dart';
import '../../api/backend_time.dart';
import '../../api/dto/commitment_dto.dart';
import '../../api/dto/slot_dto.dart';

/// The calendar side of the backend: fixed commitments, scheduled slots, and
/// the CP-SAT planner.
class ScheduleRepository {
  ScheduleRepository(this._api);

  final ApiClient _api;

  // ── Fixed commitments ──────────────────────────────────────────────────────

  Future<List<FixedCommitmentDto>> listCommitments() async {
    final data = await _api.get('/schedule/commitments') as List<dynamic>;
    return data
        .map((e) => FixedCommitmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FixedCommitmentDto> createCommitment(
    FixedCommitmentCreateRequest request,
  ) async {
    final data = await _api.post('/schedule/commitments', body: request.toJson())
        as Map<String, dynamic>;
    return FixedCommitmentDto.fromJson(data);
  }

  /// Soft-deletes the commitment. Deleting one that is already gone returns 404.
  Future<void> deleteCommitment(String id) =>
      _api.delete('/schedule/commitments/$id');

  // ── The day's schedule ─────────────────────────────────────────────────────

  /// Booked slots and free gaps for one day.
  ///
  /// [day] is interpreted as an IST calendar date; only the date part is sent.
  Future<DayScheduleDto> getDaySchedule(DateTime day) async {
    final date = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final data = await _api.get('/schedule/day', query: {'date': date})
        as Map<String, dynamic>;
    return DayScheduleDto.fromJson(data);
  }

  // ── Planning ───────────────────────────────────────────────────────────────

  /// Run the CP-SAT scheduler.
  ///
  /// With no [taskIds] it plans every pending task the user has (anything in
  /// draft, scheduled, postponed or partially-done). Existing AI-placed slots
  /// for the replanned tasks are superseded.
  ///
  /// The result carries no slot ids — call [getDaySchedule] afterwards if you
  /// need them, for instance to let the user drag a block.
  ///
  /// Always check `dropped` and surface it: those are tasks the solver could not
  /// fit, and letting them vanish silently is worse than saying so.
  Future<CpsatResultDto> planSchedule({List<String>? taskIds}) async {
    final data = await _api.post(
      '/schedule/cpsat',
      body: taskIds == null ? null : {'task_ids': taskIds},
    ) as Map<String, dynamic>;
    return CpsatResultDto.fromJson(data);
  }

  /// Book a specific slot by hand. Throws [ApiException] with 409 on an overlap.
  Future<String> bookSlot({
    required String taskId,
    required DateTime start,
    required DateTime end,
  }) async {
    final data = await _api.post('/schedule/book', body: {
      'task_id': taskId,
      'slot_start': formatBackendTime(start),
      'slot_end': formatBackendTime(end),
    }) as Map<String, dynamic>;
    return data['slot_id'] as String;
  }

  /// Record that the user moved a slot, and update it.
  ///
  /// This is also a reinforcement-learning signal: the backend stores the
  /// suggested time alongside the chosen one, and a nightly job turns the
  /// eventual outcome into a reward that biases future slot scoring. So moving a
  /// block is not just an edit — it is how the scheduler learns this user's
  /// preferences.
  Future<void> moveSlot({
    required String slotId,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    await _api.post('/schedule/preference/move', body: {
      'slot_id': slotId,
      'new_start': formatBackendTime(newStart),
      'new_end': formatBackendTime(newEnd),
    });
  }

  /// Wipe every scheduled slot for the user. Tasks themselves are untouched.
  Future<int> clearAllSlots() async {
    final data = await _api.delete('/schedule/slots') as Map<String, dynamic>?;
    return (data?['deleted'] as int?) ?? 0;
  }
}
