import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns the currently signed-in user, or null if there is none.
  User? get currentUser => _auth.currentUser;

  /// Stream that notifies when the user signs in or out.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign up with email and password
  Future<UserCredential> signUpWithEmailPassword(
      String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmailPassword(
      String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Record the user's name on the Firebase account itself.
  ///
  /// The name has to outlive this device. It used to exist only in
  /// `SharedPreferences`, which sign-out deliberately wipes, so signing back in
  /// had nothing to restore and the app asked for it again. `displayName` is
  /// account state, so it survives sign-out, reinstalls and a second device.
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
    // The cached User is not refreshed by the write, so a read straight after
    // this would still see the old value.
    await user.reload();
  }

  /// Ask Firebase to email a password-reset link to [email].
  ///
  /// Deliberately reports nothing about whether the address belongs to an
  /// account. Firebase answers `user-not-found` for an unknown email, and
  /// passing that on would turn the reset screen into an account-enumeration
  /// oracle: anyone could try addresses against it and learn which ones are
  /// registered. So that one case is swallowed and the caller shows the same
  /// message either way.
  ///
  /// Everything the user can actually act on — a malformed address, no network,
  /// too many attempts — is still thrown.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return;
      throw _handleAuthException(e);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Helper to convert Firebase error codes into user-friendly messages
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'weak-password':
        return 'The password provided is too weak (min 6 characters).';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return e.message ?? 'An unknown authentication error occurred.';
    }
  }
}
