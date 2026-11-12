import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/statemachine/session_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SessionStateMachine sm;

  const supportedRoute = AudioRouteInfo(
    routeType: AudioRouteType.wiredHeadphones,
    deviceName: 'Test Headphones',
    isStereoCapable: true,
    sampleRateHz: 44100,
    calibrationInfo: CalibrationInfo(
      deviceModel: 'Test',
      routeType: AudioRouteType.wiredHeadphones,
      provenance: CalibrationProvenance.fixtureDefault,
      isOfficiallySupported: true,
    ),
  );

  const unsupportedRoute = AudioRouteInfo(
    routeType: AudioRouteType.builtinSpeaker,
    deviceName: 'Phone Speaker',
    isStereoCapable: true,
    sampleRateHz: 44100,
    calibrationInfo: CalibrationInfo(
      deviceModel: 'Test',
      routeType: AudioRouteType.builtinSpeaker,
      provenance: CalibrationProvenance.uncalibrated,
      isOfficiallySupported: false,
    ),
  );

  setUp(() {
    sm = SessionStateMachine();
  });

  test('starts in NOT_STARTED state', () {
    expect(sm.currentState, SessionState.notStarted);
  });

  test('valid onboarding and consent transitions', () {
    sm.transition(const StartOnboardingEvent());
    expect(sm.currentState, SessionState.onboardingConsent);

    sm.transition(const ConsentAgreedEvent(true));
    expect(sm.currentState, SessionState.deviceReadiness);
  });

  test('declined consent aborts session', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const ConsentAgreedEvent(false));
    expect(sm.currentState, SessionState.aborted);
  });

  test('unsupported audio route aborts session', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const ConsentAgreedEvent(true));
    sm.transition(
      const DeviceEvaluatedEvent(route: unsupportedRoute, isSupported: false),
    );
    expect(sm.currentState, SessionState.aborted);
  });

  test('supported route proceeds through calibration and noise precheck', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const ConsentAgreedEvent(true));
    sm.transition(
      const DeviceEvaluatedEvent(route: supportedRoute, isSupported: true),
    );
    expect(sm.currentState, SessionState.calibrationGate);

    sm.transition(CalibrationEvaluatedEvent(supportedRoute.calibrationInfo));
    expect(sm.currentState, SessionState.environmentalNoiseCheck);

    sm.transition(const NoiseBaselineCheckedEvent(NoiseAssessment.valid));
    expect(sm.currentState, SessionState.testPrep);
  });

  test('noisy environment causes automatic pause during precheck', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const ConsentAgreedEvent(true));
    sm.transition(
      const DeviceEvaluatedEvent(route: supportedRoute, isSupported: true),
    );
    sm.transition(CalibrationEvaluatedEvent(supportedRoute.calibrationInfo));
    sm.transition(const NoiseBaselineCheckedEvent(NoiseAssessment.invalid));
    expect(sm.currentState, SessionState.automaticPauseNoise);
  });

  test('illegal transitions are rejected with StateError', () {
    expect(() => sm.transition(const StartTestEvent()), throwsStateError);
  });

  test('cancellation is allowed from any active state', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const CancelRequestedEvent());
    expect(sm.currentState, SessionState.cancelled);
  });

  test('restart resets state to NOT_STARTED', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const RestartRequestedEvent());
    expect(sm.currentState, SessionState.notStarted);
  });

  test('practice round flow transitions correctly', () {
    sm.transition(const StartOnboardingEvent());
    sm.transition(const ConsentAgreedEvent(true));
    sm.transition(
      const DeviceEvaluatedEvent(route: supportedRoute, isSupported: true),
    );
    sm.transition(CalibrationEvaluatedEvent(supportedRoute.calibrationInfo));
    sm.transition(const NoiseBaselineCheckedEvent(NoiseAssessment.valid));
    expect(sm.currentState, SessionState.testPrep);

    sm.transition(const StartPracticeEvent());
    expect(sm.currentState, SessionState.practicePresentation);

    sm.transition(
      const PracticeResponseReceivedEvent(heard: true, latencyMs: 400),
    );
    expect(sm.currentState, SessionState.practiceFeedback);

    sm.transition(const StartTestEvent());
    expect(sm.currentState, SessionState.stimulusPresentation);
  });
}
