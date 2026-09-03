import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';
import '../../api/dto/slot_dto.dart';
import '../repositories/schedule_repository.dart';

/// The scheduled blocks for whichever day the timeline is showing, plus the
/// "Plan my day" action.
///
/// This is what replaces the app's old idea that a task carries the day it
/// belongs to. The day now comes from the server's `scheduled_slots`, so the
/// timeline asks this store what to draw for a date rather than filtering a
/// local task list.
class ScheduleSlotStore extends ChangeNotifier {
  ScheduleSlotStore(this._repo);

  final ScheduleRepository _repo;

  DateTime? _loadedDate;
  DayScheduleDto? _day;
  bool _isLoading = false;
  bool _isPlanning = false;
  String? _error;

  /// The most recent plan run, so the UI can report what the solver did —
  /// including anything it could not fit.
  CpsatResultDto? _lastPlan;

  DayScheduleDto? get day => _day;
  List<ScheduledSlotDto> get slots => _day?.bookedSlots ?? const [];
  List<FreeGapDto> get freeGaps => _day?.freeGaps ?? const [];
  int get totalBookedMinutes => _day?.totalBookedMinutes ?? 0;
  bool get isLoading => _isLoading;
  bool get isPlanning => _isPlanning;
  String? get error => _error;
  CpsatResultDto? get lastPlan => _lastPlan;
  DateTime? get loadedDate => _loadedDate;

  /// Slots for one task, in start order.
  ///
  /// A long task is split by CP-SAT into several sessions that share a
  /// `taskId`, so this can legitimately return more than one.
  List<ScheduledSlotDto> slotsForTask(String taskId) {
    final list = slots.where((s) => s.taskId == taskId).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  Future<void> loadDay(DateTime date) async {
    _isLoading = true;
    _error = null;
    _loadedDate = date;
    notifyListeners();
    try {
      final fetched = await _repo.getDaySchedule(date);
      // Guard against an out-of-order response: if the user swiped to another
      // day while this was in flight, the stale answer must not overwrite it.
      if (!_isSameDate(_loadedDate, date)) return;
      _day = fetched;
    } catch (e) {
      _error = _describe(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final date = _loadedDate;
    if (date != null) await loadDay(date);
  }

  /// Run the CP-SAT scheduler over every pending task, then reload the day.
  ///
  /// The reload is not optional: the solver's response carries no slot ids, so
  /// the timeline needs a fresh `GET /schedule/day` before a block can be moved.
  ///
  /// Returns the plan result so the caller can surface `dropped` — tasks the
  /// solver could not fit must be reported rather than silently missing.
  Future<CpsatResultDto?> planDay() async {
    _isPlanning = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repo.planSchedule();
      _lastPlan = result;
      if (!result.solved && !result.hadNothingToDo) {
        _error = 'The scheduler could not fit these tasks '
            '(${result.solveStatus.toLowerCase()}).';
      }
      return result;
    } catch (e) {
      _error = _describe(e);
      return null;
    } finally {
      _isPlanning = false;
      notifyListeners();
      await refresh();
    }
  }

  /// Move a block, which also records a preference signal the scheduler learns
  /// from over time.
  Future<bool> moveSlot({
    required String slotId,
    required DateTime newStart,
    required DateTime newEnd,
  }) async {
    _error = null;
    try {
      await _repo.moveSlot(slotId: slotId, newStart: newStart, newEnd: newEnd);
      await refresh();
      return true;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return false;
    }
  }

  Future<int> clearAll() async {
    _error = null;
    try {
      final n = await _repo.clearAllSlots();
      await refresh();
      return n;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return 0;
    }
  }

  void clear() {
    _day = null;
    _loadedDate = null;
    _lastPlan = null;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  static bool _isSameDate(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  static String _describe(Object e) {
    if (e is ApiUnreachableException) {
      return 'Cannot reach the server. Is the backend running?';
    }
    if (e is ApiException) {
      if (e.isServerMisconfigured) {
        return 'The server is not fully configured yet.';
      }
      if (e.isUnauthorized) return 'Your session expired. Please sign in again.';
      return e.message;
    }
    return 'Something went wrong: $e';
  }
}
