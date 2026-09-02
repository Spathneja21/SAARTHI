import 'package:flutter/material.dart';

import '../../core/data/stores/user_profile_store.dart';
import '../../core/services/auth_service.dart';
import '../auth/login_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_flow.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final UserProfileStore _profileStore = UserProfileStore();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          _navigateToNextScreen();
        }
      });
    _controller.forward();
  }

  Future<void> _navigateToNextScreen() async {
    final user = AuthService().currentUser;

    if (!mounted) {
      return;
    }

    if (user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final profile = await _profileStore.load();
    if (!mounted) {
      return;
    }

    if (profile.isOnboardingComplete) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingFlow()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final barWidth =
                (constraints.maxWidth - 64).clamp(220.0, 360.0);

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'S.A.A.R.T.H.I',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                letterSpacing: 3,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              width: barWidth,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE9E1D2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            Container(
                              width: barWidth * _controller.value,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
