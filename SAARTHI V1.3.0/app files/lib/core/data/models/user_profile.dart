class UserProfile {
  const UserProfile({
    required this.name,
    required this.primaryTask,
    required this.isOnboardingComplete,
  });

  final String name;
  final String primaryTask;
  final bool isOnboardingComplete;

  static const empty = UserProfile(
    name: '',
    primaryTask: '',
    isOnboardingComplete: false,
  );
}
