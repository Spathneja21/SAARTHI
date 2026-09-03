import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/dto/slot_dto.dart';
import '../../../core/api/dto/task_dto.dart';
// Flip-clock style is on hold for revisiting later; see FlipClock widget.
// import '../../../shared/widgets/flip_clock.dart';

/// The home/overview page shown alongside the Timeline: a live clock as the
/// hero element, plus a quick read on today's work.
///
/// The counters now come from **scheduled slots**, not from a local task list
/// filtered by date. Tasks no longer carry a day — the scheduler decides that —
/// so "what is on today" is a question only the day's slots can answer.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.todaySlots,
    required this.tasks,
    required this.unplannedCount,
    this.isLoading = false,
  });

  /// Sessions placed on today. Empty when the timeline is showing another day,
  /// so the numbers never quietly describe a day the user only browsed to.
  final List<ScheduledSlotDto> todaySlots;

  /// Every task, used to resolve the status behind each slot.
  final List<TaskDto> tasks;

  final int unplannedCount;
  final bool isLoading;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late DateTime _now;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Count distinct tasks, not slots: a long task split into three sessions is
    // still one thing to do, and reporting "3 tasks today" for it would be
    // misleading.
    final taskIdsToday = widget.todaySlots.map((s) => s.taskId).toSet();
    final total = taskIdsToday.length;

    final statusById = {for (final t in widget.tasks) t.id: t.status};
    final completed = taskIdsToday
        .where((id) => statusById[id] == TaskStatus.completed)
        .length;

    final minutesPlanned = widget.todaySlots
        .fold<int>(0, (sum, s) => sum + s.durationMinutes);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          Text(
            DateFormat('EEEE, MMMM d').format(_now),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          // Flip-clock style is on hold for revisiting later; reverted to a
          // plain live digital clock in the meantime.
          // FlipClock(
          //   hourText: DateFormat('hh').format(_now),
          //   minuteText: DateFormat('mm').format(_now),
          //   periodText: DateFormat('a').format(_now).toUpperCase(),
          // ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: DateFormat('h:mm').format(_now),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -1.5,
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: ' ${DateFormat('a').format(_now)}',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Tasks today',
                  value: '$total',
                  icon: Icons.checklist_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _StatCard(
                  label: 'Completed',
                  value: '$completed',
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _StatCard(
                  label: minutesPlanned == 0 ? 'Planned' : 'Planned time',
                  value: _durationLabel(minutesPlanned),
                  icon: Icons.timelapse_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProgressCard(total: total, completed: completed),
          if (widget.unplannedCount > 0) ...[
            const SizedBox(height: 14),
            _UnplannedHint(count: widget.unplannedCount),
          ],
        ],
      ),
    );
  }
}

String _durationLabel(int minutes) {
  if (minutes == 0) return '—';
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h${m}m';
}

/// Nudge toward planning, shown only when tasks are sitting without a slot.
///
/// Necessary because the user no longer picks a day for a task: without this
/// the dashboard would read "0 tasks today" while several tasks waited
/// invisibly to be placed.
class _UnplannedHint extends StatelessWidget {
  const _UnplannedHint({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 task is waiting for a time slot.'
                      : '$count tasks are waiting for a time slot.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 26),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total == 0 ? 0.0 : completed / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Today's progress", style: theme.textTheme.titleMedium),
                  Text(
                    total == 0 ? '—' : '${(fraction * 100).round()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : fraction,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
