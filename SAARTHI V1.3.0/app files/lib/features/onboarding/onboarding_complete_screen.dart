import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/models/user_profile.dart';
import '../home/home_screen.dart';

class OnboardingCompleteScreen extends StatefulWidget {
  const OnboardingCompleteScreen({
    super.key,
    required this.profile,
  });

  final UserProfile profile;

  @override
  State<OnboardingCompleteScreen> createState() =>
      _OnboardingCompleteScreenState();
}

class _OnboardingCompleteScreenState extends State<OnboardingCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _timer = Timer(const Duration(milliseconds: 2200), _goToHome);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _goToHome() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(profile: widget.profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Now that I have your fixed schedule, lets get started',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity:
                      Tween<double>(begin: 0.35, end: 1).animate(_controller),
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
