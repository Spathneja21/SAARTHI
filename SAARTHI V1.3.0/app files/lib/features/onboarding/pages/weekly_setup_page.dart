import 'package:flutter/material.dart';

import '../../../core/data/stores/schedule_store.dart';
import '../../../core/utils/time_utils.dart';
import '../../../shared/widgets/page_shell.dart';

class WeeklySetupPage extends StatefulWidget {
  const WeeklySetupPage({super.key, required this.scheduleStore, this.onFinish});

  final ScheduleStore scheduleStore;

  /// When provided, a "Finish setup" button is shown at the bottom of the
  /// page (onboarding context). Left null when this page is reused as a
  /// standalone schedule editor (e.g. from the home screen).
  final VoidCallback? onFinish;

  @override
  State<WeeklySetupPage> createState() => _WeeklySetupPageState();
}

class _WeeklySetupPageState extends State<WeeklySetupPage> {
  int _selectedWeekday = DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Set your fixed weekly schedule',
      child: AnimatedBuilder(
        animation: widget.scheduleStore,
        builder: (context, child) {
          final entries = widget.scheduleStore.weeklyEntriesForWeekday(_selectedWeekday);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These items repeat every week.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              _WeekdaySelector(
                selectedWeekday: _selectedWeekday,
                onChanged: (value) {
                  setState(() {
                    _selectedWeekday = value;
                  });
                },
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => _showAddWeeklyEntryDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add fixed slot'),
              ),
              const SizedBox(height: 12),
              if (entries.isEmpty)
                Text(
                  'No fixed slots added for ${_weekdayLabel(_selectedWeekday)}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                ...entries.map(
                  (entry) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(entry.title),
                      subtitle: Text(
                        '${entry.startTime.format(context)} - ${entry.endTime.format(context)}',
                      ),
                      trailing: IconButton(
                        onPressed: () {
                          widget.scheduleStore.deleteEntryById(entry.id);
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
              if (widget.onFinish != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: widget.onFinish,
                    child: const Text('Finish setup'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddWeeklyEntryDialog(BuildContext context) async {
    final titleController = TextEditingController();
    final now = TimeOfDay.now();
    var startTime = TimeOfDay(hour: now.hour, minute: 0);
    var endTime = TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Add fixed slot • ${_weekdayLabel(_selectedWeekday)}'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: 'Task name'),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start time'),
                    trailing: Text(startTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                      );
                      if (picked == null) {
                        return;
                      }
                      setDialogState(() {
                        startTime = picked;
                        if (compareTimes(startTime, endTime) >= 0) {
                          endTime = TimeOfDay(
                            hour: (startTime.hour + 1) % 24,
                            minute: startTime.minute,
                          );
                        }
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End time'),
                    trailing: Text(endTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: endTime,
                      );
                      if (picked == null) {
                        return;
                      }
                      setDialogState(() {
                        endTime = picked;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a task name.')),
                  );
                  return;
                }
                if (compareTimes(startTime, endTime) >= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('End time must be after start time.')),
                  );
                  return;
                }

                widget.scheduleStore.addWeeklyEntry(
                  weekday: _selectedWeekday,
                  title: title,
                  startTime: startTime,
                  endTime: endTime,
                );
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  String _weekdayLabel(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({
    required this.selectedWeekday,
    required this.onChanged,
  });

  final int selectedWeekday;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List<Widget>.generate(days.length, (index) {
        final weekday = index + 1;
        final selected = weekday == selectedWeekday;
        return ChoiceChip(
          label: Text(days[index]),
          selected: selected,
          onSelected: (_) => onChanged(weekday),
        );
      }),
    );
  }
}
