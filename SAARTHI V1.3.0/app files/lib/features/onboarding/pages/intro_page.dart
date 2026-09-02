import 'package:flutter/material.dart';

import '../../../shared/widgets/page_shell.dart';

class IntroPage extends StatelessWidget {
  const IntroPage({super.key, required this.nameListenable});

  final TextEditingController nameListenable;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.w700,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          height: 1.6,
        );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: nameListenable,
      builder: (context, value, child) {
        final displayName = _displayName(value.text);
        return PageShell(
          title: 'Hello,$displayName',
          titleStyle: titleStyle,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          titleAlignment: Alignment.center,
          titleTextAlign: TextAlign.center,
          childAlignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text(
                'I am S.A.A.R.T.H.I.',
                style: bodyStyle?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Your friend/guide for your productive future.'
                'Let\'s begin, shall we?',
                style: bodyStyle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  String _displayName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'there';
    }
    return trimmed;
  }
}
