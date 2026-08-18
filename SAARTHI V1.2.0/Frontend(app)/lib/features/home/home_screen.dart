import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../../core/data/models/user_profile.dart';
import '../../core/data/stores/daily_task_store.dart';
import '../../core/data/stores/schedule_store.dart';
import '../../core/services/auth_service.dart';
import '../onboarding/pages/weekly_setup_page.dart';
import '../splash/splash_screen.dart';
import 'widgets/task_creation_dialog.dart';
import 'widgets/timeline_view.dart';
import 'widgets/week_strip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScheduleStore _scheduleStore = ScheduleStore();
  final DailyTaskStore _dailyTaskStore = DailyTaskStore();
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _scheduleStore.load();
    _dailyTaskStore.load();
  }

  @override
  void dispose() {
    _scheduleStore.dispose();
    _dailyTaskStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, ${widget.profile.name.isEmpty ? 'there' : widget.profile.name}'),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, _) {
              final isLight = currentMode == ThemeMode.light;
              return IconButton(
                onPressed: () {
                  themeNotifier.value = isLight ? ThemeMode.dark : ThemeMode.light;
                },
                tooltip: 'Toggle Theme',
                icon: Icon(isLight ? Icons.dark_mode_outlined : Icons.light_mode),
              );
            },
          ),
          IconButton(
            onPressed: _openFixedScheduleEditor,
            tooltip: 'Edit fixed schedule',
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
          IconButton(
            onPressed: () async {
              await AuthService().signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashScreen()),
                (route) => false,
              );
            },
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_scheduleStore, _dailyTaskStore]),
          builder: (context, child) {
            final fixedEntries = _scheduleStore.entriesForDate(_selectedDate);
            final dayTasks = _dailyTaskStore.tasksForDate(_selectedDate);

            return Stack(
              children: [
                TimelineView(
                  selectedDate: _selectedDate,
                  fixedEntries: fixedEntries,
                  dayTasks: dayTasks,
                  onTaskToggle: (taskId, isDone) {
                    _dailyTaskStore.toggleTask(taskId, isDone);
                  },
                  onTaskDelete: (taskId) {
                    _dailyTaskStore.deleteTask(taskId);
                  },
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: WeekStrip(
                      selectedDate: _selectedDate,
                      onDateSelected: (date) {
                        setState(() {
                          _selectedDate = date;
                        });
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 110,
                  right: 18,
                  child: Material(
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
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              _formatDatePill(_selectedDate),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    letterSpacing: 0.3,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 18,
                  right: 18,
                  child: Material(
                    color: Colors.transparent,
                    child: PopupMenuButton<String>(
                      color: Theme.of(context).colorScheme.surface,
                      onSelected: (value) {
                        if (value == 'add') {
                          _showAddTaskDialog();
                        } else if (value == 'delete') {
                          _showTaskDeletionDialog();
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'add',
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 20),
                              SizedBox(width: 12),
                              Text('Add Task'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 20),
                              SizedBox(width: 12),
                              Text('Delete Task'),
                            ],
                          ),
                        ),
                      ],
                      icon: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.menu,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatDatePill(DateTime date) {
    final day = DateFormat('EEEE').format(date).toUpperCase();
    final month = DateFormat('MMM').format(date);
    return '$day, ${_ordinal(date.day)} $month';
  }

  String _ordinal(int day) {
    if (day >= 11 && day <= 13) {
      return '${day}th';
    }
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

  Future<void> _showDatePicker() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      setState(() {
        _selectedDate = selected;
      });
    }
  }

  Future<void> _showAddTaskDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return TaskCreationDialog(
          initialDate: _selectedDate,
          onTaskCreated: (title, deadline, durationMinutes, priority, flexibility) {
            _dailyTaskStore.addTask(
              title: title,
              date: _selectedDate,
              deadline: deadline,
              durationMinutes: durationMinutes,
              priority: priority,
              flexibility: flexibility,
            );
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );
  }

  Future<void> _showTaskDeletionDialog() async {
    final dayTasks = _dailyTaskStore.tasksForDate(_selectedDate);
    
    if (dayTasks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tasks to delete')),
        );
      }
      return;
    }

    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Delete Task'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                itemCount: dayTasks.length,
                itemBuilder: (context, index) {
                  final task = dayTasks[index];
                  return ListTile(
                    title: Text(task.title),
                    subtitle: Text(
                      '${task.deadline.hour.toString().padLeft(2, '0')}:${task.deadline.minute.toString().padLeft(2, '0')}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        _dailyTaskStore.deleteTask(task.id);
                        Navigator.of(dialogContext).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('"${task.title}" deleted')),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    }
  }

  void _openFixedScheduleEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Edit Fixed Weekly Schedule'),
          ),
          body: WeeklySetupPage(scheduleStore: _scheduleStore),
        ),
      ),
    );
  }
}
