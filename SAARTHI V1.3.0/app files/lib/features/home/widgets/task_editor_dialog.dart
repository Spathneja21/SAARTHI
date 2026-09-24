import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/dto/task_dto.dart';

/// Collects what the scheduler needs to place a task.
///
/// Two fields are new and not optional: **category** and **energy**. They are
/// not decoration — `category` is a training feature for both ML models, and
/// `energy` is matched against an energy curve peaking around 10am to decide
/// *when* in the day a task should land. Without them the scheduler is guessing.
///
/// Two fields were deliberately removed:
///
///   * *Flexibility* — the backend has no such field; it infers flexibility from
///     duration. A control that changes nothing is worse than no control.
///   * *Which day the task sits on* — that is the scheduler's entire job. The
///     user supplies a deadline and a duration; CP-SAT returns the day and hour.
/// Creates a task, or edits one that already exists.
///
/// One widget for both because the fields are identical — a separate edit form
/// would be the same seven controls kept in step by hand.
class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog.create({
    super.key,
    required DateTime this.initialDate,
    required this.onCreate,
  })  : task = null,
        onUpdate = null;

  const TaskEditorDialog.edit({
    super.key,
    required TaskDto this.task,
    required this.onUpdate,
  })  : initialDate = null,
        onCreate = null;

  /// Seeds the deadline date picker only — it does not decide where the task
  /// lives on the timeline. Null when editing, where the task's own deadline
  /// seeds it instead.
  final DateTime? initialDate;

  /// The task being edited, or null when creating.
  final TaskDto? task;

  final void Function(TaskCreateRequest request)? onCreate;

  /// Receives a patch of **only the fields that actually changed**, so an edit
  /// never silently rewrites values the user did not touch.
  final void Function(TaskUpdateRequest request)? onUpdate;

  bool get isEditing => task != null;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  late TextEditingController _titleController;
  late DateTime _deadline;
  late TimeOfDay _deadlineTime;
  int _duration = 60;
  int _priority = 3;
  TaskCategory _category = TaskCategory.deepWork;
  EnergyLevel _energy = EnergyLevel.medium;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    if (task != null) {
      _category = task.category;
      _energy = task.energyRequirement;
      _duration = task.estimatedDuration;
      _priority = task.priority;
    }
    // An existing deadline wins; otherwise the date the caller seeded.
    final seed = task?.deadline ?? widget.initialDate ?? DateTime.now();
    _deadline = seed;
    _deadlineTime = task?.deadline != null
        ? TimeOfDay(hour: seed.hour, minute: seed.minute)
        : const TimeOfDay(hour: 14, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String text, {String? hint}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(text, style: theme.textTheme.labelLarge),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A small pill showing the current value of a slider, matching the badge
  /// already used for priority.
  Widget _valueBadge(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit task' : 'Create task'),
      constraints: const BoxConstraints(maxWidth: 350, maxHeight: 560),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Task name',
                hintText: 'e.g., Prep meeting',
              ),
            ),
            const SizedBox(height: 20),

            // ── Category ──────────────────────────────────────────────────
            _sectionLabel('Category'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TaskCategory.values.map((c) {
                return ChoiceChip(
                  label: Text(c.label),
                  selected: _category == c,
                  onSelected: (selected) {
                    if (selected) setState(() => _category = c);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Energy ────────────────────────────────────────────────────
            _sectionLabel('Energy needed', hint: 'picks the time of day'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: EnergyLevel.values.map((e) {
                return ChoiceChip(
                  label: Text(e.label),
                  selected: _energy == e,
                  onSelected: (selected) {
                    if (selected) setState(() => _energy = e);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Duration ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Duration', style: theme.textTheme.labelLarge),
                _valueBadge(_durationLabel(_duration)),
              ],
            ),
            Slider(
              value: _duration.toDouble(),
              min: 15,
              max: 480,
              divisions: 31,
              label: _durationLabel(_duration),
              onChanged: (value) => setState(() => _duration = value.toInt()),
            ),
            const SizedBox(height: 8),

            // ── Priority ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Priority', style: theme.textTheme.labelLarge),
                _valueBadge('$_priority'),
              ],
            ),
            Slider(
              value: _priority.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$_priority',
              onChanged: (value) => setState(() => _priority = value.toInt()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Low',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  'High',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Deadline ──────────────────────────────────────────────────
            _sectionLabel('Deadline', hint: 'not when it runs'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(_deadline)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _deadline,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime(2100),
                );
                if (selected != null) {
                  setState(() => _deadline = selected);
                }
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              subtitle: Text(
                '${_deadlineTime.hour.toString().padLeft(2, '0')}:'
                '${_deadlineTime.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: _deadlineTime,
                );
                if (selected != null) {
                  setState(() => _deadlineTime = selected);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  static String _durationLabel(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }

    final deadline = DateTime(
      _deadline.year,
      _deadline.month,
      _deadline.day,
      _deadlineTime.hour,
      _deadlineTime.minute,
    );

    final task = widget.task;
    if (task == null) {
      widget.onCreate!(TaskCreateRequest(
        title: title,
        category: _category,
        energyRequirement: _energy,
        estimatedDuration: _duration,
        priority: _priority,
        deadline: deadline,
      ));
      return;
    }

    // Only what changed. The backend answers 422 to an empty patch, and sending
    // every field back would overwrite anything altered elsewhere since this
    // dialog opened.
    widget.onUpdate!(TaskUpdateRequest(
      title: title == task.title ? null : title,
      category: _category == task.category ? null : _category,
      energyRequirement:
          _energy == task.energyRequirement ? null : _energy,
      estimatedDuration:
          _duration == task.estimatedDuration ? null : _duration,
      priority: _priority == task.priority ? null : _priority,
      deadline: task.deadline != null &&
              deadline.isAtSameMomentAs(task.deadline!)
          ? null
          : deadline,
    ));
  }
}
