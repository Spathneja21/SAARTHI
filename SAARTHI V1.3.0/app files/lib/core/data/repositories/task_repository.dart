import '../../api/api_client.dart';
import '../../api/dto/task_dto.dart';

/// Everything the app does with tasks, over the AURA backend.
///
/// The server is the source of truth: no local mutation happens here, and every
/// method returns the server's view of the task after the change. Callers should
/// replace their local copy with what comes back rather than assuming what the
/// change did — counters such as `procrastinationCount` are computed server-side.
class TaskRepository {
  TaskRepository(this._api);

  final ApiClient _api;

  Future<List<TaskDto>> listTasks() async {
    final data = await _api.get('/tasks') as List<dynamic>;
    return data
        .map((e) => TaskDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TaskDto> getTask(String id) async {
    final data = await _api.get('/tasks/$id') as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  Future<TaskDto> createTask(TaskCreateRequest request) async {
    final data =
        await _api.post('/tasks', body: request.toJson()) as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  Future<TaskDto> updateTask(String id, TaskUpdateRequest request) async {
    if (request.isEmpty) {
      // The backend answers 422 for an empty patch; failing here avoids a
      // pointless round trip and gives a clearer message.
      throw ApiException(422, 'No fields to update.');
    }
    final data = await _api.patch('/tasks/$id', body: request.toJson())
        as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  Future<void> deleteTask(String id) => _api.delete('/tasks/$id');

  /// Mark a task done.
  ///
  /// Goes through the dedicated endpoint rather than a status transition,
  /// because the state machine forbids `draft -> completed` and the server walks
  /// the intermediate steps itself. It also decides whether a real duration can
  /// be recorded: a task that was never actually started keeps a null
  /// `actualDuration` instead of a fabricated zero.
  ///
  /// Idempotent — completing an already-completed task returns it unchanged.
  Future<TaskDto> completeTask(String id) async {
    final data = await _api.post('/tasks/$id/complete') as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  /// Push a task out. Increments `procrastinationCount` server-side.
  Future<TaskDto> postponeTask(String id) async {
    final data = await _api.post('/tasks/$id/postpone') as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  /// Skip a task. Increments both `skipCount` and `procrastinationCount`.
  Future<TaskDto> skipTask(String id) async {
    final data = await _api.post('/tasks/$id/skip') as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  /// Move a task to an explicit status.
  ///
  /// Low-level: the server rejects illegal transitions with 422. Prefer
  /// [completeTask], [postponeTask] and [skipTask]. The one case that needs
  /// this is starting work — see [startTask].
  Future<TaskDto> transition(String id, TaskStatus to, {String? reason}) async {
    final data = await _api.patch(
      '/tasks/$id/transition',
      body: {'to_status': to.wire, 'reason': ?reason},
    ) as Map<String, dynamic>;
    return TaskDto.fromJson(data);
  }

  /// Begin working on a task, moving it to `in_progress`.
  ///
  /// This is the *only* way the system ever learns how long a task really took.
  /// `started_at` is stamped on entering `in_progress`, and `actualDuration` is
  /// derived from it on completion; without a start there is nothing to measure,
  /// so `avg_estimation_error_minutes` in the behaviour profile stays empty.
  ///
  /// A `draft` task cannot go straight to `in_progress`, so schedule it first.
  Future<TaskDto> startTask(String id, {TaskStatus? currentStatus}) async {
    if (currentStatus == TaskStatus.draft) {
      await transition(id, TaskStatus.scheduled);
    }
    return transition(id, TaskStatus.inProgress);
  }

  Future<List<Map<String, dynamic>>> getHistory(String id) async {
    final data = await _api.get('/tasks/$id/history') as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }
}
