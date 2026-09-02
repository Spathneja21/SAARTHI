import 'package:flutter/material.dart';

class PageDots extends StatelessWidget {
  const PageDots({super.key, required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 6,
          width: active ? 20 : 6,
          decoration: BoxDecoration(
            color: active ? scheme.primary : scheme.onSurface.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
        );
      }),
    );
  }
}
