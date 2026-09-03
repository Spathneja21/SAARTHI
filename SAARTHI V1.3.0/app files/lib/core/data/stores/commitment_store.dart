import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

import '../../api/api_client.dart';
import '../../api/dto/commitment_dto.dart';
import '../repositories/schedule_repository.dart';

/// The user's recurring fixed commitments — classes, shifts, standing meetings.
///
/// Replaces the local `ScheduleStore`, which kept weekly entries in
/// `SharedPreferences` where the scheduler could never see them. On the server
/// these are what CP-SAT treats as immovable, so together they define the gaps
/// tasks get placed into.
class CommitmentStore extends ChangeNotifier {
  CommitmentStore(this._repo);

  final ScheduleRepository _repo;

  List<FixedCommitmentDto> _commitments = const [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  List<FixedCommitmentDto> get commitments => _commitments;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;

  /// Onboarding requires at least one commitment before it will finish, so the
  /// scheduler has some shape of a week to work around.
  bool get hasAny => _commitments.isNotEmpty;

  /// Commitments that fall on a given day, in start order — what the timeline
  /// draws as fixed blocks.
  List<FixedCommitmentDto> forDate(DateTime date) {
    final list = _commitments.where((c) => c.occursOn(date)).toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return list;
  }

  /// Weekly commitments for one Dart weekday (1 = Monday … 7 = Sunday), for the
  /// weekly-setup editor.
  List<FixedCommitmentDto> weeklyForDartWeekday(int dartWeekday) {
    final backendWeekday = FixedCommitmentDto.fromDartWeekday(dartWeekday);
    final list = _commitments
        .where((c) =>
            c.recurrence == CommitmentRecurrence.weekly &&
            c.weekday == backendWeekday)
        .toList()
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    return list;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _commitments = await _repo.listCommitments();
      _hasLoaded = true;
    } catch (e) {
      _error = _describe(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a weekly commitment. Returns false and sets [error] on failure.
  Future<bool> addWeekly({
    required String title,
    required int dartWeekday,
    required TimeOfDay start,
    required TimeOfDay end,
  }) async {
    _error = null;
    try {
      final created = await _repo.createCommitment(
        FixedCommitmentCreateRequest.weekly(
          title: title,
          dartWeekday: dartWeekday,
          start: start,
          end: end,
        ),
      );
      _commitments = [..._commitments, created];
      notifyListeners();
      return true;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(String id) async {
    _error = null;
    try {
      await _repo.deleteCommitment(id);
      _commitments = _commitments.where((c) => c.id != id).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = _describe(e);
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _commitments = const [];
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
