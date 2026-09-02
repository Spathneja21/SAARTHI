import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/data/models/daily_task.dart';

class TaskCreationDialog extends StatefulWidget {
  const TaskCreationDialog({
    super.key,
    required this.initialDate,
    required this.onTaskCreated,
  });

  final DateTime initialDate;
  final Function(String, DateTime, int, int, TaskFlexibility) onTaskCreated;

  @override
  State<TaskCreationDialog> createState() => _TaskCreationDialogState();
}

class _TaskCreationDialogState extends State<TaskCreationDialog> {
  late TextEditingController _titleController;
  late DateTime _deadline;
  late TimeOfDay _deadlineTime;
  int _duration = 60;
  int _priority = 3;
  TaskFlexibility _flexibility = TaskFlexibility.flexible;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _deadline = widget.initialDate;
    _deadlineTime = const TimeOfDay(hour: 14, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create task'),
      constraints: const BoxConstraints(maxWidth: 350, maxHeight: 500),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task title
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Task name',
                hintText: 'e.g., Prep meeting',
              ),
            ),
            const SizedBox(height: 16),

            // Deadline date
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Deadline date'),
              subtitle: Text(DateFormat('MMM d, yyyy').format(_deadline)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _deadline,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (selected != null) {
                  setState(() {
                    _deadline = selected;
                  });
                }
              },
            ),

            // Deadline time
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Deadline time'),
              subtitle: Text('${_deadlineTime.hour.toString().padLeft(2, '0')}:${_deadlineTime.minute.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final selected = await showTimePicker(
                  context: context,
                  initialTime: _deadlineTime,
                );
                if (selected != null) {
                  setState(() {
                    _deadlineTime = selected;
                  });
                }
              },
            ),

            const SizedBox(height: 16),

            // Duration (15 min to 8 hours)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Duration: ${_duration ~/ 60}h ${_duration % 60}m',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Slider(
                  value: _duration.toDouble(),
                  min: 15,
                  max: 480,
                  divisions: 30,
                  label: '${_duration ~/ 60}h ${_duration % 60}m',
                  onChanged: (value) {
                    setState(() {
                      _duration = value.toInt();
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Priority (1-5 scale)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Priority',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_priority',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _priority.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$_priority',
                  onChanged: (value) {
                    setState(() {
                      _priority = value.toInt();
                    });
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Low',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    Text(
                      'High',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Flexibility
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flexibility',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Flexible'),
                        selected: _flexibility == TaskFlexibility.flexible,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _flexibility = TaskFlexibility.flexible;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Rigid'),
                        selected: _flexibility == TaskFlexibility.rigid,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _flexibility = TaskFlexibility.rigid;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
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
          onPressed: () {
            if (_titleController.text.trim().isEmpty) {
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

            widget.onTaskCreated(
              _titleController.text.trim(),
              deadline,
              _duration,
              _priority,
              _flexibility,
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
