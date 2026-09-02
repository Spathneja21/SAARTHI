import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/data/models/user_profile.dart';
import '../../core/data/stores/user_profile_store.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/morphing_sparkle.dart';
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
  static const List<String> _words = [
    'Planning',
    'Focus',
    'Discipline',
    'Momentum',
    'Balance',
    'Priorities',
    'SAARTHI',
    'Consistency',
    'Clarity',
    'Progress',
    'Growth',
  ];
  static const Duration _totalDuration = Duration(milliseconds: 6000);
  static const double _sparkleSize = 240;
  // Matches the current-time marker color on the Timeline for brand consistency.
  static const Color _nowMarkerColor = Color(0xFFFF8FA3);

  final UserProfileStore _profileStore = UserProfileStore();
  late final AnimationController _controller;

  bool _readyToNavigate = false;
  User? _pendingUser;
  UserProfile? _pendingProfile;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration)
      ..addStatusListener(_handleLapCompleted);
    _controller.forward();
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    final user = AuthService().currentUser;
    UserProfile? profile;
    if (user != null) {
      profile = await _profileStore.load();
    }
    _pendingUser = user;
    _pendingProfile = profile;
    _readyToNavigate = true;
  }

  void _handleLapCompleted(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    if (_readyToNavigate) {
      _navigate();
    } else {
      // Data isn't ready yet: let the word wall run through another full lap
      // rather than cutting the animation off mid-way.
      _controller.forward(from: 0);
    }
  }

  void _navigate() {
    if (!mounted) {
      return;
    }

    final user = _pendingUser;
    final profile = _pendingProfile;

    if (user == null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    if (profile!.isOnboardingComplete) {
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
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const lineHeightFactor = 1.06;
              final fontSize =
                  (constraints.maxHeight / _words.length / lineHeightFactor)
                      .clamp(22.0, 44.0);
              final lineHeight = fontSize * lineHeightFactor;
              final listHeight = lineHeight * _words.length;
              final topInset = ((constraints.maxHeight - listHeight) / 2).clamp(
                0.0,
                double.infinity,
              );

              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final t = _controller.value;
                  final activeIndex = (t * _words.length).floor().clamp(
                    0,
                    _words.length - 1,
                  );
                  final sparkleCenterY = topInset + t * listHeight;

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: sparkleCenterY - _sparkleSize / 2,
                        child: Center(
                          child: MorphingSparkle(
                            progress: t,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.16,
                            ),
                            size: _sparkleSize,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: topInset,
                        child: Column(
                          children: [
                            for (var i = 0; i < _words.length; i++)
                              SizedBox(
                                height: lineHeight,
                                width: double.infinity,
                                child: Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOut,
                                    style: TextStyle(
                                      fontFamily: theme
                                          .textTheme
                                          .displaySmall
                                          ?.fontFamily,
                                      fontSize: fontSize,
                                      height: 1.0,
                                      fontWeight: i == activeIndex
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: _words[i] == 'SAARTHI'
                                          ? (i == activeIndex
                                                ? _nowMarkerColor
                                                : _nowMarkerColor.withValues(
                                                    alpha: 0.2,
                                                  ))
                                          : (i == activeIndex
                                                ? theme.colorScheme.onSurface
                                                : theme.colorScheme.primary
                                                      .withValues(alpha: 0.2)),
                                    ),
                                    child: Text(_words[i]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
