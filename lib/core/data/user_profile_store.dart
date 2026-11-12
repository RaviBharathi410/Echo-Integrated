import 'dart:async';

import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/data/user_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences provider overridden cleanly in widget tests if needed.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a real or mock SharedPreferences instance.',
  );
});

class UserProfileNotifier extends Notifier<UserProfile> {
  static const _prefix = 'echo.user.';
  static const _migratedFlag = 'echo.legacy_user_migrated';

  @override
  UserProfile build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final coordinator = ref.watch(audioCoordinatorProvider);
    final initial = _readFromPrefs(prefs);
    if (!(prefs.getBool(_migratedFlag) ?? false)) {
      unawaited(_importLegacyOnce(prefs, coordinator));
    }
    return initial;
  }

  UserProfile _readFromPrefs(SharedPreferences prefs) {
    return UserProfile(
      isLoggedIn: prefs.getBool('${_prefix}is_logged_in') ?? false,
      onboardingCompleted:
          prefs.getBool('${_prefix}onboarding_completed') ?? false,
      name: prefs.getString('${_prefix}user_name') ?? 'Alex Parker',
      email: prefs.getString('${_prefix}user_email') ?? 'alex@example.com',
      ageGroup: prefs.getString('${_prefix}age_group') ?? '25–34',
      primaryGoal:
          prefs.getString('${_prefix}primary_goal') ?? 'Daily Clarity & Focus',
      devicePreference:
          prefs.getString('${_prefix}device_pref') ??
          'Wireless Earbuds / Headphones',
      initialScreeningCompleted:
          prefs.getBool('${_prefix}initial_screening_completed') ?? false,
      notificationsEnabled:
          prefs.getBool('${_prefix}notifications_enabled') ?? true,
      micPermissionGranted:
          prefs.getBool('${_prefix}mic_granted') ?? false,
      healthNoticeAccepted:
          prefs.getBool('${_prefix}health_notice_accepted') ?? false,
    );
  }

  Future<void> _importLegacyOnce(
    SharedPreferences prefs,
    AudioSessionCoordinator coordinator,
  ) async {
    try {
      final allLegacy = await coordinator.readLegacyPrefs();
      final legacy = allLegacy['echo_user_profile'];
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setBool(
          '${_prefix}is_logged_in',
          (legacy['is_logged_in'] as bool?) ?? false,
        );
        await prefs.setBool(
          '${_prefix}onboarding_completed',
          (legacy['onboarding_completed'] as bool?) ?? false,
        );
        await prefs.setString(
          '${_prefix}user_name',
          (legacy['user_name'] as String?) ?? 'Alex Parker',
        );
        await prefs.setString(
          '${_prefix}user_email',
          (legacy['user_email'] as String?) ?? 'alex@example.com',
        );
        await prefs.setString(
          '${_prefix}age_group',
          (legacy['age_group'] as String?) ?? '25–34',
        );
        await prefs.setString(
          '${_prefix}primary_goal',
          (legacy['primary_goal'] as String?) ?? 'Daily Clarity & Focus',
        );
        await prefs.setString(
          '${_prefix}device_pref',
          (legacy['device_pref'] as String?) ?? 'Wireless Earbuds / Headphones',
        );
        await prefs.setBool(
          '${_prefix}initial_screening_completed',
          (legacy['initial_screening_completed'] as bool?) ?? false,
        );
        await prefs.setBool(
          '${_prefix}notifications_enabled',
          (legacy['notifications_enabled'] as bool?) ?? true,
        );
        await prefs.setBool(
          '${_prefix}mic_granted',
          (legacy['mic_granted'] as bool?) ?? false,
        );
        await prefs.setBool(
          '${_prefix}health_notice_accepted',
          (legacy['health_notice_accepted'] as bool?) ?? false,
        );
        state = _readFromPrefs(prefs);
      }
      await prefs.setBool(_migratedFlag, true);
    } catch (_) {
      // Ignore bridge unavailability during tests / cold desktop targets.
    }
  }

  Future<void> _persist(UserProfile next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool('${_prefix}is_logged_in', next.isLoggedIn);
    await prefs.setBool(
      '${_prefix}onboarding_completed',
      next.onboardingCompleted,
    );
    await prefs.setString('${_prefix}user_name', next.name);
    await prefs.setString('${_prefix}user_email', next.email);
    await prefs.setString('${_prefix}age_group', next.ageGroup);
    await prefs.setString('${_prefix}primary_goal', next.primaryGoal);
    await prefs.setString('${_prefix}device_pref', next.devicePreference);
    await prefs.setBool(
      '${_prefix}initial_screening_completed',
      next.initialScreeningCompleted,
    );
    await prefs.setBool(
      '${_prefix}notifications_enabled',
      next.notificationsEnabled,
    );
    await prefs.setBool('${_prefix}mic_granted', next.micPermissionGranted);
    await prefs.setBool(
      '${_prefix}health_notice_accepted',
      next.healthNoticeAccepted,
    );
  }

  Future<void> saveAccount({
    required String name,
    required String email,
  }) async {
    final trimmedName = name.trim().isEmpty ? state.name : name.trim();
    final trimmedEmail = email.trim().isEmpty ? state.email : email.trim();
    await _persist(
      state.copyWith(
        isLoggedIn: true,
        name: trimmedName,
        email: trimmedEmail,
      ),
    );
  }

  Future<void> updateProfile({
    String? name,
    String? ageGroup,
    String? primaryGoal,
    String? devicePreference,
  }) async {
    await _persist(
      state.copyWith(
        name: name?.trim().isNotEmpty == true ? name!.trim() : state.name,
        ageGroup: ageGroup ?? state.ageGroup,
        primaryGoal: primaryGoal ?? state.primaryGoal,
        devicePreference: devicePreference ?? state.devicePreference,
      ),
    );
  }

  Future<void> acceptHealthNotice() async {
    await _persist(state.copyWith(healthNoticeAccepted: true));
  }

  Future<void> updatePermissions({
    bool? micGranted,
    bool? notificationsEnabled,
  }) async {
    await _persist(
      state.copyWith(
        micPermissionGranted: micGranted ?? state.micPermissionGranted,
        notificationsEnabled:
            notificationsEnabled ?? state.notificationsEnabled,
      ),
    );
  }

  Future<void> completeOnboarding() async {
    await _persist(state.copyWith(onboardingCompleted: true));
  }

  Future<void> markInitialScreeningCompleted() async {
    await _persist(
      state.copyWith(
        initialScreeningCompleted: true,
        onboardingCompleted: true,
      ),
    );
  }

  Future<void> signOut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    for (final k in [
      'is_logged_in',
      'onboarding_completed',
      'user_name',
      'user_email',
      'age_group',
      'primary_goal',
      'device_pref',
      'initial_screening_completed',
      'notifications_enabled',
      'mic_granted',
      'health_notice_accepted',
    ]) {
      await prefs.remove('$_prefix$k');
    }
    state = const UserProfile();
  }
}

final userProfileProvider =
    NotifierProvider<UserProfileNotifier, UserProfile>(UserProfileNotifier.new);
