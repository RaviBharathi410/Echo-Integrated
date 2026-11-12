import 'dart:async';
import 'dart:math' as math;

import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/quality/trial_quality_controller.dart';
import 'package:echo_hearing/core/domain/statemachine/session_state_machine.dart';
import 'package:echo_hearing/core/domain/threshold/binary_search_strategy.dart';
import 'package:echo_hearing/core/domain/threshold/hughson_westlake_protocol.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

enum ScreeningSubScreen {
  mainFlow,
  history,
  compare,
  reminders,
  recordDetail,
}

@immutable
class ScreeningUiState {
  ScreeningUiState({
    required this.sessionId,
    required this.startedAt,
    this.sessionState = SessionState.onboardingConsent,
    this.hasUserConsented = false,
    this.selectedStrategy = StrategyType.modifiedHughsonWestlake,
    this.isExtendedFrequencyMode = false,
    this.currentEar = Ear.left,
    this.currentFrequencyHz = 1000,
    this.currentLevelDb = 40,
    this.trialNumber = 0,
    this.isTonePlaying = false,
    this.isWaitingForResponse = false,
    this.lastResponseLatencyMs,
    this.audioRoute,
    this.isHeadphoneConnected = false,
    NoiseReading? noiseReading,
    this.isMicPermissionGranted = true,
    this.practiceTonePlaying = false,
    this.practiceHeard,
    this.practiceLatencyMs,
    this.practiceFeedbackMessage,
    this.isNoisePaused = false,
    this.isDevicePaused = false,
    this.isLeftEarCompletePaused = false,
    this.pauseReason,
    this.cancelReason,
    this.noisePauseCount = 0,
    this.devicePauseCount = 0,
    this.qualityFlags = const {},
    this.trials = const [],
    this.thresholdResults = const [],
    this.screeningOutcome,
    this.savedSessions = const [],
    this.isSimulationMode = false,
    this.subScreen = ScreeningSubScreen.mainFlow,
    this.selectedRecord,
  }) : noiseReading =
           noiseReading ??
           NoiseReading(
             levelDbFs: -60.0,
             assessment: NoiseAssessment.valid,
             isDisturbance: false,
             consecutiveQuietSeconds: 0,
           );

  final String sessionId;
  final int startedAt;
  final SessionState sessionState;
  final bool hasUserConsented;
  final StrategyType selectedStrategy;
  final bool isExtendedFrequencyMode;
  final Ear currentEar;
  final int currentFrequencyHz;
  final int currentLevelDb;
  final int trialNumber;
  final bool isTonePlaying;
  final bool isWaitingForResponse;
  final int? lastResponseLatencyMs;
  final AudioRouteInfo? audioRoute;
  final bool isHeadphoneConnected;
  final NoiseReading noiseReading;
  final bool isMicPermissionGranted;
  final bool practiceTonePlaying;
  final bool? practiceHeard;
  final int? practiceLatencyMs;
  final String? practiceFeedbackMessage;
  final bool isNoisePaused;
  final bool isDevicePaused;
  final bool isLeftEarCompletePaused;
  final String? pauseReason;
  final String? cancelReason;
  final int noisePauseCount;
  final int devicePauseCount;
  final Set<QualityFlag> qualityFlags;
  final List<TrialRecord> trials;
  final List<ThresholdResult> thresholdResults;
  final SessionScreeningOutcome? screeningOutcome;
  final List<HearingSessionRecord> savedSessions;
  final bool isSimulationMode;
  final ScreeningSubScreen subScreen;
  final HearingSessionRecord? selectedRecord;

  ScreeningUiState copyWith({
    String? sessionId,
    int? startedAt,
    SessionState? sessionState,
    bool? hasUserConsented,
    StrategyType? selectedStrategy,
    bool? isExtendedFrequencyMode,
    Ear? currentEar,
    int? currentFrequencyHz,
    int? currentLevelDb,
    int? trialNumber,
    bool? isTonePlaying,
    bool? isWaitingForResponse,
    int? Function()? lastResponseLatencyMs,
    AudioRouteInfo? Function()? audioRoute,
    bool? isHeadphoneConnected,
    NoiseReading? noiseReading,
    bool? isMicPermissionGranted,
    bool? practiceTonePlaying,
    bool? Function()? practiceHeard,
    int? Function()? practiceLatencyMs,
    String? Function()? practiceFeedbackMessage,
    bool? isNoisePaused,
    bool? isDevicePaused,
    bool? isLeftEarCompletePaused,
    String? Function()? pauseReason,
    String? Function()? cancelReason,
    int? noisePauseCount,
    int? devicePauseCount,
    Set<QualityFlag>? qualityFlags,
    List<TrialRecord>? trials,
    List<ThresholdResult>? thresholdResults,
    SessionScreeningOutcome? Function()? screeningOutcome,
    List<HearingSessionRecord>? savedSessions,
    bool? isSimulationMode,
    ScreeningSubScreen? subScreen,
    HearingSessionRecord? Function()? selectedRecord,
  }) {
    return ScreeningUiState(
      sessionId: sessionId ?? this.sessionId,
      startedAt: startedAt ?? this.startedAt,
      sessionState: sessionState ?? this.sessionState,
      hasUserConsented: hasUserConsented ?? this.hasUserConsented,
      selectedStrategy: selectedStrategy ?? this.selectedStrategy,
      isExtendedFrequencyMode:
          isExtendedFrequencyMode ?? this.isExtendedFrequencyMode,
      currentEar: currentEar ?? this.currentEar,
      currentFrequencyHz: currentFrequencyHz ?? this.currentFrequencyHz,
      currentLevelDb: currentLevelDb ?? this.currentLevelDb,
      trialNumber: trialNumber ?? this.trialNumber,
      isTonePlaying: isTonePlaying ?? this.isTonePlaying,
      isWaitingForResponse: isWaitingForResponse ?? this.isWaitingForResponse,
      lastResponseLatencyMs: lastResponseLatencyMs != null
          ? lastResponseLatencyMs()
          : this.lastResponseLatencyMs,
      audioRoute: audioRoute != null ? audioRoute() : this.audioRoute,
      isHeadphoneConnected: isHeadphoneConnected ?? this.isHeadphoneConnected,
      noiseReading: noiseReading ?? this.noiseReading,
      isMicPermissionGranted:
          isMicPermissionGranted ?? this.isMicPermissionGranted,
      practiceTonePlaying: practiceTonePlaying ?? this.practiceTonePlaying,
      practiceHeard: practiceHeard != null
          ? practiceHeard()
          : this.practiceHeard,
      practiceLatencyMs: practiceLatencyMs != null
          ? practiceLatencyMs()
          : this.practiceLatencyMs,
      practiceFeedbackMessage: practiceFeedbackMessage != null
          ? practiceFeedbackMessage()
          : this.practiceFeedbackMessage,
      isNoisePaused: isNoisePaused ?? this.isNoisePaused,
      isDevicePaused: isDevicePaused ?? this.isDevicePaused,
      isLeftEarCompletePaused:
          isLeftEarCompletePaused ?? this.isLeftEarCompletePaused,
      pauseReason: pauseReason != null ? pauseReason() : this.pauseReason,
      cancelReason: cancelReason != null ? cancelReason() : this.cancelReason,
      noisePauseCount: noisePauseCount ?? this.noisePauseCount,
      devicePauseCount: devicePauseCount ?? this.devicePauseCount,
      qualityFlags: qualityFlags ?? this.qualityFlags,
      trials: trials ?? this.trials,
      thresholdResults: thresholdResults ?? this.thresholdResults,
      screeningOutcome: screeningOutcome != null
          ? screeningOutcome()
          : this.screeningOutcome,
      savedSessions: savedSessions ?? this.savedSessions,
      isSimulationMode: isSimulationMode ?? this.isSimulationMode,
      subScreen: subScreen ?? this.subScreen,
      selectedRecord: selectedRecord != null
          ? selectedRecord()
          : this.selectedRecord,
    );
  }
}

class ScreeningNotifier extends Notifier<ScreeningUiState> {
  static const _uuid = Uuid();
  final math.Random _random = math.Random();
  final TrialQualityController _qualityController =
      const TrialQualityController();

  late SessionStateMachine _stateMachine;
  late ThresholdEstimationStrategy _thresholdStrategy;

  StimulusEngine get _stimulusEngine => ref.read(stimulusEngineProvider);
  NoiseMonitor get _noiseMonitor => ref.read(noiseMonitorProvider);
  ScreeningDeviceDetector get _deviceDetector =>
      ref.read(screeningDeviceDetectorProvider);
  SessionRepository get _sessionRepo => ref.read(sessionRepositoryProvider);

  StreamSubscription<NoiseReading>? _noiseSub;
  StreamSubscription<AudioRouteInfo>? _routeSub;
  StreamSubscription<ToneEvent>? _toneSub;

  Timer? _presentationTimer;
  Timer? _responseTimeoutTimer;
  Timer? _practiceTimeoutTimer;
  Timer? _recoveryTimer;
  Timer? _nextTrialTimer;

  int _toneStartTimeMs = 0;

  @override
  ScreeningUiState build() {
    _stateMachine = SessionStateMachine(
      initialState: SessionState.onboardingConsent,
    );
    _thresholdStrategy = _buildStrategy(
      StrategyType.modifiedHughsonWestlake,
      extended: false,
    );

    _subscribeStreams();
    ref.onDispose(_cleanup);

    unawaited(refreshDeviceRoute());
    unawaited(refreshSavedSessions());

    return ScreeningUiState(
      sessionId: _uuid.v4(),
      startedAt: DateTime.now().millisecondsSinceEpoch,
      sessionState: _stateMachine.currentState,
      noiseReading: _noiseMonitor.latestReading,
      currentEar: _thresholdStrategy.currentEar,
      currentFrequencyHz: _thresholdStrategy.currentFrequencyHz,
      currentLevelDb: _thresholdStrategy.currentLevelDb,
    );
  }

  ThresholdEstimationStrategy _buildStrategy(
    StrategyType type, {
    required bool extended,
  }) {
    final freqs = extended
        ? AudiometricFrequencies.extendedSixFrequencies
        : AudiometricFrequencies.defaultScreeningFrequencies;
    return switch (type) {
      StrategyType.modifiedHughsonWestlake => ModifiedHughsonWestlakeEngine(
        config: ProtocolConfig(frequencies: freqs),
      ),
      StrategyType.binarySearchRefinement => BinarySearchStrategy(
        config: BinarySearchConfig(frequencies: freqs),
      ),
    };
  }

  void _subscribeStreams() {
    _noiseSub = _noiseMonitor.readingStream.listen(_handleNoiseReading);
    _routeSub = _deviceDetector.routeStream.listen(_handleRouteUpdate);
    _toneSub = _stimulusEngine.toneEvents.listen(_handleToneEvent);
  }

  void _cleanup() {
    _cancelTimers();
    unawaited(_noiseSub?.cancel());
    unawaited(_routeSub?.cancel());
    unawaited(_toneSub?.cancel());
  }

  void _cancelTimers() {
    _presentationTimer?.cancel();
    _presentationTimer = null;
    _responseTimeoutTimer?.cancel();
    _responseTimeoutTimer = null;
    _practiceTimeoutTimer?.cancel();
    _practiceTimeoutTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _nextTrialTimer?.cancel();
    _nextTrialTimer = null;
  }

  void _handleToneEvent(ToneEvent event) {
    switch (event.state) {
      case ToneEventState.started:
        if (state.sessionState == SessionState.practicePresentation) {
          state = state.copyWith(practiceTonePlaying: true);
        } else {
          state = state.copyWith(isTonePlaying: true);
        }
        break;
      case ToneEventState.finished:
        if (state.sessionState == SessionState.practicePresentation) {
          state = state.copyWith(practiceTonePlaying: false);
        } else {
          state = state.copyWith(isTonePlaying: false);
          if (_stateMachine.currentState == SessionState.stimulusPresentation) {
            try {
              _stateMachine.transition(const StimulusEndedEvent());
              state = state.copyWith(sessionState: _stateMachine.currentState);
            } catch (_) {}
          }
        }
        break;
      case ToneEventState.focusLost:
        _cancelTimers();
        if (state.sessionState == SessionState.stimulusPresentation ||
            state.sessionState == SessionState.waitingForResponse) {
          state = state.copyWith(
            isTonePlaying: false,
            isWaitingForResponse: false,
            isNoisePaused: true,
            pauseReason: () =>
                'Audio focus lost to another app. Tap Resume when ready.',
          );
        } else {
          state = state.copyWith(
            isTonePlaying: false,
            practiceTonePlaying: false,
          );
        }
        break;
      case ToneEventState.interrupted:
        state = state.copyWith(
          isTonePlaying: false,
          practiceTonePlaying: false,
        );
        break;
    }
  }

  Future<void> refreshDeviceRoute() async {
    final route = await _deviceDetector.getCurrentAudioRoute();
    _applyRouteUpdate(route);
  }

  void _handleRouteUpdate(AudioRouteInfo route) {
    _applyRouteUpdate(route);
  }

  void _applyRouteUpdate(AudioRouteInfo route) {
    final connected = route.routeType.isHeadphone;
    final inActiveTesting =
        _stateMachine.currentState == SessionState.stimulusPresentation ||
        _stateMachine.currentState == SessionState.waitingForResponse ||
        _stateMachine.currentState == SessionState.practicePresentation ||
        _stateMachine.currentState == SessionState.recoveryRecheck;

    state = state.copyWith(
      audioRoute: () => route,
      isHeadphoneConnected: connected,
    );

    if (!connected && inActiveTesting) {
      _handleDeviceDisconnectDuringTest();
    } else if (connected &&
        _stateMachine.currentState == SessionState.automaticPauseDevice) {
      try {
        _stateMachine.transition(
          DeviceEvaluatedEvent(route: route, isSupported: true),
        );
        _stateMachine.transition(const StartTestEvent());
        state = state.copyWith(
          sessionState: _stateMachine.currentState,
          isDevicePaused: false,
          pauseReason: () => null,
        );
        _startStimulusPresentation();
      } catch (_) {}
    }
  }

  void _handleDeviceDisconnectDuringTest() {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());

    try {
      _stateMachine.transition(const DeviceDisconnectedEvent());
    } catch (_) {}

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      isTonePlaying: false,
      isWaitingForResponse: false,
      isDevicePaused: true,
      pauseReason: () =>
          'Headphones disconnected! Please reconnect headphones to resume screening.',
      devicePauseCount: state.devicePauseCount + 1,
      qualityFlags: {
        ...state.qualityFlags,
        QualityFlag.audioRouteChangedDuringTest,
      },
    );
  }

  void _handleNoiseReading(NoiseReading reading) {
    state = state.copyWith(noiseReading: reading);

    final current = _stateMachine.currentState;
    if (reading.assessment == NoiseAssessment.invalid ||
        reading.assessment == NoiseAssessment.unavailable) {
      if (current == SessionState.stimulusPresentation ||
          current == SessionState.waitingForResponse ||
          current == SessionState.practicePresentation) {
        _handleNoiseDisturbance(reading);
      }
    } else if (current == SessionState.automaticPauseNoise &&
        state.isNoisePaused &&
        reading.assessment == NoiseAssessment.valid &&
        reading.consecutiveQuietSeconds >= 3) {
      _onNoiseRecoveryPassed();
    }
  }

  Future<void> onMicrophonePermissionResult({required bool granted}) async {
    state = state.copyWith(isMicPermissionGranted: granted);
    if (granted) {
      final started = await _noiseMonitor.startMonitoring();
      if (!started) {
        state = state.copyWith(
          noiseReading: NoiseReading(
            levelDbFs: -100.0,
            assessment: NoiseAssessment.unavailable,
            isDisturbance: true,
            consecutiveQuietSeconds: 0,
          ),
        );
      }
      await refreshDeviceRoute();
    } else {
      await _noiseMonitor.stopMonitoring();
      state = state.copyWith(
        noiseReading: NoiseReading(
          levelDbFs: -100.0,
          assessment: NoiseAssessment.unavailable,
          isDisturbance: true,
          consecutiveQuietSeconds: 0,
        ),
        qualityFlags: {
          ...state.qualityFlags,
          QualityFlag.noTrustedNoiseSensor,
        },
      );
    }
  }

  void onConsentAgreed(bool agreed) {
    if (_stateMachine.currentState == SessionState.notStarted) {
      try {
        _stateMachine.transition(const StartOnboardingEvent());
      } catch (_) {}
    }

    if (_stateMachine.currentState != SessionState.onboardingConsent) {
      if (!agreed) {
        _stateMachine = SessionStateMachine(
          initialState: SessionState.aborted,
        );
        state = state.copyWith(
          sessionState: SessionState.aborted,
          hasUserConsented: false,
        );
      }
      return;
    }

    try {
      _stateMachine.transition(ConsentAgreedEvent(agreed));
    } catch (_) {}

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      hasUserConsented: agreed,
      pauseReason: () => null,
    );

    if (agreed) {
      unawaited(_noiseMonitor.startMonitoring());
      unawaited(refreshDeviceRoute());
    }
  }

  void ensureConsentedForLoggedInUser() {
    if (_stateMachine.currentState == SessionState.onboardingConsent) {
      onConsentAgreed(true);
    }
  }

  void selectStrategy(StrategyType strategy) {
    if (_stateMachine.currentState == SessionState.deviceReadiness ||
        _stateMachine.currentState == SessionState.testPrep ||
        _stateMachine.currentState == SessionState.onboardingConsent) {
      _thresholdStrategy = _buildStrategy(
        strategy,
        extended: state.isExtendedFrequencyMode,
      );
      final updatedFlags = Set<QualityFlag>.from(state.qualityFlags);
      if (strategy == StrategyType.binarySearchRefinement) {
        updatedFlags.add(QualityFlag.binarySearchExperimental);
      } else {
        updatedFlags.remove(QualityFlag.binarySearchExperimental);
      }
      state = state.copyWith(
        selectedStrategy: strategy,
        qualityFlags: updatedFlags,
        currentEar: _thresholdStrategy.currentEar,
        currentFrequencyHz: _thresholdStrategy.currentFrequencyHz,
        currentLevelDb: _thresholdStrategy.currentLevelDb,
      );
    }
  }

  void toggleFrequencyMode(bool extended) {
    if (_stateMachine.currentState == SessionState.deviceReadiness ||
        _stateMachine.currentState == SessionState.testPrep ||
        _stateMachine.currentState == SessionState.onboardingConsent) {
      _thresholdStrategy = _buildStrategy(
        state.selectedStrategy,
        extended: extended,
      );
      state = state.copyWith(
        isExtendedFrequencyMode: extended,
        currentEar: _thresholdStrategy.currentEar,
        currentFrequencyHz: _thresholdStrategy.currentFrequencyHz,
        currentLevelDb: _thresholdStrategy.currentLevelDb,
      );
    }
  }

  void onDevicePrecheckContinue() {
    final route =
        state.audioRoute ??
        const AudioRouteInfo(
          routeType: AudioRouteType.otherUnsupported,
          deviceName: 'Unknown Audio Output',
          isStereoCapable: true,
          sampleRateHz: 44100,
          calibrationInfo: CalibrationInfo(
            deviceModel: 'Unknown',
            routeType: AudioRouteType.otherUnsupported,
            provenance: CalibrationProvenance.uncalibrated,
            isOfficiallySupported: false,
          ),
        );
    final isSupported = route.routeType.isHeadphone;

    if (!isSupported) {
      state = state.copyWith(
        pauseReason: () =>
            'Headphones required. Built-in speaker cannot isolate left and right ears.',
      );
      return;
    }

    final currentNoise = state.noiseReading;
    if (currentNoise.assessment == NoiseAssessment.unavailable) {
      state = state.copyWith(
        pauseReason: () =>
            'Microphone sensor unavailable or permission denied. Please grant microphone permission to monitor ambient noise.',
      );
      return;
    }

    if (currentNoise.assessment == NoiseAssessment.invalid) {
      state = state.copyWith(
        pauseReason: () =>
            'Environment is too loud (${currentNoise.levelDbFs.toStringAsFixed(1)} dBFS). Please move to a quieter location.',
      );
      return;
    }

    try {
      _stateMachine.transition(
        DeviceEvaluatedEvent(route: route, isSupported: isSupported),
      );
      _stateMachine.transition(
        CalibrationEvaluatedEvent(route.calibrationInfo),
      );
      _stateMachine.transition(
        NoiseBaselineCheckedEvent(currentNoise.assessment),
      );
      state = state.copyWith(
        sessionState: _stateMachine.currentState,
        pauseReason: () => null,
      );
    } catch (_) {}
  }

  // --- Practice Round Flow ---

  void onStartPractice() {
    if (_stateMachine.currentState == SessionState.testPrep ||
        _stateMachine.currentState == SessionState.practiceFeedback) {
      _practiceTimeoutTimer?.cancel();
      unawaited(_stimulusEngine.stopTone());

      try {
        _stateMachine.transition(const StartPracticeEvent());
      } catch (_) {}

      state = state.copyWith(
        sessionState: _stateMachine.currentState,
        practiceTonePlaying: true,
        practiceHeard: () => null,
        practiceLatencyMs: () => null,
        practiceFeedbackMessage: () =>
            "Playing sample 1000 Hz demo tone. Tap 'I HEAR IT' or 'I CAN'T HEAR IT'.",
      );

      _toneStartTimeMs = DateTime.now().millisecondsSinceEpoch;
      unawaited(
        _stimulusEngine.playTone(
          frequencyHz: AudiometricFrequencies.freq1000Hz,
          levelDb: 50,
          ear: Ear.left,
          durationMs: 1500,
        ),
      );

      _practiceTimeoutTimer = Timer(const Duration(milliseconds: 3500), () {
        if (state.sessionState == SessionState.practicePresentation) {
          onPracticeTimedOut();
        }
      });
    }
  }

  void onPracticeHeardClicked() {
    if (state.sessionState != SessionState.practicePresentation) return;
    final latencyMs = DateTime.now().millisecondsSinceEpoch - _toneStartTimeMs;
    _practiceTimeoutTimer?.cancel();
    unawaited(_stimulusEngine.stopTone());

    try {
      _stateMachine.transition(
        PracticeResponseReceivedEvent(heard: true, latencyMs: latencyMs),
      );
    } catch (_) {}

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      practiceTonePlaying: false,
      practiceHeard: () => true,
      practiceLatencyMs: () => latencyMs,
      practiceFeedbackMessage: () =>
          'Demo tone heard (${latencyMs}ms). You are ready to begin screening.',
    );
  }

  void onPracticeNotHeardClicked() {
    if (state.sessionState != SessionState.practicePresentation) return;
    final latencyMs = DateTime.now().millisecondsSinceEpoch - _toneStartTimeMs;
    _practiceTimeoutTimer?.cancel();
    unawaited(_stimulusEngine.stopTone());

    try {
      _stateMachine.transition(
        PracticeResponseReceivedEvent(heard: false, latencyMs: latencyMs),
      );
    } catch (_) {}

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      practiceTonePlaying: false,
      practiceHeard: () => false,
      practiceLatencyMs: () => latencyMs,
      practiceFeedbackMessage: () =>
          'Demo tone reported not heard. Check headphone volume and fit before starting.',
    );
  }

  void onPracticeTimedOut() {
    if (state.sessionState != SessionState.practicePresentation) return;
    _practiceTimeoutTimer?.cancel();
    unawaited(_stimulusEngine.stopTone());

    try {
      _stateMachine.transition(const ResponseTimedOutEvent());
    } catch (_) {}

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      practiceTonePlaying: false,
      practiceHeard: () => false,
      practiceFeedbackMessage: () =>
          'Practice round timed out cleanly. Check headphone volume or try the demo again.',
    );
  }

  void onFinishPractice() {
    _practiceTimeoutTimer?.cancel();
    unawaited(_stimulusEngine.stopTone());
    try {
      _stateMachine.transition(const FinishPracticeEvent());
    } catch (_) {}
    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      practiceTonePlaying: false,
    );
  }

  // --- Active Screening Trial Execution ---

  void onStartScreening() {
    _practiceTimeoutTimer?.cancel();
    unawaited(_stimulusEngine.stopTone());
    try {
      _stateMachine.transition(const StartTestEvent());
      state = state.copyWith(sessionState: _stateMachine.currentState);
      _startStimulusPresentation();
    } catch (_) {}
  }

  void onContinueRightEar() {
    state = state.copyWith(isLeftEarCompletePaused: false);
    _startStimulusPresentation();
  }

  void _startStimulusPresentation() {
    _cancelTimers();

    if (_stateMachine.currentState == SessionState.trialValidation ||
        _stateMachine.currentState == SessionState.thresholdEstimation) {
      try {
        _stateMachine.transition(const NextTrialNeededEvent());
      } catch (_) {}
    }

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      currentEar: _thresholdStrategy.currentEar,
      currentFrequencyHz: _thresholdStrategy.currentFrequencyHz,
      currentLevelDb: _thresholdStrategy.currentLevelDb,
      isWaitingForResponse: false,
      isTonePlaying: false,
    );

    final jitterMs = 500 + _random.nextInt(701); // 500..1200ms
    _presentationTimer = Timer(Duration(milliseconds: jitterMs), () {
      if (_stateMachine.currentState != SessionState.stimulusPresentation) {
        return;
      }

      final ear = _thresholdStrategy.currentEar;
      final freq = _thresholdStrategy.currentFrequencyHz;
      final level = _thresholdStrategy.currentLevelDb;

      _toneStartTimeMs = DateTime.now().millisecondsSinceEpoch;
      state = state.copyWith(
        isTonePlaying: true,
        isWaitingForResponse: true,
        currentEar: ear,
        currentFrequencyHz: freq,
        currentLevelDb: level,
      );

      unawaited(
        _stimulusEngine.playTone(
          frequencyHz: freq,
          levelDb: level,
          ear: ear,
          durationMs: 1200,
        ),
      );

      // Response window: stimulus (1200ms) + 1800ms grace = 3000ms.
      _responseTimeoutTimer = Timer(const Duration(milliseconds: 3000), () {
        if (state.isWaitingForResponse) {
          _handleUserResponse(
            heard: false,
            latencyMs: null,
            explicitNotHeard: false,
          );
        }
      });
    });
  }

  void onUserHeardClicked() {
    if (!state.isWaitingForResponse) return;
    final latencyMs = DateTime.now().millisecondsSinceEpoch - _toneStartTimeMs;
    _handleUserResponse(
      heard: true,
      latencyMs: latencyMs,
      explicitNotHeard: false,
    );
  }

  void onUserNotHeardClicked() {
    if (!state.isWaitingForResponse) return;
    final latencyMs = DateTime.now().millisecondsSinceEpoch - _toneStartTimeMs;
    _handleUserResponse(
      heard: false,
      latencyMs: latencyMs,
      explicitNotHeard: true,
    );
  }

  void _handleUserResponse({
    required bool heard,
    required int? latencyMs,
    required bool explicitNotHeard,
  }) {
    _presentationTimer?.cancel();
    _responseTimeoutTimer?.cancel();
    unawaited(_stimulusEngine.stopTone());

    state = state.copyWith(
      isTonePlaying: false,
      isWaitingForResponse: false,
      lastResponseLatencyMs: () => latencyMs,
    );

    try {
      if (heard) {
        _stateMachine.transition(UserRespondedHeardEvent(latencyMs ?? 0));
      } else if (explicitNotHeard) {
        _stateMachine.transition(UserRespondedNotHeardEvent(latencyMs ?? 0));
      } else {
        _stateMachine.transition(const ResponseTimedOutEvent());
      }
      state = state.copyWith(sessionState: _stateMachine.currentState);
    } catch (_) {}

    final qualityEval = _qualityController.evaluateTrialQuality(
      userTappedHeard: heard,
      latencyMs: latencyMs,
      noiseAssessment: state.noiseReading.assessment,
      isNoiseDisturbedDuringTrial: state.isNoisePaused,
      routeInfo: state.audioRoute,
      explicitNotHeard: explicitNotHeard,
    );

    final stepResult = _thresholdStrategy.evaluateTrial(
      qualityEval.outcome,
      latencyMs: qualityEval.latencyMs,
      ambientNoiseDbFs: state.noiseReading.levelDbFs,
    );

    _processStrategyResult(stepResult);
  }

  void _processStrategyResult(StrategyResult result) {
    switch (result) {
      case StrategyNextTrial(:final ear, :final frequencyHz, :final nextLevelDb):
        state = state.copyWith(
          currentEar: ear,
          currentFrequencyHz: frequencyHz,
          currentLevelDb: nextLevelDb,
          trials: _thresholdStrategy.allTrials,
          trialNumber: _thresholdStrategy.allTrials.length,
        );
        _nextTrialTimer = Timer(const Duration(milliseconds: 400), () {
          if (_stateMachine.currentState == SessionState.trialValidation ||
              _stateMachine.currentState == SessionState.stimulusPresentation) {
            _startStimulusPresentation();
          }
        });
        break;

      case StrategyThresholdFound(:final result, :final nextTarget):
        final leftJustCompleted =
            result.ear == Ear.left && nextTarget?.ear == Ear.right;
        try {
          _stateMachine.transition(const TargetThresholdFoundEvent());
        } catch (_) {}
        state = state.copyWith(
          sessionState: _stateMachine.currentState,
          currentEar: nextTarget?.ear ?? result.ear,
          currentFrequencyHz: nextTarget?.frequencyHz ?? result.frequencyHz,
          currentLevelDb: _thresholdStrategy.currentLevelDb,
          trials: _thresholdStrategy.allTrials,
          trialNumber: _thresholdStrategy.allTrials.length,
          thresholdResults: _thresholdStrategy.thresholdResults,
          isLeftEarCompletePaused: leftJustCompleted,
        );
        if (!leftJustCompleted) {
          _nextTrialTimer = Timer(const Duration(milliseconds: 500), () {
            if (_stateMachine.currentState == SessionState.thresholdEstimation) {
              _startStimulusPresentation();
            }
          });
        }
        break;

      case StrategyMaxTrialsExceeded(:final ear, :final nextTarget):
      case StrategyInconclusive(:final ear, :final nextTarget):
        final leftJustCompleted =
            ear == Ear.left && nextTarget?.ear == Ear.right;
        if (nextTarget == null) {
          _completeSession();
          return;
        }
        try {
          _stateMachine.transition(const TargetThresholdFoundEvent());
        } catch (_) {}
        state = state.copyWith(
          sessionState: _stateMachine.currentState,
          currentEar: nextTarget.ear,
          currentFrequencyHz: nextTarget.frequencyHz,
          currentLevelDb: _thresholdStrategy.currentLevelDb,
          trials: _thresholdStrategy.allTrials,
          trialNumber: _thresholdStrategy.allTrials.length,
          thresholdResults: _thresholdStrategy.thresholdResults,
          isLeftEarCompletePaused: leftJustCompleted,
        );
        if (!leftJustCompleted) {
          _nextTrialTimer = Timer(const Duration(milliseconds: 500), () {
            if (_stateMachine.currentState == SessionState.thresholdEstimation) {
              _startStimulusPresentation();
            }
          });
        }
        break;

      case StrategyAllTargetsCompleted():
        _completeSession();
        break;
    }
  }

  void _completeSession() {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());
    unawaited(_noiseMonitor.stopMonitoring());

    try {
      _stateMachine.transition(const AllTargetsCompletedEvent());
    } catch (_) {}

    final outcome = _computeScreeningOutcome();
    state = state.copyWith(
      sessionState: SessionState.results,
      isTonePlaying: false,
      isWaitingForResponse: false,
      trials: _thresholdStrategy.allTrials,
      trialNumber: _thresholdStrategy.allTrials.length,
      thresholdResults: _thresholdStrategy.thresholdResults,
      screeningOutcome: () => outcome,
    );

    unawaited(_saveSessionToDisk());
  }

  SessionScreeningOutcome _computeScreeningOutcome() {
    final freqs = state.isExtendedFrequencyMode
        ? AudiometricFrequencies.extendedSixFrequencies
        : AudiometricFrequencies.defaultScreeningFrequencies;
    final leftThresholds = _thresholdStrategy.thresholdResults
        .where((t) => t.ear == Ear.left)
        .toList();
    final rightThresholds = _thresholdStrategy.thresholdResults
        .where((t) => t.ear == Ear.right)
        .toList();

    final leftSummary = _evaluateEarScreening(
      Ear.left,
      leftThresholds,
      freqs.length,
    );
    final rightSummary = _evaluateEarScreening(
      Ear.right,
      rightThresholds,
      freqs.length,
    );

    final overall =
        (leftSummary.classification == ScreeningOutcomeClassification.refer ||
            rightSummary.classification ==
                ScreeningOutcomeClassification.refer)
        ? ScreeningOutcomeClassification.refer
        : (leftSummary.classification ==
                  ScreeningOutcomeClassification.inconclusive ||
              rightSummary.classification ==
                  ScreeningOutcomeClassification.inconclusive)
        ? ScreeningOutcomeClassification.inconclusive
        : ScreeningOutcomeClassification.pass;

    final totalTrials = _thresholdStrategy.allTrials.length;
    final contaminated = _thresholdStrategy.allTrials
        .where(
          (t) =>
              t.outcome == TrialOutcome.contaminatedByNoise ||
              t.outcome == TrialOutcome.invalidInterrupted,
        )
        .length;

    return SessionScreeningOutcome(
      overallClassification: overall,
      leftEarSummary: leftSummary,
      rightEarSummary: rightSummary,
      totalTrials: totalTrials,
      contaminatedTrials: contaminated,
      isCalibrated: false,
      advisoryNotes: const [
        'Values represent uncalibrated digital attenuation (dBFS) on consumer hardware.',
        'This is a preliminary screening / wellness tool, not a diagnostic clinical audiogram.',
        'If hearing difficulties are experienced, a formal clinical audiometry evaluation with an audiologist is recommended.',
      ],
    );
  }

  EarScreeningSummary _evaluateEarScreening(
    Ear ear,
    List<ThresholdResult> thresholds,
    int targetCount,
  ) {
    final isComplete = thresholds.length >= targetCount;
    final avgDb = thresholds.isNotEmpty
        ? thresholds.map((t) => t.thresholdDb).reduce((a, b) => a + b) /
              thresholds.length
        : null;

    const screeningBaselineDb = 25;
    final hasElevated = thresholds.any(
      (t) => t.thresholdDb > screeningBaselineDb,
    );

    final classification = !isComplete
        ? ScreeningOutcomeClassification.inconclusive
        : hasElevated
        ? ScreeningOutcomeClassification.refer
        : ScreeningOutcomeClassification.pass;

    final notes = switch (classification) {
      ScreeningOutcomeClassification.pass =>
        'All tested thresholds at or below $screeningBaselineDb dBFS provisional screening level.',
      ScreeningOutcomeClassification.refer =>
        'Thresholds above $screeningBaselineDb dBFS detected. Professional hearing assessment recommended.',
      ScreeningOutcomeClassification.inconclusive =>
        'Incomplete target coverage (${thresholds.length}/$targetCount completed).',
    };

    return EarScreeningSummary(
      ear: ear,
      classification: classification,
      thresholds: thresholds,
      averageLevelDb: avgDb,
      isComplete: isComplete,
      summaryNotes: notes,
    );
  }

  void _handleNoiseDisturbance(NoiseReading reading) {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());

    if (state.isWaitingForResponse || state.isTonePlaying) {
      _thresholdStrategy.evaluateTrial(
        TrialOutcome.contaminatedByNoise,
        ambientNoiseDbFs: reading.levelDbFs,
      );
    }

    try {
      _stateMachine.transition(const NoiseDisturbanceDetectedEvent(true));
    } catch (_) {}

    state = state.copyWith(
      sessionState: _stateMachine.currentState,
      isTonePlaying: false,
      isWaitingForResponse: false,
      isNoisePaused: true,
      pauseReason: () =>
          'Environmental noise detected (${reading.levelDbFs.toStringAsFixed(1)} dBFS). Pausing test.',
      noisePauseCount: state.noisePauseCount + 1,
      qualityFlags: {
        ...state.qualityFlags,
        QualityFlag.environmentalNoisePausesDetected,
      },
      trials: _thresholdStrategy.allTrials,
      trialNumber: _thresholdStrategy.allTrials.length,
    );
  }

  void _onNoiseRecoveryPassed() {
    if (_recoveryTimer != null) return;
    try {
      _stateMachine.transition(const NoiseRecoveredEvent(true));
      state = state.copyWith(
        sessionState: SessionState.recoveryRecheck,
        isNoisePaused: false,
        pauseReason: () => null,
      );
    } catch (_) {}

    _recoveryTimer = Timer(const Duration(seconds: 1), () {
      _recoveryTimer = null;
      if (state.noiseReading.assessment == NoiseAssessment.valid &&
          state.sessionState == SessionState.recoveryRecheck) {
        try {
          _stateMachine.transition(const StartTestEvent());
          state = state.copyWith(sessionState: _stateMachine.currentState);
          _startStimulusPresentation();
        } catch (_) {}
      } else {
        _handleNoiseDisturbance(state.noiseReading);
      }
    });
  }

  void onPauseRequested() {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());
    state = state.copyWith(
      isTonePlaying: false,
      isWaitingForResponse: false,
      isNoisePaused: true,
      pauseReason: () => 'Testing paused by user.',
    );
  }

  void onResumeRequested() {
    state = state.copyWith(isNoisePaused: false, pauseReason: () => null);
    _startStimulusPresentation();
  }

  void onCancelRequested() {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());
    unawaited(_noiseMonitor.stopMonitoring());

    try {
      _stateMachine.transition(const CancelRequestedEvent());
    } catch (_) {}

    state = state.copyWith(
      sessionState: SessionState.cancelled,
      isTonePlaying: false,
      isWaitingForResponse: false,
      isNoisePaused: false,
      cancelReason: () => 'Screening was cancelled by the user.',
    );
    unawaited(_saveSessionToDisk());
  }

  /// Returns directly to DEVICE_READINESS retaining user consent.
  void onTryAgain() {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());
    _thresholdStrategy.reset();
    _stateMachine = SessionStateMachine(
      initialState: SessionState.deviceReadiness,
    );

    state = state.copyWith(
      sessionId: _uuid.v4(),
      startedAt: DateTime.now().millisecondsSinceEpoch,
      sessionState: SessionState.deviceReadiness,
      hasUserConsented: true,
      isTonePlaying: false,
      isWaitingForResponse: false,
      isNoisePaused: false,
      isDevicePaused: false,
      isLeftEarCompletePaused: false,
      pauseReason: () => null,
      cancelReason: () => null,
      trials: const [],
      thresholdResults: const [],
      trialNumber: 0,
      screeningOutcome: () => null,
      currentEar: _thresholdStrategy.currentEar,
      currentFrequencyHz: _thresholdStrategy.currentFrequencyHz,
      currentLevelDb: _thresholdStrategy.currentLevelDb,
      subScreen: ScreeningSubScreen.mainFlow,
    );
    unawaited(_noiseMonitor.startMonitoring());
    unawaited(refreshDeviceRoute());
  }

  /// Full restart resetting consent back to ONBOARDING_CONSENT.
  void onRestartRequested() {
    _cancelTimers();
    unawaited(_stimulusEngine.stopTone());
    _thresholdStrategy.reset();
    _stateMachine = SessionStateMachine(
      initialState: SessionState.onboardingConsent,
    );

    state = ScreeningUiState(
      sessionId: _uuid.v4(),
      startedAt: DateTime.now().millisecondsSinceEpoch,
      sessionState: SessionState.onboardingConsent,
      hasUserConsented: false,
      savedSessions: state.savedSessions,
      isSimulationMode: state.isSimulationMode,
      audioRoute: state.audioRoute,
      isHeadphoneConnected: state.isHeadphoneConnected,
    );
  }

  Future<void> _saveSessionToDisk() async {
    final route =
        state.audioRoute ?? await _deviceDetector.getCurrentAudioRoute();
    final record = HearingSessionRecord(
      sessionId: state.sessionId,
      startedAt: state.startedAt,
      completedAt: DateTime.now().millisecondsSinceEpoch,
      strategyType: state.selectedStrategy == StrategyType.binarySearchRefinement
          ? 'BINARY_SEARCH_REFINEMENT'
          : 'MODIFIED_HUGHSON_WESTLAKE',
      deviceModel: route.calibrationInfo.deviceModel,
      androidVersion: 35,
      audioRoute: route,
      isCompleted: state.sessionState == SessionState.results,
      qualityFlags: {
        ...state.qualityFlags,
        QualityFlag.uncalibratedHardware,
        if (state.isSimulationMode) QualityFlag.simulationOnly,
      },
      trials: _thresholdStrategy.allTrials,
      thresholdResults: _thresholdStrategy.thresholdResults,
      noisePauseCount: state.noisePauseCount,
      devicePauseCount: state.devicePauseCount,
      screeningOutcome: state.screeningOutcome,
    );
    await _sessionRepo.saveSession(record);
    await refreshSavedSessions();
  }

  Future<void> refreshSavedSessions() async {
    final sessions = await _sessionRepo.loadAllSessions();
    state = state.copyWith(savedSessions: sessions);
  }

  void openSubScreen(
    ScreeningSubScreen subScreen, {
    HearingSessionRecord? record,
  }) {
    state = state.copyWith(
      subScreen: subScreen,
      selectedRecord: () => record ?? state.selectedRecord,
    );
  }

  // --- Developer Simulation Drawer Controls ---

  void toggleSimulationMode() {
    state = state.copyWith(isSimulationMode: !state.isSimulationMode);
  }

  void simulateNoiseSpike(NoiseAssessment assessment) {
    if (!state.isSimulationMode) return;
    final db = switch (assessment) {
      NoiseAssessment.invalid => -25.0,
      NoiseAssessment.suspect => -32.0,
      NoiseAssessment.valid => -55.0,
      NoiseAssessment.unavailable => -100.0,
    };
    final quietSecs = assessment == NoiseAssessment.valid ? 4 : 0;
    final monitor = _noiseMonitor;
    if (monitor is FakeNoiseMonitor) {
      monitor.injectAssessment(assessment, db, quietSeconds: quietSecs);
    } else {
      _handleNoiseReading(
        NoiseReading(
          levelDbFs: db,
          assessment: assessment,
          isDisturbance: assessment == NoiseAssessment.invalid,
          consecutiveQuietSeconds: quietSecs,
        ),
      );
    }
  }

  void simulateDeviceDisconnect() {
    if (!state.isSimulationMode) return;
    const speakerRoute = AudioRouteInfo(
      routeType: AudioRouteType.builtinSpeaker,
      deviceName: 'Simulated Built-in Speaker',
      isStereoCapable: false,
      sampleRateHz: 44100,
      calibrationInfo: CalibrationInfo(
        deviceModel: 'Simulator',
        routeType: AudioRouteType.builtinSpeaker,
        provenance: CalibrationProvenance.simulatedProfile,
        isOfficiallySupported: false,
      ),
    );
    final detector = _deviceDetector;
    if (detector is FakeDeviceCapabilityManager) {
      detector.setSimulatedRoute(AudioRouteType.builtinSpeaker);
    } else {
      _applyRouteUpdate(speakerRoute);
    }
  }

  void simulateDeviceReconnect() {
    if (!state.isSimulationMode) return;
    const hpRoute = AudioRouteInfo(
      routeType: AudioRouteType.wiredHeadphones,
      deviceName: 'Simulated Wired Headphones',
      isStereoCapable: true,
      sampleRateHz: 44100,
      calibrationInfo: CalibrationInfo(
        deviceModel: 'Simulator',
        routeType: AudioRouteType.wiredHeadphones,
        provenance: CalibrationProvenance.simulatedProfile,
        isOfficiallySupported: true,
      ),
    );
    final detector = _deviceDetector;
    if (detector is FakeDeviceCapabilityManager) {
      detector.setSimulatedRoute(AudioRouteType.wiredHeadphones);
    } else {
      _applyRouteUpdate(hpRoute);
    }
  }
}

final screeningNotifierProvider =
    NotifierProvider<ScreeningNotifier, ScreeningUiState>(
      ScreeningNotifier.new,
    );
