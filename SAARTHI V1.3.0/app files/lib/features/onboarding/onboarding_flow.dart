import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/models/user_profile.dart';
import '../../core/data/stores/schedule_store.dart';
import '../../core/data/stores/user_profile_store.dart';
import '../../shared/widgets/page_dots.dart';
import '../../shared/widgets/soft_blob.dart';
import 'onboarding_complete_screen.dart';
import 'pages/intro_page.dart';
import 'pages/name_page.dart';
import 'pages/start_page.dart';
import 'pages/weekly_setup_page.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  // Pages that carry no required input auto-advance on their own after a
  // short pause so the user isn't forced to tap the arrow every time.
  static const Set<int> _autoAdvancePages = {1, 2};
  static const Duration _autoAdvanceDelay = Duration(milliseconds: 2400);
  static const Duration _pageTransitionDuration = Duration(milliseconds: 520);
  static const Curve _pageTransitionCurve = Curves.easeInOutCubic;

  final PageController _controller = PageController();
  final TextEditingController _nameController = TextEditingController();
  final ScheduleStore _scheduleStore = ScheduleStore();
  final UserProfileStore _profileStore = UserProfileStore();
  int _pageIndex = 0;
  Timer? _autoAdvanceTimer;

  @override
  void initState() {
    super.initState();
    _scheduleStore.load();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _scheduleAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (!_autoAdvancePages.contains(_pageIndex)) {
      return;
    }
    _autoAdvanceTimer = Timer(_autoAdvanceDelay, () {
      if (mounted && _pageIndex < 3) {
        _goNext();
      }
    });
  }

  void _handleNameSubmitted(String _) {
    _goNext();
  }

  void _goNext() {
    if (_pageIndex == 0 && _nameController.text.trim().isEmpty) {
      _showMessage('Please enter your name to continue.');
      return;
    }

    if (_pageIndex < 3) {
      _autoAdvanceTimer?.cancel();
      _controller.nextPage(
        duration: _pageTransitionDuration,
        curve: _pageTransitionCurve,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      _showMessage('Please enter your name.');
      _controller.animateToPage(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }

    if (!_scheduleStore.hasAnyWeeklyEntry()) {
      _showMessage('Please add at least one fixed weekly slot.');
      return;
    }

    final profile = UserProfile(
      name: name,
      primaryTask: '',
      isOnboardingComplete: true,
    );
    await _profileStore.save(profile);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OnboardingCompleteScreen(profile: profile),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _blended(int index, Widget child) {
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, child) {
        var page = _pageIndex.toDouble();
        if (_controller.hasClients && _controller.position.haveDimensions) {
          page = _controller.page ?? page;
        }
        final delta = (page - index).clamp(-1.0, 1.0);
        final opacity = (1 - delta.abs()).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(delta * 32, 0),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -120,
              left: -80,
              child: SoftBlob(
                size: 220,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -80,
              child: SoftBlob(
                size: 240,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            Column(
              children: [
                const SizedBox(height: 16),
                PageDots(current: _pageIndex, count: 4),
                const SizedBox(height: 12),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (value) {
                      setState(() {
                        _pageIndex = value;
                      });
                      _scheduleAutoAdvance();
                    },
                    children: [
                      _blended(0, NamePage(
                        controller: _nameController,
                        onSubmitted: _handleNameSubmitted,
                      )),
                      _blended(1, IntroPage(nameListenable: _nameController)),
                      _blended(2, const StartPage()),
                      _blended(
                        3,
                        WeeklySetupPage(
                          scheduleStore: _scheduleStore,
                          onFinish: _finishOnboarding,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
