import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/dto/commitment_dto.dart';
import '../../../core/api/dto/slot_dto.dart';
import '../../../core/api/dto/task_dto.dart' show TaskStatus;
import '../../../core/utils/time_utils.dart';
import '../../../shared/theme/accents.dart';
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
    required this.scrollRequest,
    required this.commitmentsForDate,
    required this.slotsForDate,
    required this.isDayLoaded,
    required this.onDayNeeded,
    required this.onVisibleDateChanged,
    required this.onSlotTap,
    required this.onSlotLongPress,
  });

  /// The day the rest of the screen is talking about — the week strip's
  /// selection. Changing it scrolls the timeline there; scrolling the timeline
  /// reports back through [onVisibleDateChanged].
  final DateTime selectedDate;

  /// Bumped by the parent every time the user asks to go somewhere.
  ///
  /// A date alone cannot express the request: `selectedDate` also changes as a
  /// *result* of scrolling, so reacting to it would have the timeline chasing
  /// the user's own drag — and tapping the day already in view, which is how
  /// you get back to now after scrolling around inside today, would look like
  /// no change at all.
  final int scrollRequest;

  /// Per-day lookups rather than plain lists. The timeline draws several dates
  /// at once now, so it cannot be handed the contents of a single one.
  final List<FixedCommitmentDto> Function(DateTime) commitmentsForDate;
  final List<ScheduledSlotDto> Function(DateTime) slotsForDate;

  /// Whether an empty result from [slotsForDate] means "nothing scheduled" or
  /// "not fetched yet".
  final bool Function(DateTime) isDayLoaded;

  /// Asked for any date drawn without data. Must be cheap and idempotent — it
  /// is called for every unloaded day the viewport touches, on every build.
  final void Function(DateTime) onDayNeeded;

  /// Fired when scrolling brings a different day under the top of the viewport.
  final void Function(DateTime) onVisibleDateChanged;

  /// Opens the actions for a session — start, done, skip.
  final void Function(ScheduledSlotDto slot) onSlotTap;

  /// Long-press goes straight to editing the task behind this block.
  ///
  /// Direct rather than via an intermediate pencil affordance: the gesture is
  /// already deliberate, so making the user aim at a second target afterwards
  /// only adds a step.
  final void Function(ScheduledSlotDto slot) onSlotLongPress;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  Timer? _minuteTicker;
  late ScrollController _scrollController;

  /// The date sitting at scroll offset zero.
  ///
  /// Fixed for the life of the widget, so an offset always denotes the same
  /// instant: earlier days live in the reverse sliver at negative offsets,
  /// later days in the centre sliver at positive ones.
  late DateTime _anchor;

  /// Marks the sliver owning offset zero. Everything before it is laid out
  /// upward, which is what lets the scroll run in both directions at once.
  final GlobalKey _centerKey = GlobalKey();

  /// The day currently under the top of the viewport.
  late DateTime _visibleDate;

  static const int _timelineStartHour = 0;
  static const int _timelineEndHour = 23;
  static const double _labelWidth = 58;
  static const double _gapWidth = 8;
  static const double _hourHeight = 76;

  static const int _hoursPerDay = _timelineEndHour + 1 - _timelineStartHour;
  static const double _dayHeight = _hoursPerDay * _hourHeight;

  /// How far the timeline runs either side of the anchor.
  ///
  /// Bounded rather than genuinely endless: a year in each direction is beyond
  /// any real use, and a finite extent keeps the scroll position meaningful
  /// instead of leaving the bar permanently at nothing.
  static const int _daysEitherSide = 365;

  /// Fixed height of an hour / half-hour marker row.
  ///
  /// Fixed, rather than left to the label's text metrics, because the rule
  /// inside the row is centred vertically: only a known row height lets the
  /// line land on the exact minute offset. Previously the row took its height
  /// from the label, so every rule was drawn roughly 8px below the time it
  /// named and no block could line up with it.
  static const double _markerRowHeight = 18;

  /// Vertical space between two blocks that meet in time.
  ///
  /// Split evenly above and below each block, so a session ending at 18:00 and
  /// one starting at 18:00 both stop 1px short of the 18:00 rule. Small enough
  /// that each edge still reads as sitting on its line, wide enough that the
  /// two cards never look like one merged block.
  static const double _blockGap = 2;

  @override
  void initState() {
    super.initState();
    _anchor = _dateOnly(widget.selectedDate);
    _visibleDate = _anchor;
    _scrollController = ScrollController()..addListener(_onScroll);
    _minuteTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentTime();
    });
  }

  @override
  void didUpdateWidget(TimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollRequest != oldWidget.scrollRequest) {
      _scrollToDate(_dateOnly(widget.selectedDate));
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Days from the anchor to [date].
  ///
  /// Computed in UTC deliberately: a local-time difference spanning a
  /// daylight-saving change is 23 or 25 hours, and `inDays` would truncate that
  /// to the wrong day.
  int _indexOf(DateTime date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(_anchor.year, _anchor.month, _anchor.day)).inDays;

  DateTime _dateAt(int index) =>
      DateTime(_anchor.year, _anchor.month, _anchor.day + index);

  double _offsetForDate(DateTime date) => _indexOf(date) * _dayHeight;

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Floor rather than truncate: offsets above the anchor are negative, and
    // truncation rounds those toward zero, which would report the whole day
    // before the anchor as the anchor itself.
    final index = (_scrollController.position.pixels / _dayHeight).floor();
    final date = _dateAt(index);
    if (isSameDate(date, _visibleDate)) return;
    setState(() => _visibleDate = date);
    widget.onVisibleDateChanged(date);
  }

  void _jumpClamped(double target) {
    final position = _scrollController.position;
    _scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _scrollToCurrentTime() {
    if (!_scrollController.hasClients) return;
    final now = DateTime.now();
    final minutesIn = (now.hour * 60 + now.minute) - _timelineStartHour * 60;
    // Jumped, not animated: the anchor is wherever the day happens to start, so
    // animating would fly the user through hours of empty grid to get here.
    _jumpClamped(
      _offsetForDate(_dateOnly(now)) + (minutesIn / 60) * _hourHeight - 200,
    );
  }

  void _scrollToDate(DateTime date) {
    if (!_scrollController.hasClients) return;
    final now = DateTime.now();
    // Today lands on the current hour, not on its 00:00. Tapping today is a
    // "take me back" gesture, and dropping the user at midnight would leave
    // them scrolling forward through the hours they had just left.
    final target = isSameDate(date, _dateOnly(now))
        ? _offsetForDate(date) +
              (((now.hour * 60 + now.minute) - _timelineStartHour * 60) / 60) *
                  _hourHeight -
              200
        : _offsetForDate(date);
    final position = _scrollController.position;
    _scrollController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
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

    // Two lists sharing one viewport, split at `_centerKey`: the first is laid
    // out upward from offset zero and holds the days before the anchor, the
    // second downward from it. This is what makes the timeline continuous
    // across midnight without any jump-back trickery — there is no seam to
    // hide, because the scroll genuinely extends in both directions.
    return CustomScrollView(
      controller: _scrollController,
      center: _centerKey,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _dayColumn(theme, _dateAt(-(index + 1))),
            childCount: _daysEitherSide,
          ),
        ),
        SliverList(
          key: _centerKey,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _dayColumn(theme, _dateAt(index)),
            childCount: _daysEitherSide,
          ),
        ),
      ],
    );
  }

  /// One day, drawn in its own coordinate space from 00:00 at the top.
  ///
  /// Every block positions itself by minutes-from-midnight, so giving each day
  /// its own fixed-height box leaves that arithmetic untouched no matter how
  /// far the user has scrolled.
  Widget _dayColumn(ThemeData theme, DateTime date) {
    final isDark = theme.brightness == Brightness.dark;
    final slots = widget.slotsForDate(date);
    final commitments = widget.commitmentsForDate(date);

    if (!widget.isDayLoaded(date)) {
      // Deferred to after the frame: asking during build would mutate the store
      // mid-layout. The store's own gate makes the repeat calls free.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDayNeeded(date);
      });
    }

    final rangeStartMinute = _timelineStartHour * 60;
    final rangeEndMinute = (_timelineEndHour + 1) * 60;
    final now = DateTime.now();
    final isToday = isSameDate(date, _dateOnly(now));

    // Group sessions by task so a split task can say "1 of 3".
    final sessionsPerTask = <String, int>{};
    for (final s in slots) {
      sessionsPerTask[s.taskId] = (sessionsPerTask[s.taskId] ?? 0) + 1;
    }
    final orderedByTask = <String, List<String>>{};
    for (final s in [...slots]..sort((a, b) => a.start.compareTo(b.start))) {
      orderedByTask.putIfAbsent(s.taskId, () => []).add(s.slotId);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: _dayHeight,
        child: Stack(
          // The midnight marker is centred on this box's very first row, so
          // half of it falls outside these bounds — and a Stack clips to its
          // bounds by default, which would slice the day label in two.
          clipBehavior: Clip.none,
          children: [
            for (
              int hour = _timelineStartHour;
              hour <= _timelineEndHour;
              hour++
            )
              _hourMarker(theme, isDark, hour, rangeStartMinute, date),
            for (
              int hour = _timelineStartHour;
              hour <= _timelineEndHour;
              hour++
            )
              _halfHourMarker(theme, isDark, hour, rangeStartMinute),
            for (final commitment in commitments)
              _buildCommitmentBlock(
                context,
                theme,
                commitment,
                rangeStartMinute,
                rangeEndMinute,
              ),
            for (final slot in slots)
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
                theme,
                now.hour * 60 + now.minute,
                rangeStartMinute,
                rangeEndMinute,
              ),
          ],
        ),
      ),
    );
  }

  /// An hour rule — and at midnight, the day divider.
  ///
  /// There is no "24:00" any more: the next day's 00:00 occupies exactly that
  /// line. Midnight is therefore the only place a day boundary can announce
  /// itself, so it names the date rather than the hour. Without that a
  /// continuous scroll gives no clue which day is on screen.
  Widget _hourMarker(
    ThemeData theme,
    bool isDark,
    int hour,
    int rangeStartMinute,
    DateTime date,
  ) {
    final isMidnight = hour == _timelineStartHour;
    final onSurface = theme.colorScheme.onSurface;
    return Positioned(
      top:
          _offsetForMinute((hour * 60) - rangeStartMinute) -
          _markerRowHeight / 2,
      left: 0,
      right: 0,
      height: _markerRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(
              isMidnight
                  ? DateFormat('EEE d').format(date).toUpperCase()
                  : '${hour.toString().padLeft(2, '0')}:00',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isMidnight ? FontWeight.w800 : null,
                color: onSurface.withValues(
                  alpha: isMidnight
                      ? (isDark ? 0.82 : 0.85)
                      : (isDark ? 0.5 : 0.6),
                ),
              ),
            ),
          ),
          const SizedBox(width: _gapWidth),
          Expanded(
            child: Container(
              height: isMidnight ? 1.5 : 1,
              color: onSurface.withValues(
                alpha: isMidnight
                    ? (isDark ? 0.26 : 0.34)
                    : (isDark ? 0.10 : 0.16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Half-hour marks, deliberately quieter than the hours: smaller type, lower
  /// contrast, and a short tick in place of the full rule.
  ///
  /// The hour grid has to keep carrying the structure of the day. Drawn at
  /// equal weight the column would read as a 48-row ladder and the hours would
  /// stop being findable at a glance.
  Widget _halfHourMarker(
    ThemeData theme,
    bool isDark,
    int hour,
    int rangeStartMinute,
  ) {
    final onSurface = theme.colorScheme.onSurface;
    return Positioned(
      top:
          _offsetForMinute((hour * 60 + 30) - rangeStartMinute) -
          _markerRowHeight / 2,
      left: 0,
      right: 0,
      height: _markerRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(
              '${hour.toString().padLeft(2, '0')}:30',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: onSurface.withValues(alpha: isDark ? 0.32 : 0.42),
              ),
            ),
          ),
          const SizedBox(width: _gapWidth),
          // A stub rather than an Expanded rule, so the half hour is a
          // reference point beside the label and never a line the eye can
          // mistake for an hour boundary behind the blocks.
          Container(
            width: 12,
            height: 1,
            color: onSurface.withValues(alpha: isDark ? 0.12 : 0.18),
          ),
        ],
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

    // A block spans exactly its own minutes, less `_blockGap` shared evenly
    // between its two edges. The previous geometry inset each block by 4 top
    // and bottom, which opened an 8px trough between two sessions that touch in
    // time and left neither edge anywhere near the rule it was meant to meet.
    final top =
        _offsetForMinute(clampedStart - rangeStartMinute) + _blockGap / 2;
    final height =
        ((_offsetForMinute(clampedEnd - rangeStartMinute) -
                    _offsetForMinute(clampedStart - rangeStartMinute)) -
                _blockGap)
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
    final geo = _blockGeometry(
      commitment.startMinute,
      commitment.endMinute,
      rangeStartMinute,
      rangeEndMinute,
    );
    if (geo == null) return const SizedBox.shrink();

    final timeLabel =
        '${commitment.startTime.format(context)} - '
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
          horizontal: 12,
          vertical: geo.height < 40 ? 4 : 8,
        ),
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
      slot.startMinutes,
      slot.endMinutes,
      rangeStartMinute,
      rangeEndMinute,
    );
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
          onLongPress: () => widget.onSlotLongPress(slot),
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
                // The accent pill carries the category colour without
                // swamping the card.
                //
                // Inset and fully rounded, rather than the flush full-height
                // spine this used to be. A flush spine has to match the card's
                // *inner* corner radius — the outer 14 minus the border width —
                // and that border grows from 1 to 2 while a session is running,
                // so the two could never stay in step. Worse, the card paints a
                // rounded `BoxDecoration` but does not clip its children, so
                // the spine simply painted straight through the corner. Letting
                // the pill float inside the padding takes it out of the
                // corner's geometry altogether.
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  // Centred by the Row, so this only has to be shorter than the
                  // card; the inset then falls out evenly top and bottom at any
                  // block height. Floored so the shortest blocks still show a
                  // recognisable mark rather than a dot.
                  height: (geo.height - 20).clamp(10.0, double.infinity),
                  decoration: BoxDecoration(
                    color: isDone ? accent.withValues(alpha: 0.35) : accent,
                    borderRadius: BorderRadius.circular(2),
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
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
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
                                    style: theme.textTheme.labelSmall?.copyWith(
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
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
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
    ThemeData theme,
    ScheduledSlotDto slot,
    bool isDone,
    double size,
  ) {
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
      // Half the 14px dot, so the marker's centre is the current minute.
      top: top - 7,
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
              color: kNowAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kNowAccent.withValues(alpha: 0.5),
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
                    kNowAccent,
                    // The same colour at zero alpha, written out so the
                    // gradient stays const.
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
