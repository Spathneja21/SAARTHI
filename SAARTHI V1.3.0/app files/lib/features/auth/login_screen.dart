import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../shared/widgets/soft_blob.dart';
import '../splash/splash_screen.dart';
import 'signup_success_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoginMode = true; // Toggle between Login and Sign Up
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1. Validate form (checks if fields are empty)
    if (!_formKey.currentState!.validate()) return;

    // 2. Clear previous errors and show loading spinner
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      // 3. Call our AuthService
      if (_isLoginMode) {
        await _authService.signInWithEmailPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );
        
        if (mounted) {
          // Go to splash screen to route to home or onboarding
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SplashScreen()),
          );
        }
      } else {
        await _authService.signUpWithEmailPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );
        
        // Sign out so they have to log in manually as requested
        await _authService.signOut();
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SignupSuccessScreen()),
          );
        }
      }

    } catch (e) {
      // 4. If error (wrong password, etc), show the message
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      // 5. Hide loading spinner whether it succeeded or failed
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _errorMessage = null; // Clear errors when switching modes
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);

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
              bottom: -140,
              right: -80,
              child: SoftBlob(
                size: 240,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- HEADER ---
                      Text(
                        _isLoginMode ? 'Welcome Back' : 'Create Account',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLoginMode
                            ? 'Enter your details to continue'
                            : 'Sign up to start scheduling smarter',
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),

                      // --- EMAIL FIELD ---
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // --- PASSWORD FIELD ---
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true, // Hides the password dots
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(), // Submit on keyboard enter
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (!_isLoginMode && value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // --- ERROR MESSAGE (Only shows if there's an error) ---
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24.0),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      // --- SUBMIT BUTTON ---
                      SizedBox(
                        height: 52,
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _submit,
                                child: Text(_isLoginMode ? 'Login' : 'Sign Up'),
                              ),
                      ),
                      const SizedBox(height: 8),

                      // --- TOGGLE MODE BUTTON ---
                      TextButton(
                        onPressed: _isLoading ? null : _toggleMode,
                        child: Text(
                          _isLoginMode
                              ? "Don't have an account? Sign Up"
                              : "Already have an account? Login",
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
