import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/quality/trial_quality_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TrialQualityController controller;

  const validRoute = AudioRouteInfo(
    routeType: AudioRouteType.wiredHeadphones,
    deviceName: 'Standard 3.5mm Headset',
    isStereoCapable: true,
    sampleRateHz: 44100,
    calibrationInfo: CalibrationInfo(
      deviceModel: 'Test',
      routeType: AudioRouteType.wiredHeadphones,
      provenance: CalibrationProvenance.fixtureDefault,
      isOfficiallySupported: true,
    ),
  );

  const speakerRoute = AudioRouteInfo(
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
    controller = const TrialQualityController(
      minPlausibleLatencyMs: 150,
      maxPlausibleLatencyMs: 3000,
    );
  });

  test('valid response with plausible latency produces HEARD outcome', () {
    final eval = controller.evaluateTrialQuality(
      userTappedHeard: true,
      latencyMs: 450,
      noiseAssessment: NoiseAssessment.valid,
      isNoiseDisturbedDuringTrial: false,
      routeInfo: validRoute,
    );
    expect(eval.isTrialValid, isTrue);
    expect(eval.outcome, TrialOutcome.heard);
    expect(eval.latencyMs, 450);
    expect(eval.isPlausibleLatency, isTrue);
  });

  test('anticipatory false alarm tap is rejected as INVALID_INTERRUPTED', () {
    final eval = controller.evaluateTrialQuality(
      userTappedHeard: true,
      latencyMs: 80,
      noiseAssessment: NoiseAssessment.valid,
      isNoiseDisturbedDuringTrial: false,
      routeInfo: validRoute,
    );
    expect(eval.isTrialValid, isFalse);
    expect(eval.outcome, TrialOutcome.invalidInterrupted);
    expect(eval.isPlausibleLatency, isFalse);
    expect(eval.qualityFlags, contains(QualityFlag.excessiveReversals));
  });

  test(
    'noise disturbance automatically invalidates trial as CONTAMINATED_BY_NOISE',
    () {
      final eval = controller.evaluateTrialQuality(
        userTappedHeard: true,
        latencyMs: 500,
        noiseAssessment: NoiseAssessment.invalid,
        isNoiseDisturbedDuringTrial: true,
        routeInfo: validRoute,
      );
      expect(eval.isTrialValid, isFalse);
      expect(eval.outcome, TrialOutcome.contaminatedByNoise);
      expect(
        eval.qualityFlags,
        contains(QualityFlag.environmentalNoisePausesDetected),
      );
    },
  );

  test(
    'speaker route or missing headphones invalidates trial as INVALID_INTERRUPTED',
    () {
      final eval = controller.evaluateTrialQuality(
        userTappedHeard: true,
        latencyMs: 500,
        noiseAssessment: NoiseAssessment.valid,
        isNoiseDisturbedDuringTrial: false,
        routeInfo: speakerRoute,
      );
      expect(eval.isTrialValid, isFalse);
      expect(eval.outcome, TrialOutcome.invalidInterrupted);
      expect(
        eval.qualityFlags,
        contains(QualityFlag.audioRouteChangedDuringTest),
      );
    },
  );

  test('explicit not-heard response produces NOT_HEARD outcome', () {
    final eval = controller.evaluateTrialQuality(
      userTappedHeard: false,
      latencyMs: 800,
      noiseAssessment: NoiseAssessment.valid,
      isNoiseDisturbedDuringTrial: false,
      routeInfo: validRoute,
      explicitNotHeard: true,
    );
    expect(eval.isTrialValid, isTrue);
    expect(eval.outcome, TrialOutcome.notHeard);
    expect(eval.latencyMs, 800);
  });

  test(
    'missing response on timeout produces UNANSWERED_TIMEOUT and is not treated as not-heard',
    () {
      final eval = controller.evaluateTrialQuality(
        userTappedHeard: false,
        latencyMs: null,
        noiseAssessment: NoiseAssessment.valid,
        isNoiseDisturbedDuringTrial: false,
        routeInfo: validRoute,
        explicitNotHeard: false,
      );
      expect(eval.isTrialValid, isFalse);
      expect(eval.outcome, TrialOutcome.unansweredTimeout);
      expect(eval.latencyMs, isNull);
    },
  );
}
