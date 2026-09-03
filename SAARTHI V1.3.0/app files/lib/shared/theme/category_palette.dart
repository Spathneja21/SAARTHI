import 'package:flutter/material.dart';

import '../../core/api/dto/task_dto.dart';

/// Accent colours for task categories.
///
/// Drawn from Apple's system palette so they sit naturally next to the app's
/// existing Oceanic Blue (`#007AFF`, itself iOS system blue) rather than
/// introducing a second visual language. Deep work keeps the primary blue,
/// which makes it read as the default kind of work.
///
/// Used only as a thin accent on a surface-coloured block, never as a large
/// fill — fixed commitments own the solid blue blocks, and the distinction
/// between "immovable" and "the scheduler put this here" has to stay obvious at
/// a glance.
abstract final class CategoryPalette {
  static const Map<TaskCategory, Color> _light = {
    TaskCategory.deepWork: Color(0xFF007AFF), // system blue
    TaskCategory.learning: Color(0xFF5E5CE6), // system indigo
    TaskCategory.meeting: Color(0xFFFF9500), // system orange
    TaskCategory.personal: Color(0xFF34C759), // system green
    TaskCategory.health: Color(0xFFFF375F), // system pink
    TaskCategory.admin: Color(0xFF8E8E93), // system gray
  };

  /// Slightly brighter variants, matching how the theme lifts primary from
  /// `#007AFF` to `#0A84FF` in dark mode so colours keep their punch on black.
  static const Map<TaskCategory, Color> _dark = {
    TaskCategory.deepWork: Color(0xFF0A84FF),
    TaskCategory.learning: Color(0xFF7D7AFF),
    TaskCategory.meeting: Color(0xFFFF9F0A),
    TaskCategory.personal: Color(0xFF30D158),
    TaskCategory.health: Color(0xFFFF375F),
    TaskCategory.admin: Color(0xFF98989D),
  };

  static Color of(BuildContext context, TaskCategory category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final map = isDark ? _dark : _light;
    return map[category] ?? Theme.of(context).colorScheme.primary;
  }

  /// A small glyph per category, for compact blocks where the label is elided.
  static IconData iconOf(TaskCategory category) {
    switch (category) {
      case TaskCategory.deepWork:
        return Icons.center_focus_strong_outlined;
      case TaskCategory.learning:
        return Icons.school_outlined;
      case TaskCategory.meeting:
        return Icons.groups_outlined;
      case TaskCategory.personal:
        return Icons.person_outline;
      case TaskCategory.health:
        return Icons.favorite_outline;
      case TaskCategory.admin:
        return Icons.inbox_outlined;
    }
  }
}
