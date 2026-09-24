import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../shared/widgets/soft_blob.dart';

/// Asks Firebase to email a password-reset link.
///
/// A screen rather than a dialog because it has two distinct states — the form
/// and the confirmation — and the confirmation has something to say. A dialog
/// that swaps its own contents mid-flight reads as a glitch.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// Carried over from the login form, so the user is not made to retype the
  /// address they just typed.
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final TextEditingController _emailController;

  bool _isSending = false;
  bool _sent = false;
  String? _errorMessage;

  /// Held separately from the controller so the confirmation keeps naming the
  /// address the link actually went to, even if the field is edited after.
  String _sentTo = '';

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentTo = email;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extendBodyBehindAppBar: true,
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
              bottom: -140,
              right: -80,
              child: SoftBlob(
                size: 240,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _sent
                    ? _buildConfirmation(theme, muted)
                    : _buildForm(theme, muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, Color muted) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset password',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "Enter your email and we'll send you a link to set a new password.",
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofocus: widget.initialEmail.isEmpty,
            onFieldSubmitted: (_) => _send(),
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!value.contains('@')) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            height: 52,
            child: _isSending
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _send,
                    child: const Text('Send reset link'),
                  ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isSending ? null : () => Navigator.of(context).pop(),
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation(ThemeData theme, Color muted) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Check your inbox',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        // Deliberately conditional: "if an account exists". Confirming that
        // this address is registered would let anyone use this screen to test
        // whether a given person has an account here.
        Text(
          'If an account exists for $_sentTo, a link to set a new password '
          'is on its way. It expires after an hour, so use it soon.',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          "Nothing arrived? Check your spam folder, or try again with a "
          'different address.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to login'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _sent = false;
            _errorMessage = null;
          }),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
