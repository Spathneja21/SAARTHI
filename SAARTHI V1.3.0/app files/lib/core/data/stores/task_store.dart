import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';
import '../../api/dto/task_dto.dart';
import '../repositories/task_repository.dart';

/// The user's tasks, mirroring the server.
///
/// Replaces the old `DailyTaskStore`, which kept tasks in `SharedPreferences`
/// keyed by nothing but the device. Two consequences of the move are worth
/// knowing:
///
///   * There is no local `date` field any more. A task's day is decided by the
///     scheduler and read from `scheduled_slots`, so "which tasks are on
///     Tuesday" is a question for [ScheduleSlotStore], not this one.
///   * Mutations are `Future`s that await the server and adopt its response,
///     rather than synchronous list edits. Counters like
///     `procrastinationCount` are computed server-side, so guessing locally
///     would drift.
class TaskStore extends ChangeNotifier {
  TaskStore(this._repo);

  final TaskRepository _repo;

  List<TaskDto> _tasks = const [];
  bool _isLoading = false;
  String? _error;

  List<TaskDto> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  bool _hasLoaded = false;

  /// Tasks the scheduler has not placed yet.
  ///
  /// These need somewhere to live in the UI: a task exists the moment it is
  /// created but has no slot until "Plan my day" runs, and since the user no
  /// longer picks a day, it would otherwise be invisible.
  List<TaskDto> get unplanned => _tasks
      .where((t) => t.status == TaskStatus.draft || t.status == TaskStatus.postponed)
      .toList();

  List<TaskDto> get active =>
      _tasks.where((t) => !t.status.isResolved).toList();

  List<TaskDto> get completed =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();

  TaskDto? byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _tasks = await _repo.listTasks();
      _hasLoaded = true;
    } catch (e) {
      _error = _describe(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a task. Returns it on success, or null when the call failed —
  /// in which case [error] holds a message worth showing.
  Future<TaskDto?> create(TaskCreateRequest request) async {
    _error = null;
    try {
      final created = await _repo.createTask(request);
      _tasks = [created, ..._tasks];
      notifyListeners();
      return created;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return null;
    }
  }

  /// Mark a task done.
  ///
  /// Note that `actualDuration` comes back null unless the task was actually
  /// started — see [start]. That is intentional on the server's part, not a bug
  /// to work around here.
  Future<bool> complete(String id) => _mutate(() => _repo.completeTask(id));

  /// Begin working on a task.
  ///
  /// This is the only path that produces a real `actualDuration`, because
  /// `startedAt` is stamped on entering `in_progress` and the duration is
  /// derived from it at completion. Without it the behaviour profile's
  /// estimation-accuracy figures stay permanently empty, which is why the UI
  /// offers "Start" and not only "Done".
  Future<bool> start(String id) {
    final current = byId(id);
    return _mutate(() => _repo.startTask(id, currentStatus: current?.status));
  }

  Future<bool> skip(String id) => _mutate(() => _repo.skipTask(id));

  Future<bool> postpone(String id) => _mutate(() => _repo.postponeTask(id));

  Future<bool> update(String id, TaskUpdateRequest request) =>
      _mutate(() => _repo.updateTask(id, request));

  Future<bool> delete(String id) async {
    _error = null;
    try {
      await _repo.deleteTask(id);
      _tasks = _tasks.where((t) => t.id != id).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return false;
    }
  }

  /// Run a repository call that returns the task's new server state, then swap
  /// the local copy for it.
  Future<bool> _mutate(Future<TaskDto> Function() action) async {
    _error = null;
    try {
      final updated = await action();
      _tasks = _tasks.map((t) => t.id == updated.id ? updated : t).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return false;
    }
  }

  /// Clear cached tasks — called on sign-out.
  ///
  /// Necessary because the previous local-storage keys were not namespaced by
  /// user, so signing in as someone else on the same device showed the previous
  /// person's data.
  void clear() {
    _tasks = const [];
    _hasLoaded = false;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

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
