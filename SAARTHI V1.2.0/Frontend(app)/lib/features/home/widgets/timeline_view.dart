import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data/models/daily_task.dart';
import '../../../core/data/models/schedule_entry.dart';
import '../../../core/utils/time_utils.dart';

class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.selectedDate,
    required this.fixedEntries,
    required this.dayTasks,
    required this.onTaskToggle,
    required this.onTaskDelete,
  });

  final DateTime selectedDate;
  final List<ScheduleEntry> fixedEntries;
  final List<DailyTask> dayTasks;
  final Function(String, bool) onTaskToggle;
  final Function(String) onTaskDelete;

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
      if (mounted) {
        setState(() {});
      }
    });
    
    // Auto-scroll to current time on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentTime();
    });
  }

  void _scrollToCurrentTime() {
    final now = DateTime.now();
    final isToday = isSameDate(widget.selectedDate, DateTime(now.year, now.month, now.day));
    
    if (isToday && _scrollController.hasClients) {
      final currentMinuteOfDay = now.hour * 60 + now.minute;
      final rangeStartMinute = _timelineStartHour * 60;
      final scrollOffset = ((currentMinuteOfDay - rangeStartMinute) / 60) * _hourHeight - 200;
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
    final now = DateTime.now();
    final isToday = isSameDate(widget.selectedDate, DateTime(now.year, now.month, now.day));
    final rangeStartMinute = _timelineStartHour * 60;
    final rangeEndMinute = (_timelineEndHour + 1) * 60;
    final currentMinuteOfDay = now.hour * 60 + now.minute;
    final totalMinutes = rangeEndMinute - rangeStartMinute;
    final timelineHeight = (totalMinutes / 60) * _hourHeight;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 110, 16, 100),
      child: SizedBox(
        height: timelineHeight,
        child: Stack(
          children: [
            for (int hour = _timelineStartHour; hour <= _timelineEndHour + 1; hour++)
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
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: _gapWidth),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: const Color(0xFFB8B6B0),
                      ),
                    ),
                  ],
                ),
              ),
            for (final entry in widget.fixedEntries)
              _buildFixedEntry(context, theme, entry, rangeStartMinute, rangeEndMinute),
            for (final task in widget.dayTasks)
              _buildTaskMarker(context, theme, task, rangeStartMinute, rangeEndMinute, widget.onTaskToggle, widget.onTaskDelete),
            if (isToday)
              _buildNowLine(theme, currentMinuteOfDay, rangeStartMinute, rangeEndMinute),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedEntry(
    BuildContext context,
    ThemeData theme,
    ScheduleEntry entry,
    int rangeStartMinute,
    int rangeEndMinute,
  ) {
    final entryStart = entry.startTime.hour * 60 + entry.startTime.minute;
    final entryEnd = entry.endTime.hour * 60 + entry.endTime.minute;
    final clampedStart = entryStart.clamp(rangeStartMinute, rangeEndMinute);
    final clampedEnd = entryEnd.clamp(rangeStartMinute, rangeEndMinute);
    if (clampedEnd <= clampedStart) {
      return const SizedBox.shrink();
    }

    final top = _offsetForMinute(clampedStart - rangeStartMinute) + 4;
    final height = ((_offsetForMinute(clampedEnd - rangeStartMinute) -
                _offsetForMinute(clampedStart - rangeStartMinute)) -
            8)
        .clamp(26.0, double.infinity);

    return Positioned(
      top: top,
      left: _labelWidth + _gapWidth + 2,
      right: 2,
      child: Container(
        height: height,
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
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: height < 40 ? 4 : 8),
        child: height < 45
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontSize: height < 32 ? 12 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (height >= 32) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${entry.startTime.format(context)} - ${entry.endTime.format(context)}',
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
                    entry.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.startTime.format(context)} - ${entry.endTime.format(context)}',
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

  Widget _buildTaskMarker(
    BuildContext context,
    ThemeData theme,
    DailyTask task,
    int rangeStartMinute,
    int rangeEndMinute,
    Function(String, bool) onTaskToggle,
    Function(String) onTaskDelete,
  ) {
    final minute = task.deadline.hour * 60 + task.deadline.minute;
    if (minute < rangeStartMinute || minute > rangeEndMinute) {
      return const SizedBox.shrink();
    }
    final top = _offsetForMinute(minute - rangeStartMinute);

    return Positioned(
      top: top - 12,
      left: _labelWidth + _gapWidth + 2,
      right: 2,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.error.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => onTaskToggle(task.id, !task.isDone),
                    child: Icon(
                      task.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      task.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => onTaskDelete(task.id),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
          SizedBox(width: _labelWidth),
          const SizedBox(width: _gapWidth),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFFFF8FA3),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8FA3).withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF8FA3),
                    const Color(0xFFFF8FA3).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _offsetForMinute(int minuteInRange) {
    return (minuteInRange / 60) * _hourHeight;
  }
}
