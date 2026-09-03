import 'package:flutter/material.dart';

import '../../../core/api/dto/task_dto.dart';
import '../../../shared/theme/category_palette.dart';

/// What the user can do with a task, offered as a bottom sheet.
///
/// **Start** is here for a specific reason. `actualDuration` is only ever
/// recorded when a task genuinely passes through `in_progress` — the server
/// stamps `startedAt` on that transition and derives the duration from it at
/// completion. A done-checkbox on its own always yields a null duration, so
/// without a start action the behaviour profile's estimation-accuracy figures
/// would stay permanently empty and the app could never learn how badly the
/// user estimates.
///
/// **Un-complete is deliberately absent**: `completed` is terminal in the
/// server's state machine, with no transitions out of it.
enum TaskAction { start, complete, skip, postpone, delete, edit }

class TaskActionSheet extends StatelessWidget {
  const TaskActionSheet({
    super.key,
    required this.title,
    required this.category,
    required this.status,
    this.subtitle,
    this.estimatedDuration,
    this.showDelete = true,
  });

  final String title;
  final TaskCategory category;
  final TaskStatus status;
  final String? subtitle;
  final int? estimatedDuration;
  final bool showDelete;

  /// Presents the sheet and resolves to the chosen action, or null if dismissed.
  static Future<TaskAction?> show(
    BuildContext context, {
    required String title,
    required TaskCategory category,
    required TaskStatus status,
    String? subtitle,
    int? estimatedDuration,
    bool showDelete = true,
  }) {
    return showModalBottomSheet<TaskAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskActionSheet(
        title: title,
        category: category,
        status: status,
        subtitle: subtitle,
        estimatedDuration: estimatedDuration,
        showDelete: showDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = CategoryPalette.of(context, category);
    final isDone = status == TaskStatus.completed;
    final isRunning = status == TaskStatus.inProgress;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle, matching the app's soft iOS feel.
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(CategoryPalette.iconOf(category),
                      size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          category.label,
                          if (estimatedDuration != null)
                            _durationLabel(estimatedDuration!),
                          ?subtitle,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: status, accent: accent),
              ],
            ),
            const SizedBox(height: 18),

            if (isDone)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Completed tasks cannot be reopened.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              )
            else ...[
              if (!isRunning)
                _ActionTile(
                  icon: Icons.play_circle_outline,
                  label: 'Start working',
                  detail: 'Tracks how long this actually takes',
                  color: accent,
                  onTap: () => Navigator.pop(context, TaskAction.start),
                ),
              _ActionTile(
                icon: Icons.check_circle_outline,
                label: isRunning ? 'Finish' : 'Mark done',
                detail: isRunning ? null : 'Without timing it',
                color: accent,
                onTap: () => Navigator.pop(context, TaskAction.complete),
              ),
              _ActionTile(
                icon: Icons.schedule,
                label: 'Postpone',
                onTap: () => Navigator.pop(context, TaskAction.postpone),
              ),
              _ActionTile(
                icon: Icons.skip_next_outlined,
                label: 'Skip',
                onTap: () => Navigator.pop(context, TaskAction.skip),
              ),
            ],

            if (showDelete) ...[
              const Divider(height: 20),
              _ActionTile(
                icon: Icons.delete_outline,
                label: 'Delete task',
                color: theme.colorScheme.error,
                onTap: () => Navigator.pop(context, TaskAction.delete),
              ),
            ],
            const SizedBox(height: 4),
          ],
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.color,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tint,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.accent});

  final TaskStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}
