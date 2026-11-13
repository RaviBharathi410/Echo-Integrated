import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/statemachine/session_state_machine.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<
    ({
      ProviderContainer container,
      FakeNoiseMonitor noise,
      FakeDeviceCapabilityManager detector,
      FakeStimulusEngine stimulus,
    })
  >
  setupScreening() async {
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
    // Ensure initial refreshDeviceRoute finishes cleanly.
    await container.read(screeningNotifierProvider.notifier).refreshDeviceRoute();
    return (
      container: container,
      noise: noise,
      detector: detector,
      stimulus: stimulus,
    );
  }

  test(
    'cancelling screening and tapping Try Again returns to setup preserving consent',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.deviceReadiness,
      );
      expect(
        ctx.container.read(screeningNotifierProvider).hasUserConsented,
        isTrue,
      );

      ctx.noise.injectAssessment(NoiseAssessment.valid, -62.0);
      await pumpEventQueue();
      notifier.onDevicePrecheckContinue();
      notifier.onStartScreening();

      notifier.onCancelRequested();
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.cancelled,
      );
      expect(
        ctx.container.read(screeningNotifierProvider).cancelReason,
        'Screening was cancelled by the user.',
      );
      expect(
        ctx.container.read(screeningNotifierProvider).hasUserConsented,
        isTrue,
      );

      notifier.onTryAgain();
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.deviceReadiness,
      );
      expect(
        ctx.container.read(screeningNotifierProvider).hasUserConsented,
        isTrue,
      );
    },
  );

  test(
    'full restart request resets consent and returns to consent onboarding',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      expect(
        ctx.container.read(screeningNotifierProvider).hasUserConsented,
        isTrue,
      );

      notifier.onRestartRequested();
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.onboardingConsent,
      );
      expect(
        ctx.container.read(screeningNotifierProvider).hasUserConsented,
        isFalse,
      );
    },
  );

  test('precheck continue is blocked when noise reading is UNAVAILABLE', () async {
    final ctx = await setupScreening();
    final notifier = ctx.container.read(screeningNotifierProvider.notifier);

    notifier.onConsentAgreed(true);
    ctx.noise.injectAssessment(NoiseAssessment.unavailable, -100.0);
    await pumpEventQueue();

    notifier.onDevicePrecheckContinue();

    final state = ctx.container.read(screeningNotifierProvider);
    expect(state.sessionState, SessionState.deviceReadiness);
    expect(state.pauseReason, contains('Microphone sensor unavailable'));
  });

  test('precheck continue is blocked when noise reading is INVALID (Too Loud)', () async {
    final ctx = await setupScreening();
    final notifier = ctx.container.read(screeningNotifierProvider.notifier);

    notifier.onConsentAgreed(true);
    ctx.noise.injectAssessment(NoiseAssessment.invalid, -35.0);
    await pumpEventQueue();

    notifier.onDevicePrecheckContinue();

    final state = ctx.container.read(screeningNotifierProvider);
    expect(state.sessionState, SessionState.deviceReadiness);
    expect(state.pauseReason, contains('Environment is too loud'));
  });

  test('precheck continue succeeds when headphones connected and noise is VALID', () async {
    final ctx = await setupScreening();
    final notifier = ctx.container.read(screeningNotifierProvider.notifier);

    notifier.onConsentAgreed(true);
    ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
    await pumpEventQueue();

    notifier.onDevicePrecheckContinue();

    final state = ctx.container.read(screeningNotifierProvider);
    expect(state.sessionState, SessionState.testPrep);
    expect(state.pauseReason, isNull);
  });

  test('precheck continue is blocked when built-in speaker is active', () async {
    final ctx = await setupScreening();
    final notifier = ctx.container.read(screeningNotifierProvider.notifier);

    ctx.detector.setSimulatedRoute(AudioRouteType.builtinSpeaker);
    await notifier.refreshDeviceRoute();
    notifier.onConsentAgreed(true);
    ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
    await pumpEventQueue();

    notifier.onDevicePrecheckContinue();

    final state = ctx.container.read(screeningNotifierProvider);
    expect(state.sessionState, SessionState.deviceReadiness);
    expect(state.pauseReason, contains('Headphones required'));
  });

  test(
    'practice round tone response HEARD sets practiceHeard true and enables start test',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
      await pumpEventQueue();
      notifier.onDevicePrecheckContinue();

      notifier.onStartPractice();
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.practicePresentation,
      );

      notifier.onPracticeHeardClicked();
      final state = ctx.container.read(screeningNotifierProvider);
      expect(state.sessionState, SessionState.practiceFeedback);
      expect(state.practiceHeard, isTrue);
      expect(state.practiceFeedbackMessage, contains('Demo tone heard'));
    },
  );

  test(
    'practice round tone response NOT HEARD sets practiceHeard false and warns user',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
      await pumpEventQueue();
      notifier.onDevicePrecheckContinue();

      notifier.onStartPractice();
      notifier.onPracticeNotHeardClicked();
      final state = ctx.container.read(screeningNotifierProvider);
      expect(state.sessionState, SessionState.practiceFeedback);
      expect(state.practiceHeard, isFalse);
      expect(
        state.practiceFeedbackMessage,
        contains('Demo tone reported not heard'),
      );
    },
  );

  test(
    'practice round timeout marks practice as not heard and stops tone',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
      await pumpEventQueue();
      notifier.onDevicePrecheckContinue();

      notifier.onStartPractice();
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.practicePresentation,
      );

      notifier.onPracticeTimedOut();
      final state = ctx.container.read(screeningNotifierProvider);
      expect(state.sessionState, SessionState.practiceFeedback);
      expect(state.practiceHeard, isFalse);
      expect(state.practiceTonePlaying, isFalse);
    },
  );

  testWidgets(
    'user responding I CANNOT HEAR IT records NOT_HEARD trial outcome and steps level up',
    (tester) async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
      await tester.pump();
      notifier.onDevicePrecheckContinue();
      notifier.selectStrategy(StrategyType.modifiedHughsonWestlake);
      notifier.onStartScreening();

      // Advance past 500-1200ms pre-stimulus jitter delay.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        ctx.container.read(screeningNotifierProvider).isWaitingForResponse,
        isTrue,
      );
      final initialLevel =
          ctx.container.read(screeningNotifierProvider).currentLevelDb;

      notifier.onUserNotHeardClicked();
      final state = ctx.container.read(screeningNotifierProvider);
      expect(state.trials.lastOrNull?.outcome, TrialOutcome.notHeard);
      expect(state.currentLevelDb, initialLevel + 5);

      // Flush pending 400ms next-trial timer cleanly before teardown.
      notifier.onCancelRequested();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'duplicate user response clicks are suppressed when not waiting for response',
    (tester) async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
      await tester.pump();
      notifier.onDevicePrecheckContinue();
      notifier.onStartScreening();

      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        ctx.container.read(screeningNotifierProvider).isWaitingForResponse,
        isTrue,
      );
      notifier.onUserHeardClicked();
      expect(
        ctx.container.read(screeningNotifierProvider).isWaitingForResponse,
        isFalse,
      );
      final trialsBefore =
          ctx.container.read(screeningNotifierProvider).trials.length;

      notifier.onUserHeardClicked();
      notifier.onUserNotHeardClicked();
      expect(
        ctx.container.read(screeningNotifierProvider).trials.length,
        trialsBefore,
      );

      notifier.onCancelRequested();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'noise disturbance during trial invalidates trial and pauses screening',
    (tester) async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      ctx.noise.injectAssessment(NoiseAssessment.valid, -65.0);
      await tester.pump();
      notifier.onDevicePrecheckContinue();
      notifier.onStartScreening();

      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        ctx.container.read(screeningNotifierProvider).isWaitingForResponse,
        isTrue,
      );

      ctx.noise.injectAssessment(NoiseAssessment.invalid, -35.0);
      await tester.pump();

      final state = ctx.container.read(screeningNotifierProvider);
      expect(state.sessionState, SessionState.automaticPauseNoise);
      expect(state.isNoisePaused, isTrue);
      expect(state.trials.lastOrNull?.outcome, TrialOutcome.contaminatedByNoise);

      notifier.onCancelRequested();
    },
  );

  test(
    'unplug simulation on setup screen swaps device route to speaker without teleporting to screening',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      expect(
        ctx.container.read(screeningNotifierProvider).sessionState,
        SessionState.deviceReadiness,
      );

      notifier.toggleSimulationMode();
      expect(
        ctx.container.read(screeningNotifierProvider).isSimulationMode,
        isTrue,
      );

      notifier.simulateDeviceDisconnect();
      await pumpEventQueue();

      final state = ctx.container.read(screeningNotifierProvider);
      expect(state.sessionState, SessionState.deviceReadiness);
      expect(state.isHeadphoneConnected, isFalse);
    },
  );

  test(
    'simulateNoiseSpike injects deterministic noise level into UI state when simulation is active',
    () async {
      final ctx = await setupScreening();
      final notifier = ctx.container.read(screeningNotifierProvider.notifier);

      notifier.onConsentAgreed(true);
      notifier.toggleSimulationMode();
      expect(
        ctx.container.read(screeningNotifierProvider).isSimulationMode,
        isTrue,
      );

      notifier.simulateNoiseSpike(NoiseAssessment.invalid);
      await pumpEventQueue();
      expect(
        ctx.container.read(screeningNotifierProvider).noiseReading.assessment,
        NoiseAssessment.invalid,
      );
      expect(
        ctx.container.read(screeningNotifierProvider).noiseReading.levelDbFs,
        closeTo(-25.0, 0.1),
      );

      notifier.simulateNoiseSpike(NoiseAssessment.valid);
      await pumpEventQueue();
      expect(
        ctx.container.read(screeningNotifierProvider).noiseReading.assessment,
        NoiseAssessment.valid,
      );
      expect(
        ctx.container.read(screeningNotifierProvider).noiseReading.levelDbFs,
        closeTo(-55.0, 0.1),
      );
    },
  );
}

