import 'package:flutter/material.dart';

import '../../core/data/models/user_profile.dart';
import '../../core/data/stores/user_profile_store.dart';
import '../../core/services/auth_service.dart';
import '../../shared/widgets/soft_blob.dart';
import '../home/home_screen.dart';
import 'pages/name_page.dart';

/// Asks for the name, and only the name.
///
/// Reached by an account that has already been through onboarding — its fixed
/// weekly schedule is on the server, which is how we know — but whose name is
/// nowhere to be found. That is every account created before the name moved
/// onto the Firebase profile: it lived only in `SharedPreferences`, which
/// sign-out deliberately wipes, so there is nothing left to restore.
///
/// Sending those users back through the full flow would make them rebuild a
/// weekly schedule they already have. Asking the one question whose answer is
/// genuinely missing costs a single screen, and the account carries it from
/// then on.
class NameCaptureScreen extends StatefulWidget {
  const NameCaptureScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<NameCaptureScreen> createState() => _NameCaptureScreenState();
}

class _NameCaptureScreenState extends State<NameCaptureScreen> {
  final TextEditingController _nameController = TextEditingController();
  final UserProfileStore _profileStore = UserProfileStore();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Optional positional argument so this can serve both the button and the
  /// text field's `onSubmitted`, which hands over the submitted text.
  Future<void> _save([String? _]) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Please enter your name.')),
        );
      return;
    }
    setState(() => _saving = true);

    final profile = UserProfile(
      name: name,
      primaryTask: widget.profile.primaryTask,
      isOnboardingComplete: true,
    );
    // The account first — that is the copy that has to survive the next
    // sign-out. The local save is only a cache for the offline path.
    await AuthService().updateDisplayName(name);
    await _profileStore.save(profile);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -120,
              left: -80,
              child: SoftBlob(
                size: 220,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -80,
              child: SoftBlob(
                size: 240,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: NamePage(
                    controller: _nameController,
                    onSubmitted: _save,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
                    ),
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
