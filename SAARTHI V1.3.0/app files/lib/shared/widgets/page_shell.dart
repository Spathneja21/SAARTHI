import 'package:flutter/material.dart';

class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.title,
    required this.child,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.titleAlignment,
    this.titleTextAlign,
    this.titleStyle,
    this.titleWidget,
    this.childAlignment,
  });

  final String title;
  final Widget child;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final Alignment? titleAlignment;
  final TextAlign? titleTextAlign;
  final TextStyle? titleStyle;
  final Widget? titleWidget;
  final Alignment? childAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = (constraints.maxHeight - 48).clamp(0.0, double.infinity);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Column(
              mainAxisAlignment: mainAxisAlignment,
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Align(
                  alignment: titleAlignment ?? Alignment.centerLeft,
                  child: titleWidget ??
                      Text(
                        title,
                        textAlign: titleTextAlign,
                        style: titleStyle ?? Theme.of(context).textTheme.displaySmall,
                      ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: childAlignment ?? Alignment.centerLeft,
                  child: child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
