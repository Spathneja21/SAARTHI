import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/api/dto/slot_dto.dart';
import '../../core/api/dto/task_dto.dart';
import '../../core/data/models/user_profile.dart';
import '../../core/data/stores/commitment_store.dart';
import '../../core/data/stores/schedule_slot_store.dart';
import '../../core/data/stores/task_store.dart';
import '../../core/data/stores/user_profile_store.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/fluid_morph_background.dart';
import '../../shared/widgets/page_dots.dart';
import '../onboarding/pages/weekly_setup_page.dart';
import '../splash/splash_screen.dart';
import '../../core/utils/time_utils.dart';
import '../../shared/theme/accents.dart';
import 'widgets/dashboard_page.dart';
import 'widgets/task_action_sheet.dart';
import 'widgets/task_editor_dialog.dart';
import 'widgets/timeline_view.dart';
import 'widgets/unplanned_tasks_sheet.dart';
import 'widgets/week_strip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();

  /// Incremented on every day tap, so the timeline can tell a deliberate
  /// "go here" from the date changing underneath it as the user scrolls.
  int _scrollRequest = 0;

  /// Geometry of the bottom-right control stack.
  ///
  /// Both controls are 56pt circles on one vertical axis. They are positioned
  /// from explicit numbers rather than each carrying its own insets because
  /// `PopupMenuButton` applies a default `EdgeInsets.all(8)` to its icon: the
  /// menu's visible circle used to sit 8pt inside its `Positioned` box while
  /// the plan button had no such inset, so the two never actually lined up.
  /// That padding is now zeroed and the spacing lives here.
  static const double _fabInset = 26;
  static const double _fabDiameter = 56;
  static const double _fabGap = 14;
  late DateTime _selectedDate;
  int _homePageIndex = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);

    // Stores live above this screen now (see the MultiProvider in app.dart), so
    // they are loaded rather than constructed, and never disposed here — the
    // old code created its own instances and disposed them with the screen,
    // which meant state died on navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEverything());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadEverything() async {
    if (!mounted) return;
    await Future.wait([
      context.read<TaskStore>().load(),
      context.read<CommitmentStore>().load(),
      context.read<ScheduleSlotStore>().loadDay(_selectedDate),
    ]);
    if (mounted) _reportAnyError();
  }

  /// Surface whichever store failed. Errors are held on the stores rather than
  /// thrown so a failed request cannot tear down the screen mid-build.
  void _reportAnyError() {
    final message =
        context.read<TaskStore>().error ??
        context.read<ScheduleSlotStore>().error ??
        context.read<CommitmentStore>().error;
    if (message == null) return;
    _snack(message);
    context.read<TaskStore>().clearError();
    context.read<ScheduleSlotStore>().clearError();
    context.read<CommitmentStore>().clearError();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _scrollRequest++;
    });
    context.read<ScheduleSlotStore>().focusDay(date);
  }

  /// The timeline scrolled a different day under the viewport.
  ///
  /// Kept separate from [_onDateSelected] so the direction of travel stays
  /// clear: this one follows the scroll, that one drives it.
  void _onTimelineDateChanged(DateTime date) {
    if (isSameDate(date, _selectedDate)) return;
    setState(() => _selectedDate = date);
    context.read<ScheduleSlotStore>().focusDay(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Hello, ${widget.profile.name.isEmpty ? 'there' : widget.profile.name}',
        ),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, _) {
              final isLight = currentMode == ThemeMode.light;
              return IconButton(
                onPressed: () {
                  themeNotifier.value = isLight
                      ? ThemeMode.dark
                      : ThemeMode.light;
                },
                tooltip: 'Toggle Theme',
                icon: Icon(
                  isLight ? Icons.dark_mode_outlined : Icons.light_mode,
                ),
              );
            },
          ),
          IconButton(
            onPressed: _openFixedScheduleEditor,
            tooltip: 'Edit fixed schedule',
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          IconButton(
            onPressed: _signOut,
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const Positioned.fill(child: FluidMorphBackground()),
          SafeArea(
            // No toolbar offset of our own here. With `extendBodyBehindAppBar`
            // the Scaffold already hands the body a top padding of
            // `appBarHeight + viewPadding.top`, which this SafeArea consumes,
            // so the `EdgeInsets.only(top: kToolbarHeight)` that used to wrap
            // this Column counted the app bar a second time and left roughly
            // 56pt of dead space between the header and the page content.
            child: Column(
              children: [
                const SizedBox(height: 8),
                PageDots(current: _homePageIndex, count: 2),
                const SizedBox(height: 8),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (value) =>
                        setState(() => _homePageIndex = value),
                    children: [
                      _buildDashboardPage(),
                      _buildTimelinePage(theme),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The dashboard always reports *today*, regardless of which day the timeline
  /// is showing — it is a "how am I doing" panel, not a browser.
  Widget _buildDashboardPage() {
    return Consumer2<TaskStore, ScheduleSlotStore>(
      builder: (context, taskStore, slotStore, _) {
        final today = DateTime.now();
        return DashboardPage(
          // Today's slots read straight out of the cache, rather than whichever
          // day the timeline happens to be focused on. The store holds many
          // days now, so the dashboard no longer has to blank itself the moment
          // the user scrolls the timeline to another date — which, with a
          // continuous scroll, would otherwise happen constantly.
          todaySlots: slotStore.slotsOn(today),
          tasks: taskStore.tasks,
          unplannedCount: taskStore.unplanned.length,
          isLoading: taskStore.isLoading || slotStore.isLoading,
        );
      },
    );
  }

  Widget _buildTimelinePage(ThemeData theme) {
    return Consumer2<ScheduleSlotStore, CommitmentStore>(
      builder: (context, slotStore, commitmentStore, _) {
        return Stack(
          children: [
            // Inset below the week strip rather than running under it. The
            // timeline is continuous now, so without this the top of every day
            // would slide behind the strip's translucent cards as it passed.
            Padding(
              padding: const EdgeInsets.only(top: 110),
              child: TimelineView(
                selectedDate: _selectedDate,
                scrollRequest: _scrollRequest,
                commitmentsForDate: commitmentStore.forDate,
                slotsForDate: slotStore.slotsOn,
                isDayLoaded: slotStore.isDayLoaded,
                onDayNeeded: slotStore.ensureDay,
                onVisibleDateChanged: _onTimelineDateChanged,
                onSlotTap: _onSlotTap,
                onSlotLongPress: (slot) => _editFromLongPress(slot.taskId),
              ),
            ),
            if (slotStore.isLoading)
              const Positioned(
                top: 118,
                left: 0,
                right: 0,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: WeekStrip(
                  today: DateTime.now(),
                  visibleDate: _selectedDate,
                  onDateSelected: _onDateSelected,
                ),
              ),
            ),
            Positioned(top: 110, right: 18, child: _datePill(theme)),
            // The primary action sits closest to the thumb, in the slot the
            // menu used to occupy; the menu stacks directly above it.
            Positioned(
              bottom: _fabInset,
              right: _fabInset,
              child: _planDayButton(theme),
            ),
            Positioned(
              bottom: _fabInset + _fabDiameter + _fabGap,
              right: _fabInset,
              child: _actionMenu(theme),
            ),
          ],
        );
      },
    );
  }

  Widget _datePill(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: _showDatePicker,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                _formatDatePill(_selectedDate),
                style: theme.textTheme.titleMedium?.copyWith(
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Plan my day", promoted out of the overflow menu.
  ///
  /// Running the solver is the one action that turns a list of tasks into an
  /// actual day, so burying it behind a menu put the app's whole point two taps
  /// away and level with "Clear schedule".
  ///
  /// Warm rather than the brand blue for the same reason: on this screen the
  /// background, the session blocks and the menu button are all blue, so a blue
  /// primary action would have had nothing to stand against. It takes
  /// `kNowAccent` straight from the timeline's now-line, and a white glyph from
  /// the menu button directly above it, so the two controls read as one pair.
  ///
  /// Circular and unlabelled to match the menu it sits above, so the tooltip
  /// carries the name that the pill used to spell out.
  Widget _planDayButton(ThemeData theme) {
    final slotStore = context.watch<ScheduleSlotStore>();
    final isPlanning = slotStore.isPlanning;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: isPlanning ? 'Planning…' : 'Plan my day',
        child: InkWell(
          onTap: isPlanning ? null : _planDay,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kNowAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kNowAccent.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isPlanning
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(Icons.auto_awesome, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _actionMenu(ThemeData theme) {
    final unplannedCount = context.watch<TaskStore>().unplanned.length;

    return Material(
      color: Colors.transparent,
      child: PopupMenuButton<String>(
        color: theme.colorScheme.surface,
        // Zeroed so this button's box is exactly its 56pt circle, matching the
        // plan button and letting both share one vertical axis.
        padding: EdgeInsets.zero,
        onSelected: (value) {
          switch (value) {
            case 'add':
              _showAddTaskDialog();
            case 'unplanned':
              _showUnplanned();
            case 'clear':
              _confirmClearSchedule();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            value: 'add',
            child: Row(
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 12),
                Text('Add task'),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'unplanned',
            child: Row(
              children: [
                const Icon(Icons.inbox_outlined, size: 20),
                const SizedBox(width: 12),
                const Text('Unplanned'),
                if (unplannedCount > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$unplannedCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'clear',
            child: Row(
              children: [
                Icon(Icons.layers_clear_outlined, size: 20),
                SizedBox(width: 12),
                Text('Clear schedule'),
              ],
            ),
          ),
        ],
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.menu, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _showAddTaskDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => TaskEditorDialog.create(
        initialDate: _selectedDate,
        onCreate: (request) async {
          Navigator.of(dialogContext).pop();
          final store = context.read<TaskStore>();
          final created = await store.create(request);
          if (!mounted) return;
          if (created == null) {
            _snack(store.error ?? 'Could not create the task.');
            store.clearError();
          } else {
            _snack('"${created.title}" added. Plan your day to place it.');
          }
        },
      ),
    );
  }

  Future<void> _showUnplanned() async {
    final taskStore = context.read<TaskStore>();
    await UnplannedTasksSheet.show(
      context,
      tasks: taskStore.unplanned,
      isPlanning: context.read<ScheduleSlotStore>().isPlanning,
      onTaskLongPress: (task) {
        Navigator.pop(context);
        _editFromLongPress(task.id);
      },
      onTaskTap: (task) {
        Navigator.pop(context);
        _openTaskActions(
          taskId: task.id,
          title: task.title,
          category: task.category,
          status: task.status,
          estimatedDuration: task.estimatedDuration,
          subtitle: 'not scheduled',
        );
      },
      onPlan: () {
        Navigator.pop(context);
        _planDay();
      },
    );
  }

  Future<void> _planDay() async {
    final slotStore = context.read<ScheduleSlotStore>();
    final result = await slotStore.planDay();
    if (!mounted) return;

    // Task statuses change as a side effect of planning, so the task list has
    // to be refetched or the unplanned count goes stale.
    await context.read<TaskStore>().load();
    if (!mounted) return;

    if (result == null) {
      _snack(slotStore.error ?? 'Planning failed.');
      slotStore.clearError();
      return;
    }
    if (result.hadNothingToDo) {
      _snack('Nothing to plan — add a task first.');
      return;
    }
    if (result.dropped.isNotEmpty) {
      // Never let a task the solver could not fit disappear quietly.
      _snack(
        'Placed ${result.scheduled.length}. '
        'Could not fit: ${result.dropped.join(", ")}',
      );
      return;
    }
    _snack(
      'Placed ${result.scheduled.length} '
      'session${result.scheduled.length == 1 ? '' : 's'}.',
    );
  }

  Future<void> _confirmClearSchedule() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear schedule?'),
        content: const Text(
          'This removes every scheduled block. Your tasks are kept, and you '
          'can plan again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final n = await context.read<ScheduleSlotStore>().clearAll();
    if (!mounted) return;
    await context.read<TaskStore>().load();
    if (mounted) _snack('Cleared $n block${n == 1 ? '' : 's'}.');
  }

  void _onSlotTap(ScheduledSlotDto slot) {
    _openTaskActions(
      taskId: slot.taskId,
      title: slot.title,
      category: slot.category,
      status: slot.status,
      estimatedDuration: slot.estimatedDuration,
      subtitle: '${_hhmm(slot.start)}–${_hhmm(slot.end)}',
    );
  }

  Future<void> _openTaskActions({
    required String taskId,
    required String title,
    required TaskCategory category,
    required TaskStatus status,
    required int estimatedDuration,
    String? subtitle,
  }) async {
    final action = await TaskActionSheet.show(
      context,
      title: title,
      category: category,
      status: status,
      subtitle: subtitle,
      estimatedDuration: estimatedDuration,
    );
    if (action == null || !mounted) return;

    final taskStore = context.read<TaskStore>();
    final slotStore = context.read<ScheduleSlotStore>();

    bool ok;
    switch (action) {
      case TaskAction.start:
        ok = await taskStore.start(taskId);
      case TaskAction.complete:
        ok = await taskStore.complete(taskId);
      case TaskAction.skip:
        ok = await taskStore.skip(taskId);
      case TaskAction.postpone:
        ok = await taskStore.postpone(taskId);
      case TaskAction.delete:
        ok = await taskStore.delete(taskId);
      case TaskAction.edit:
        await _showEditTaskDialog(taskId);
        return;
    }

    if (!mounted) return;
    if (!ok) {
      _snack(taskStore.error ?? 'That did not work.');
      taskStore.clearError();
      return;
    }

    // A status change alters what the timeline should show (a completed block
    // renders struck through), and a delete removes its slots entirely.
    await slotStore.refresh();
    if (!mounted) return;

    _snack(switch (action) {
      TaskAction.start => 'Started — the time is being tracked.',
      TaskAction.complete => 'Done.',
      TaskAction.skip => 'Skipped.',
      TaskAction.postpone => 'Postponed.',
      TaskAction.delete => 'Task deleted.',
      // Unreachable: the edit case returns above, having already reported the
      // outcome from inside the dialog.
      TaskAction.edit => '',
    });
  }

  /// Long-press route into the editor.
  ///
  /// The haptic lives here rather than in [_showEditTaskDialog] because only
  /// this path needs it: a long-press changes nothing on screen until the
  /// dialog appears, so without the tap-back a press that failed to register
  /// feels identical to one that worked. Choosing "Edit task" from the action
  /// sheet is already its own confirmation.
  Future<void> _editFromLongPress(String taskId) async {
    unawaited(HapticFeedback.mediumImpact());
    await _showEditTaskDialog(taskId);
  }

  /// Opens the editor for an existing task and applies whatever changed.
  Future<void> _showEditTaskDialog(String taskId) async {
    final taskStore = context.read<TaskStore>();
    final task = taskStore.tasks.where((t) => t.id == taskId).firstOrNull;
    if (task == null) {
      _snack('That task is no longer available.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => TaskEditorDialog.edit(
        task: task,
        onUpdate: (request) async {
          Navigator.of(dialogContext).pop();
          // The dialog sends only changed fields, so an untouched form arrives
          // empty — worth saying so rather than firing a pointless request the
          // backend would reject with a 422.
          if (request.isEmpty) {
            _snack('Nothing changed.');
            return;
          }
          final ok = await taskStore.update(task.id, request);
          if (!mounted) return;
          if (!ok) {
            _snack(taskStore.error ?? 'Could not save those changes.');
            taskStore.clearError();
            return;
          }
          // Duration or deadline changes alter what the scheduler should do
          // with this task, so the placed slots have to be refetched.
          await context.read<ScheduleSlotStore>().refresh();
          if (!mounted) return;
          _snack('Task updated.');
        },
      ),
    );
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    final taskStore = context.read<TaskStore>();
    final slotStore = context.read<ScheduleSlotStore>();
    final commitmentStore = context.read<CommitmentStore>();

    await AuthService().signOut();

    // Clearing is not optional. The old local keys were not namespaced by user
    // and sign-out left them in place, so the next person to sign in on this
    // device inherited the previous user's tasks, name and completed
    // onboarding flag. Server data is per-user now, but the in-memory stores
    // and the cached profile still have to be emptied.
    taskStore.clear();
    slotStore.clear();
    commitmentStore.clear();
    await UserProfileStore().clear();

    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  void _openFixedScheduleEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Edit Fixed Weekly Schedule')),
          body: const WeeklySetupPage(),
        ),
      ),
    );
  }

  Future<void> _showDatePicker() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) _onDateSelected(selected);
  }

  String _formatDatePill(DateTime date) {
    final day = DateFormat('EEEE').format(date).toUpperCase();
    final month = DateFormat('MMM').format(date);
    return '$day, ${_ordinal(date.day)} $month';
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
