import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/dto/commitment_dto.dart';
import '../../../core/api/dto/slot_dto.dart';
import '../../../core/api/dto/task_dto.dart' show TaskStatus;
import '../../../core/utils/time_utils.dart';
import '../../../shared/theme/category_palette.dart';

/// The day, drawn as a 24-hour column.
///
/// Three layers sit on the hour grid:
///
///   1. **Fixed commitments** — solid blue blocks. Immovable; the scheduler
///      works around them.
///   2. **Scheduled task sessions** — surface cards with a category accent.
///      These are what CP-SAT placed, and they are the reason this view now
///      shows real blocks: tasks used to be drawn as zero-height markers at
///      their deadline, so duration and placement were invisible.
///   3. **The now line**, when viewing today.
///
/// A single task can own several blocks. CP-SAT splits anything longer than its
/// focus limit into multiple sessions sharing a `taskId`, which is why blocks
/// are keyed by `slotId` and labelled "session n of m".
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.selectedDate,
    required this.commitments,
    required this.slots,
    required this.onSlotTap,
  });

  final DateTime selectedDate;
  final List<FixedCommitmentDto> commitments;
  final List<ScheduledSlotDto> slots;

  /// Opens the actions for a session — start, done, skip.
  final void Function(ScheduledSlotDto slot) onSlotTap;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  Timer? _minuteTicker;
  late ScrollController _scrollController;

  static const int _timelineStartHour = 0;
  static const int _timelineEndHour = 23;
  static const double _labelWidth = 58;
  static const double _gapWidth = 8;
  static const double _hourHeight = 76;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _minuteTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentTime();
    });
  }

  void _scrollToCurrentTime() {
    final now = DateTime.now();
    final isToday =
        isSameDate(widget.selectedDate, DateTime(now.year, now.month, now.day));

    if (isToday && _scrollController.hasClients) {
      final currentMinuteOfDay = now.hour * 60 + now.minute;
      final rangeStartMinute = _timelineStartHour * 60;
      final scrollOffset =
          ((currentMinuteOfDay - rangeStartMinute) / 60) * _hourHeight - 200;
      _scrollController.animateTo(
        scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _minuteTicker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final isToday =
        isSameDate(widget.selectedDate, DateTime(now.year, now.month, now.day));
    final rangeStartMinute = _timelineStartHour * 60;
    final rangeEndMinute = (_timelineEndHour + 1) * 60;
    final currentMinuteOfDay = now.hour * 60 + now.minute;
    final totalMinutes = rangeEndMinute - rangeStartMinute;
    final timelineHeight = (totalMinutes / 60) * _hourHeight;

    // Group sessions by task so a split task can say "1 of 3".
    final sessionsPerTask = <String, int>{};
    for (final s in widget.slots) {
      sessionsPerTask[s.taskId] = (sessionsPerTask[s.taskId] ?? 0) + 1;
    }
    final orderedByTask = <String, List<String>>{};
    for (final s in [...widget.slots]
      ..sort((a, b) => a.start.compareTo(b.start))) {
      orderedByTask.putIfAbsent(s.taskId, () => []).add(s.slotId);
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 110, 16, 100),
      child: SizedBox(
        height: timelineHeight,
        child: Stack(
          children: [
            for (int hour = _timelineStartHour;
                hour <= _timelineEndHour + 1;
                hour++)
              Positioned(
                top: _offsetForMinute((hour * 60) - rangeStartMinute),
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    SizedBox(
                      width: _labelWidth,
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:00',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: isDark ? 0.5 : 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: _gapWidth),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: isDark ? 0.10 : 0.16),
                      ),
                    ),
                  ],
                ),
              ),
            for (final commitment in widget.commitments)
              _buildCommitmentBlock(
                  context, theme, commitment, rangeStartMinute, rangeEndMinute),
            for (final slot in widget.slots)
              _buildSessionBlock(
                context,
                theme,
                slot,
                rangeStartMinute,
                rangeEndMinute,
                sessionIndex:
                    (orderedByTask[slot.taskId]?.indexOf(slot.slotId) ?? 0) + 1,
                sessionCount: sessionsPerTask[slot.taskId] ?? 1,
              ),
            if (isToday)
              _buildNowLine(
                  theme, currentMinuteOfDay, rangeStartMinute, rangeEndMinute),
          ],
        ),
      ),
    );
  }

  /// Geometry shared by both block types, so a commitment and a session of the
  /// same length always line up exactly.
  ({double top, double height})? _blockGeometry(
    int startMinute,
    int endMinute,
    int rangeStartMinute,
    int rangeEndMinute,
  ) {
    final clampedStart = startMinute.clamp(rangeStartMinute, rangeEndMinute);
    final clampedEnd = endMinute.clamp(rangeStartMinute, rangeEndMinute);
    if (clampedEnd <= clampedStart) return null;

    final top = _offsetForMinute(clampedStart - rangeStartMinute) + 4;
    final height = ((_offsetForMinute(clampedEnd - rangeStartMinute) -
                _offsetForMinute(clampedStart - rangeStartMinute)) -
            8)
        .clamp(26.0, double.infinity);
    return (top: top, height: height);
  }

  Widget _buildCommitmentBlock(
    BuildContext context,
    ThemeData theme,
    FixedCommitmentDto commitment,
    int rangeStartMinute,
    int rangeEndMinute,
  ) {
    final geo = _blockGeometry(commitment.startMinute, commitment.endMinute,
        rangeStartMinute, rangeEndMinute);
    if (geo == null) return const SizedBox.shrink();

    final timeLabel = '${commitment.startTime.format(context)} - '
        '${commitment.endTime.format(context)}';

    return Positioned(
      top: geo.top,
      left: _labelWidth + _gapWidth + 2,
      right: 2,
      child: Container(
        height: geo.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
            horizontal: 12, vertical: geo.height < 40 ? 4 : 8),
        child: geo.height < 45
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      commitment.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: geo.height < 32 ? 12 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (geo.height >= 32) ...[
                    const SizedBox(width: 8),
                    Text(
                      timeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    commitment.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );
  }

  /// A work session the scheduler placed.
  ///
  /// Deliberately a surface card with a category accent rather than another
  /// solid blue block: the user needs to tell at a glance what is immovable
  /// (a class) from what the app decided (their own work), because only the
  /// latter can be started, finished or moved.
  Widget _buildSessionBlock(
    BuildContext context,
    ThemeData theme,
    ScheduledSlotDto slot,
    int rangeStartMinute,
    int rangeEndMinute, {
    required int sessionIndex,
    required int sessionCount,
  }) {
    final geo = _blockGeometry(
        slot.startMinutes, slot.endMinutes, rangeStartMinute, rangeEndMinute);
    if (geo == null) return const SizedBox.shrink();

    final accent = CategoryPalette.of(context, slot.category);
    final isDone = slot.status == TaskStatus.completed;
    final isRunning = slot.status == TaskStatus.inProgress;
    final compact = geo.height < 46;

    final timeLabel = '${_hhmm(slot.start)} - ${_hhmm(slot.end)}';

    return Positioned(
      top: geo.top,
      left: _labelWidth + _gapWidth + 2,
      right: 2,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onSlotTap(slot),
          child: Container(
            height: geo.height,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isRunning
                    ? accent
                    : accent.withValues(alpha: isDone ? 0.2 : 0.4),
                width: isRunning ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // The accent spine carries the category colour without
                // swamping the card.
                Container(
                  width: 4,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: isDone ? accent.withValues(alpha: 0.35) : accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: compact
                      ? Row(
                          children: [
                            Expanded(child: _title(theme, slot, isDone, 13)),
                            const SizedBox(width: 6),
                            Text(
                              timeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CategoryPalette.iconOf(slot.category),
                                  size: 13,
                                  color: accent,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: _title(theme, slot, isDone, 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  timeLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                                if (sessionCount > 1) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    'session $sessionIndex of $sessionCount',
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: accent.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10, left: 4),
                  child: Icon(
                    isDone
                        ? Icons.check_circle
                        : isRunning
                            ? Icons.play_circle_fill
                            : Icons.radio_button_unchecked,
                    size: 18,
                    color: isDone
                        ? accent
                        : isRunning
                            ? accent
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(
      ThemeData theme, ScheduledSlotDto slot, bool isDone, double size) {
    return Text(
      slot.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: size,
        color: isDone
            ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
            : theme.colorScheme.onSurface,
        decoration: isDone ? TextDecoration.lineThrough : null,
        decorationColor: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildNowLine(
    ThemeData theme,
    int currentMinuteOfDay,
    int rangeStartMinute,
    int rangeEndMinute,
  ) {
    final clamped = currentMinuteOfDay.clamp(rangeStartMinute, rangeEndMinute);
    final top = _offsetForMinute(clamped - rangeStartMinute);

    return Positioned(
      top: top - 6,
      left: 0,
      right: 0,
      child: Row(
        children: [
          const SizedBox(width: _labelWidth),
          const SizedBox(width: _gapWidth),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8FA3),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8FA3).withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFF8FA3),
                    Color(0x00FF8FA3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  double _offsetForMinute(int minuteInRange) {
    return (minuteInRange / 60) * _hourHeight;
  }
}
