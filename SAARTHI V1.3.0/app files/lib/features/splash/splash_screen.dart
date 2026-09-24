import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/data/models/user_profile.dart';
import '../../core/data/stores/commitment_store.dart';
import '../../core/data/stores/user_profile_store.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/morphing_sparkle.dart';
import '../auth/login_screen.dart';
import '../home/home_screen.dart';
import '../onboarding/name_capture_screen.dart';
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

  /// Work out where this user belongs, from their *account* rather than from
  /// this device.
  ///
  /// Onboarding used to be gated on a `SharedPreferences` flag that sign-out
  /// wipes, so every returning user was marched back through it. Nothing about
  /// "I already set this up" belongs to a device — a reinstall or a second
  /// phone would have done the same thing.
  Future<void> _loadAuthState() async {
    // Read before the first await: this widget can be disposed mid-flight and
    // `context` must not be touched afterwards.
    final commitmentStore = context.read<CommitmentStore>();

    final user = AuthService().currentUser;
    if (user == null) {
      _pendingUser = null;
      _pendingProfile = null;
      _readyToNavigate = true;
      return;
    }

    final cached = await _profileStore.load();

    // Onboarding cannot finish without at least one fixed weekly slot, and
    // those are stored per account on the server. Their presence is therefore
    // a trustworthy answer to "has this login been through onboarding?" — and
    // one no amount of clearing local storage can lose.
    await commitmentStore.load();
    final onboarded = commitmentStore.error == null
        ? commitmentStore.hasAny
        // Offline or backend down: no answer available, so trust what this
        // device remembers rather than send a returning user back to setup.
        : cached.isOnboardingComplete;

    // Accounts created before the name moved onto Firebase still only have it
    // on the device. Carry it across once, so the next sign-out does not lose
    // it.
    var name = user.displayName ?? '';
    if (name.isEmpty && cached.name.isNotEmpty) {
      name = cached.name;
      await AuthService().updateDisplayName(name);
    }

    final profile = UserProfile(
      name: name,
      primaryTask: cached.primaryTask,
      isOnboardingComplete: onboarded,
    );
    // Keep the device copy in step, so it is a usable fallback next time the
    // server cannot be reached.
    if (onboarded) await _profileStore.save(profile);

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
      // Onboarded, but the name did not survive — an account from before it
      // moved onto the Firebase profile. Ask for that one thing rather than
      // the whole flow.
      if (profile.name.isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => NameCaptureScreen(profile: profile),
          ),
        );
        return;
      }
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
