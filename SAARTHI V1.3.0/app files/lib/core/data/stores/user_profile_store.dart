import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

class UserProfileStore {
  static const String _nameKey = 'user_name_v1';
  static const String _taskKey = 'user_primary_task_v1';
  static const String _onboardingKey = 'user_onboarding_complete_v1';

  Future<UserProfile> load() async {
    final preferences = await SharedPreferences.getInstance();
    return UserProfile(
      name: preferences.getString(_nameKey) ?? '',
      primaryTask: preferences.getString(_taskKey) ?? '',
      isOnboardingComplete: preferences.getBool(_onboardingKey) ?? false,
    );
  }

  Future<void> save(UserProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, profile.name);
    await preferences.setString(_taskKey, profile.primaryTask);
    await preferences.setBool(_onboardingKey, profile.isOnboardingComplete);
  }

  /// Wipe the cached profile. Must be called on sign-out.
  ///
  /// These keys are not namespaced by user, and sign-out used to leave them
  /// untouched. The result was a real data leak: signing in as a different
  /// account on the same device showed the previous person's name and, because
  /// `isOnboardingComplete` was still true, skipped onboarding entirely and
  /// dropped the new user straight into a home screen labelled with someone
  /// else's name.
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_nameKey);
    await preferences.remove(_taskKey);
    await preferences.remove(_onboardingKey);
  }
}
