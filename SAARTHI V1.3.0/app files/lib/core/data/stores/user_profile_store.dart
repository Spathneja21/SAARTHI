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
}
