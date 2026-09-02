import 'package:flutter/material.dart';

import '../../../shared/widgets/page_shell.dart';
import '../../../shared/widgets/typewriter_block.dart';

class NamePage extends StatelessWidget {
  const NamePage({super.key, required this.controller, this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: 34,
      fontWeight: FontWeight.w700,
    );
    final subtitleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600);
    final inputStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w500);

    return PageShell(
      title: 'Hello,',
      titleStyle: titleStyle,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      titleAlignment: Alignment.center,
      titleTextAlign: TextAlign.center,
      childAlignment: Alignment.center,
      titleWidget: TypewriterBlock(
        lines: const ['HI! There,', 'Tell us your name'],
        lineStyles: [titleStyle, subtitleStyle],
        textAlign: TextAlign.center,
        duration: const Duration(milliseconds: 1400),
        cursor: true,
        cursorAfterComplete: true,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            textAlign: TextAlign.center,
            style: inputStyle,
            textInputAction: TextInputAction.next,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: 'Your name',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
