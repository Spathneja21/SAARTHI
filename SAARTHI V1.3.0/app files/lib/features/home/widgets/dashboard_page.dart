import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/dto/slot_dto.dart';
import '../../../core/api/dto/task_dto.dart';
import '../../../shared/theme/category_palette.dart';
// Flip-clock style is on hold for revisiting later; see FlipClock widget.
// import '../../../shared/widgets/flip_clock.dart';

/// Opacity of the frosted panels.
///
/// Raised from the original 0.55. The backdrop behind this page is not a fixed
/// colour — `FluidMorphBackground` sweeps bands from `#D3E6FA` down to
/// `#5D9BDE` — and white at 55% over that deepest band settles near `#B6D2F0`.
/// The small muted labels then sat at roughly 2:1 against their own card, under
/// half the 4.5:1 WCAG floor for text this size, and went nearly invisible
/// whenever a dark band drifted under a card. At 0.78 the panels still read as
/// glass while the labels clear the floor against every band the sweep passes
/// through.
const double _panelOpacity = 0.78;

/// Corner radius shared by every panel on this page, so the stat row, the
/// progress card and the hints all sit on one grid.
const double _panelRadius = 20.0;

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

  /// The session worth surfacing under the counters: whatever is running right
  /// now, else the next one still ahead.
  ///
  /// Completed work is skipped rather than shown as "up next" — a finished
  /// session is not something the user still has to do, and offering it as the
  /// next thing would send them back to work they already closed out.
  _Highlight? _highlight(Map<String, TaskStatus> statusById) {
    final pending = widget.todaySlots
        .where((s) => statusById[s.taskId] != TaskStatus.completed)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    for (final slot in pending) {
      // Sorted by start, so the first slot straddling `now` is the live one and
      // the first slot starting after `now` is the soonest — either way the
      // first match wins and the scan can stop.
      if (!slot.start.isAfter(_now) && slot.end.isAfter(_now)) {
        return _Highlight(slot, isNow: true);
      }
      if (slot.start.isAfter(_now)) {
        return _Highlight(slot, isNow: false);
      }
    }
    return null;
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

    final highlight = _highlight(statusById);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        children: [
          Text(
            DateFormat('EEEE, MMMM d').format(_now),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
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
                  // Deliberately one fixed word. The label used to flip between
                  // "Planned" and "Planned time" with the value, which made the
                  // three cards jitter out of alignment as the day filled up.
                  label: 'Planned',
                  value: _durationLabel(minutesPlanned),
                  icon: Icons.timelapse_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProgressCard(total: total, completed: completed),
          const SizedBox(height: 14),
          // Always one card in this position, whatever the day looks like. The
          // page used to simply end here on a quiet day, leaving roughly a
          // third of the screen blank under the progress bar and giving the
          // impression the dashboard had failed to load rather than that there
          // was genuinely nothing on.
          if (highlight != null)
            _UpNextCard(highlight: highlight, now: _now)
          else
            _DayStateCard(
              hasSlots: widget.todaySlots.isNotEmpty,
              unplannedCount: widget.unplannedCount,
            ),
          // Only alongside a live session: the empty-day card already carries
          // the unplanned count, and showing both would state it twice.
          if (highlight != null && widget.unplannedCount > 0) ...[
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

/// A slot plus the framing it earned — running now, or still ahead.
///
/// Bundled together because the two cases differ only in wording and accent;
/// handing the card a bare slot would force it to re-derive against the clock
/// what the lookup already worked out.
class _Highlight {
  const _Highlight(this.slot, {required this.isNow});

  final ScheduledSlotDto slot;
  final bool isNow;
}

/// The frosted panel every block on this page is built from.
///
/// Extracted because the `ClipRRect` + `BackdropFilter` + translucent
/// `Container` stack was repeated verbatim in each card, which is how the
/// opacity drifted out of step with the background in the first place. One
/// definition means the contrast of the whole page moves on a single knob.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.padding,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Overrides the default hairline, for panels that want to carry an accent.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(_panelRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: _panelOpacity),
            borderRadius: BorderRadius.circular(_panelRadius),
            border: Border.all(
              color: borderColor ??
                  theme.colorScheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The muted caption style used under every stat.
///
/// Not `labelSmall` from the theme: that resolves to `#8E8E93`, a grey chosen
/// against an opaque `#F2F2F7` scaffold. On a translucent card floating over
/// the blue sweep it washes out, so these labels key off `onSurface` and stay
/// legible whichever band is passing beneath.
TextStyle? _captionStyle(ThemeData theme) =>
    theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );

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
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      borderColor: theme.colorScheme.primary.withValues(alpha: 0.25),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
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
    );
  }
}

/// What the user should have in hand right now, filling the stretch of dead
/// space that used to sit between the progress bar and the bottom of the page.
///
/// The counters answer "how much is there"; they never answer "what next",
/// which on a scheduling app is the question the home screen exists to settle.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({required this.highlight, required this.now});

  final _Highlight highlight;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slot = highlight.slot;
    final accent = CategoryPalette.of(context, slot.category);

    // A live session gets the category accent on its border so it reads as the
    // active thing on the page; an upcoming one keeps the neutral hairline and
    // stays visually quieter than the work actually in progress.
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      borderColor: highlight.isNow ? accent.withValues(alpha: 0.55) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              CategoryPalette.iconOf(slot.category),
              size: 22,
              color: accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  highlight.isNow ? 'HAPPENING NOW' : 'UP NEXT',
                  style: _captionStyle(theme)?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  slot.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('h:mm').format(slot.start)} – '
                  '${DateFormat('h:mm a').format(slot.end)}'
                  '  ·  ${_durationLabel(slot.durationMinutes)}',
                  style: _captionStyle(theme),
                ),
              ],
            ),
          ),
          // Only a running session has a meaningful countdown; for a future one
          // the start time above already says everything.
          if (highlight.isNow)
            Text(
              _remainingLabel(slot.end.difference(now)),
              style: theme.textTheme.titleMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

/// "left on the clock" for the running session, floored at zero so an overrun
/// reads as `0m` rather than a negative count.
String _remainingLabel(Duration remaining) {
  final minutes = remaining.inMinutes;
  if (minutes <= 0) return '0m';
  return _durationLabel(minutes);
}

/// What stands in for the "up next" card when there is no next session: either
/// the day was never filled, or everything on it is already closed out.
///
/// The two cases are deliberately worded apart. "Nothing scheduled" is a prompt
/// to go and plan something; "all wrapped up" is a result. Collapsing them into
/// one neutral empty state would tell a user who just finished their last task
/// the same thing it tells a user who has not started.
class _DayStateCard extends StatelessWidget {
  const _DayStateCard({required this.hasSlots, required this.unplannedCount});

  /// Whether today had any sessions at all, which is what separates a finished
  /// day from an unplanned one.
  final bool hasSlots;

  final int unplannedCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String headline;
    final IconData icon;
    if (hasSlots) {
      headline = "Today's work is done";
      icon = Icons.task_alt_rounded;
    } else {
      headline = 'Nothing scheduled today';
      icon = Icons.event_available_outlined;
    }

    final String detail;
    if (unplannedCount > 0) {
      detail = unplannedCount == 1
          ? '1 task is waiting for a time slot.'
          : '$unplannedCount tasks are waiting for a time slot.';
    } else if (hasSlots) {
      detail = 'Nothing left on the schedule.';
    } else {
      detail = 'Add a task and the scheduler will place it for you.';
    }

    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(detail, style: _captionStyle(theme)),
              ],
            ),
          ),
        ],
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
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        children: [
          // Small and dimmed: the number is the point of the card, and a
          // full-strength 26px blue glyph was pulling the eye off it.
          Icon(
            icon,
            color: theme.colorScheme.primary.withValues(alpha: 0.75),
            size: 18,
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: _captionStyle(theme),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ],
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

    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _ProgressRing(fraction: fraction, hasWork: total > 0),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's progress",
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                // The raw counts, which the old bar never showed. A ring gives
                // the shape of the day at a glance but hides the numbers
                // behind a percentage, and "3 of 8" is the thing a person
                // actually repeats to themselves.
                Text(
                  total == 0
                      ? 'Nothing scheduled yet'
                      : '$completed of $total done',
                  style: _captionStyle(theme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dial itself.
///
/// Animated toward `fraction` rather than snapped to it: finishing a task is
/// the one event this page exists to acknowledge, and letting the ring sweep
/// up to its new value marks the moment without needing any other affordance.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.fraction, required this.hasWork});

  final double fraction;

  /// Whether anything is scheduled at all. An empty day is not 0% done — there
  /// is simply nothing to be done — so it shows a dash instead of a zero that
  /// would read as failure.
  final bool hasWork;

  static const double _diameter = 84;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: _diameter,
          height: _diameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 9,
                  // Rounded ends so a part-finished day reads as a drawn arc
                  // rather than a slice cut out of a donut.
                  strokeCap: StrokeCap.round,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.12),
                  valueColor:
                      AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
              Text(
                hasWork ? '${(value * 100).round()}%' : '\u2014',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: hasWork
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
