import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/statemachine/session_state_machine.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> createContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final stimulus = FakeStimulusEngine();
    final noise = FakeNoiseMonitor();
    final detector = FakeDeviceCapabilityManager();
    final monitor = FakeLiveMonitorEngine();
    final coordinator = FakeAudioSessionCoordinator(
      stimulusEngine: stimulus,
      noiseMonitor: noise,
      liveMonitorEngine: monitor,
    );
    final repo = InMemorySessionRepository();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioCoordinatorProvider.overrideWithValue(coordinator),
        stimulusEngineProvider.overrideWithValue(stimulus),
        noiseMonitorProvider.overrideWithValue(noise),
        screeningDeviceDetectorProvider.overrideWithValue(detector),
        liveMonitorEngineProvider.overrideWithValue(monitor),
        sessionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(() {
      stimulus.dispose();
      noise.dispose();
      detector.dispose();
      monitor.dispose();
      container.dispose();
    });
    return container;
  }

  test('init transitions state to ONBOARDING_CONSENT', () async {
    final container = await createContainer();
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.onboardingConsent,
    );
  });

  test('onConsentAgreed does not throw when called from ONBOARDING_CONSENT', () async {
    final container = await createContainer();
    container.read(screeningNotifierProvider.notifier).onConsentAgreed(true);
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.deviceReadiness,
    );
  });

  test('declined consent transitions to ABORTED', () async {
    final container = await createContainer();
    container.read(screeningNotifierProvider.notifier).onConsentAgreed(false);
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.aborted,
    );
  });

  test('onConsentAgreed is safe to call multiple times', () async {
    final container = await createContainer();
    final notifier = container.read(screeningNotifierProvider.notifier);
    notifier.onConsentAgreed(true);
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.deviceReadiness,
    );
    notifier.onConsentAgreed(true);
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.deviceReadiness,
    );
  });

  test('restart then re-consent does not crash', () async {
    final container = await createContainer();
    final notifier = container.read(screeningNotifierProvider.notifier);
    notifier.onConsentAgreed(true);
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.deviceReadiness,
    );

    notifier.onRestartRequested();
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.onboardingConsent,
    );

    notifier.onConsentAgreed(true);
    expect(
      container.read(screeningNotifierProvider).sessionState,
      SessionState.deviceReadiness,
    );
  });

  test('onMicrophonePermissionResult granted refreshes device route', () async {
    final container = await createContainer();
    final notifier = container.read(screeningNotifierProvider.notifier);
    notifier.onConsentAgreed(true);
    await notifier.onMicrophonePermissionResult(granted: true);
    expect(container.read(screeningNotifierProvider).audioRoute, isNotNull);
  });

  test('onMicrophonePermissionResult denied sets noise to UNAVAILABLE', () async {
    final container = await createContainer();
    final notifier = container.read(screeningNotifierProvider.notifier);
    notifier.onConsentAgreed(true);
    await notifier.onMicrophonePermissionResult(granted: false);
    expect(
      container.read(screeningNotifierProvider).noiseReading.assessment,
      NoiseAssessment.unavailable,
    );
  });
}

