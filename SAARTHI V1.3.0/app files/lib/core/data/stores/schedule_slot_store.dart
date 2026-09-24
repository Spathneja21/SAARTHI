import 'dart:async';

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
  ScheduleSlotStore(
    this._repo, {
    Duration retryDelay = const Duration(seconds: 8),
  }) : _retryDelay = retryDelay;

  final ScheduleRepository _repo;

  /// How long a day that failed to load waits before it may be asked for again.
  ///
  /// Injectable so a test does not have to sit through it.
  final Duration _retryDelay;

  bool _disposed = false;

  DateTime? _loadedDate;

  /// Day schedules already fetched, keyed `yyyy-mm-dd`.
  ///
  /// The timeline now scrolls continuously across days, so it renders several
  /// dates at once and re-asks as the user moves. Holding only a single
  /// "current" day would leave every neighbouring column blank and refetch the
  /// same dates on each change of direction.
  final Map<String, DayScheduleDto> _cache = {};

  /// Dates already asked for: cached, in flight, or cooling off after a
  /// failure.
  ///
  /// The timeline requests any day it draws without data on every build, so
  /// this gate is what stops a failing date being re-asked once per frame. A
  /// failure re-opens it after [_retryDelay] rather than leaving it shut — see
  /// [ensureDay].
  final Set<String> _attempted = {};

  /// Bumped on invalidation, so a response already in flight cannot repopulate
  /// a cache that was cleared while it was travelling.
  int _generation = 0;

  bool _isLoading = false;
  bool _isPlanning = false;
  String? _error;

  /// The most recent plan run, so the UI can report what the solver did —
  /// including anything it could not fit.
  CpsatResultDto? _lastPlan;

  /// The focused day — whatever the dashboard and the day-scoped actions are
  /// talking about. Derived from the cache rather than stored separately, so
  /// there is only ever one copy of a day's schedule in memory.
  DayScheduleDto? get day =>
      _loadedDate == null ? null : _cache[_key(_loadedDate!)];
  List<ScheduledSlotDto> get slots => day?.bookedSlots ?? const [];
  List<FreeGapDto> get freeGaps => day?.freeGaps ?? const [];
  int get totalBookedMinutes => day?.totalBookedMinutes ?? 0;
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

  /// Slots for any day the cache holds.
  ///
  /// Returns empty both for a day with nothing on it and for one not fetched
  /// yet; [isDayLoaded] is what separates the two.
  List<ScheduledSlotDto> slotsOn(DateTime date) =>
      _cache[_key(date)]?.bookedSlots ?? const [];

  bool isDayLoaded(DateTime date) => _cache.containsKey(_key(date));

  /// Fetch [date] unless it is already cached or already in flight.
  ///
  /// Safe to call on every build: the `_attempted` gate makes repeat calls for
  /// the same date free, which is what lets the timeline ask for whatever it is
  /// currently drawing without tracking requests itself.
  Future<void> ensureDay(DateTime date) async {
    final key = _key(date);
    if (_attempted.contains(key)) return;
    _attempted.add(key);
    final generation = _generation;
    try {
      final fetched = await _repo.getDaySchedule(date);
      if (generation != _generation) return;
      _cache[key] = fetched;
      notifyListeners();
    } catch (e) {
      if (generation != _generation) return;
      _error = _describe(e);
      // Re-open the gate, but on a delay.
      //
      // Leaving it shut — which is what this did originally — meant a day that
      // failed once was never asked for again: it stayed empty for the rest of
      // the session, and because a failed day and a day with nothing on it both
      // render as an empty column, nothing said so. Clearing it immediately is
      // the opposite failure, since the timeline would then re-ask on every
      // frame for as long as the backend stayed down.
      Timer(_retryDelay, () {
        if (_disposed || generation != _generation) return;
        _attempted.remove(key);
        // Nothing else would prompt the timeline to ask again.
        notifyListeners();
      });
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Point the day-scoped getters at [date] without forcing a refetch.
  ///
  /// This is what scrolling uses. Crossing midnight is now an ordinary gesture
  /// rather than a deliberate act, so routing it through [loadDay] would fire a
  /// request at every boundary even for days already in the cache.
  void focusDay(DateTime date) {
    if (_loadedDate != null && _key(_loadedDate!) == _key(date)) return;
    _loadedDate = date;
    notifyListeners();
    ensureDay(date);
  }

  Future<void> loadDay(DateTime date) async {
    _isLoading = true;
    _error = null;
    _loadedDate = date;
    notifyListeners();
    final key = _key(date);
    _attempted.add(key);
    final generation = _generation;
    try {
      final fetched = await _repo.getDaySchedule(date);
      // No same-date guard needed any more: each response writes its own key,
      // so an answer that arrives after the user has moved on lands in the day
      // it belongs to instead of overwriting the visible one.
      if (generation != _generation) return;
      _cache[key] = fetched;
    } catch (e) {
      if (generation != _generation) return;
      _error = _describe(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Drop every fetched day so the next render re-asks.
  ///
  /// Planning and clearing move sessions *between* days, so invalidating only
  /// the focused date would leave the columns either side of it showing a
  /// schedule the server no longer has.
  void _invalidate() {
    _generation++;
    _cache.clear();
    _attempted.clear();
  }

  Future<void> refresh() async {
    _invalidate();
    final date = _loadedDate;
    if (date != null) {
      await loadDay(date);
    } else {
      notifyListeners();
    }
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
    _invalidate();
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

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
