import 'package:flutter/material.dart';

import '../../../shared/widgets/page_shell.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Let\'s get you started.',
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      titleAlignment: Alignment.center,
      titleTextAlign: TextAlign.center,
      childAlignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 10),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyLarge,
              children: [
                const TextSpan(text: 'Upload your '),
                TextSpan(
                  text: 'Everyday',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: Theme.of( context).textTheme.bodyLarge?.fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const TextSpan(text: ' schedule in the next section.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
