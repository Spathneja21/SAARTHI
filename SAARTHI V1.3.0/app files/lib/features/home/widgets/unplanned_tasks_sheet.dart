import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/dto/task_dto.dart';
import '../../../shared/theme/category_palette.dart';

/// Tasks that exist but have no place in the day yet.
///
/// This screen has no equivalent in the old local-only app, and it is needed
/// precisely because the user no longer chooses a day. A task is created,
/// stored, and then sits here until "Plan my day" runs and CP-SAT decides where
/// it goes. Without somewhere to show them, freshly created tasks would simply
/// vanish until planning happened.
class UnplannedTasksSheet extends StatelessWidget {
  const UnplannedTasksSheet({
    super.key,
    required this.tasks,
    required this.onTaskTap,
    required this.onPlan,
    required this.isPlanning,
  });

  final List<TaskDto> tasks;
  final void Function(TaskDto task) onTaskTap;
  final VoidCallback onPlan;
  final bool isPlanning;

  static Future<void> show(
    BuildContext context, {
    required List<TaskDto> tasks,
    required void Function(TaskDto task) onTaskTap,
    required VoidCallback onPlan,
    required bool isPlanning,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => UnplannedTasksSheet(
        tasks: tasks,
        onTaskTap: onTaskTap,
        onPlan: onPlan,
        isPlanning: isPlanning,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Text('Unplanned', style: theme.textTheme.titleLarge),
                const SizedBox(width: 8),
                if (tasks.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tasks.isEmpty
                  ? 'Everything you have created has a time.'
                  : 'Waiting for a slot. Plan your day to place them.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),

            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 34,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.25),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Nothing waiting',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _UnplannedTile(task: tasks[i], onTap: onTaskTap),
                ),
              ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (tasks.isEmpty || isPlanning) ? null : onPlan,
                icon: isPlanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(isPlanning ? 'Planning…' : 'Plan my day'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnplannedTile extends StatelessWidget {
  const _UnplannedTile({required this.task, required this.onTap});

  final TaskDto task;
  final void Function(TaskDto task) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = CategoryPalette.of(context, task.category);
    final deadline = task.deadline;
    final isOverdue = deadline != null && deadline.isBefore(DateTime.now());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(task),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${task.category.label} · ${_durationLabel(task.estimatedDuration)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                        if (deadline != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· due ${DateFormat('MMM d').format(deadline)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isOverdue
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                              fontWeight:
                                  isOverdue ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _durationLabel(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
