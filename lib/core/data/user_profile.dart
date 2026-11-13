import 'package:flutter/foundation.dart';

/// User identity, onboarding completion, preferences, and baseline gate state.
///
/// Mirrors the 11 fields from `UserProfileStore.kt`.
@immutable
class UserProfile {
  const UserProfile({
    this.isLoggedIn = false,
    this.onboardingCompleted = false,
    this.name = 'Alex Parker',
    this.email = 'alex@example.com',
    this.ageGroup = '25–34',
    this.primaryGoal = 'Daily Clarity & Focus',
    this.devicePreference = 'Wireless Earbuds / Headphones',
    this.initialScreeningCompleted = false,
    this.notificationsEnabled = true,
    this.micPermissionGranted = false,
    this.healthNoticeAccepted = false,
  });

  final bool isLoggedIn;
  final bool onboardingCompleted;
  final String name;
  final String email;
  final String ageGroup;
  final String primaryGoal;
  final String devicePreference;
  final bool initialScreeningCompleted;
  final bool notificationsEnabled;
  final bool micPermissionGranted;
  final bool healthNoticeAccepted;

  UserProfile copyWith({
    bool? isLoggedIn,
    bool? onboardingCompleted,
    String? name,
    String? email,
    String? ageGroup,
    String? primaryGoal,
    String? devicePreference,
    bool? initialScreeningCompleted,
    bool? notificationsEnabled,
    bool? micPermissionGranted,
    bool? healthNoticeAccepted,
  }) {
    return UserProfile(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      name: name ?? this.name,
      email: email ?? this.email,
      ageGroup: ageGroup ?? this.ageGroup,
      primaryGoal: primaryGoal ?? this.primaryGoal,
      devicePreference: devicePreference ?? this.devicePreference,
      initialScreeningCompleted:
          initialScreeningCompleted ?? this.initialScreeningCompleted,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      micPermissionGranted: micPermissionGranted ?? this.micPermissionGranted,
      healthNoticeAccepted: healthNoticeAccepted ?? this.healthNoticeAccepted,
    );
  }

  Map<String, dynamic> toJson() => {
    'isLoggedIn': isLoggedIn,
    'onboardingCompleted': onboardingCompleted,
    'name': name,
    'email': email,
    'ageGroup': ageGroup,
    'primaryGoal': primaryGoal,
    'devicePreference': devicePreference,
    'initialScreeningCompleted': initialScreeningCompleted,
    'notificationsEnabled': notificationsEnabled,
    'micPermissionGranted': micPermissionGranted,
    'healthNoticeAccepted': healthNoticeAccepted,
  };
}

