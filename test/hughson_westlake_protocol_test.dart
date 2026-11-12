import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/threshold/hughson_westlake_protocol.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ModifiedHughsonWestlakeEngine engine;

  setUp(() {
    engine = ModifiedHughsonWestlakeEngine(
      config: const ProtocolConfig(
        startingLevelDb: 40,
        downStepDb: 10,
        upStepDb: 5,
        minLevelDb: 0,
        maxLevelDb: 80,
        requiredAscendingResponses: 2,
        frequencies: [
          AudiometricFrequencies.freq1000Hz,
          AudiometricFrequencies.freq2000Hz,
        ],
        ears: [Ear.left, Ear.right],
      ),
    );
  });

  test('starts at configured starting level and first target', () {
    expect(engine.currentLevelDb, 40);
    expect(engine.currentEar, Ear.left);
    expect(engine.currentFrequencyHz, AudiometricFrequencies.freq1000Hz);
  });

  test('moves down 10 dB on heard and up 5 dB on not heard', () {
    final r1 = engine.evaluateTrial(TrialOutcome.heard);
    expect(r1, isA<StrategyNextTrial>());
    expect(engine.currentLevelDb, 30);

    final r2 = engine.evaluateTrial(TrialOutcome.notHeard);
    expect(r2, isA<StrategyNextTrial>());
    expect(engine.currentLevelDb, 35);

    final r3 = engine.evaluateTrial(TrialOutcome.notHeard);
    expect(r3, isA<StrategyNextTrial>());
    expect(engine.currentLevelDb, 40);
  });

  test(
    'contaminated trial by noise does not advance level or count as non-response',
    () {
      expect(engine.currentLevelDb, 40);
      final r = engine.evaluateTrial(
        TrialOutcome.contaminatedByNoise,
        ambientNoiseDbFs: -25.0,
      );
      expect(r, isA<StrategyNextTrial>());
      expect(engine.currentLevelDb, 40);
      expect(engine.allTrials.last.outcome, TrialOutcome.contaminatedByNoise);
    },
  );

  test('invalid interrupted trial does not alter threshold search', () {
    final r = engine.evaluateTrial(TrialOutcome.invalidInterrupted);
    expect(r, isA<StrategyNextTrial>());
    expect(engine.currentLevelDb, 40);
  });

  test(
    'Hughson-Westlake threshold accepted after 2 ascending responses at same level',
    () {
      engine.evaluateTrial(TrialOutcome.heard); // 40 -> 30
      expect(engine.currentLevelDb, 30);

      engine.evaluateTrial(TrialOutcome.notHeard); // 30 -> 35
      expect(engine.currentLevelDb, 35);

      engine.evaluateTrial(TrialOutcome.heard); // 35 (1st asc) -> 25
      expect(engine.currentLevelDb, 25);

      engine.evaluateTrial(TrialOutcome.notHeard); // 25 -> 30
      expect(engine.currentLevelDb, 30);

      engine.evaluateTrial(TrialOutcome.notHeard); // 30 -> 35
      expect(engine.currentLevelDb, 35);

      final result = engine.evaluateTrial(TrialOutcome.heard); // 35 (2nd asc)
      expect(result, isA<StrategyThresholdFound>());
      final found = result as StrategyThresholdFound;
      expect(found.result.thresholdDb, 35);
      expect(found.result.ear, Ear.left);
      expect(found.result.frequencyHz, AudiometricFrequencies.freq1000Hz);
      expect(found.nextTarget?.ear, Ear.left);
      expect(found.nextTarget?.frequencyHz, AudiometricFrequencies.freq2000Hz);
    },
  );

  test('ear and frequency isolation verified across full protocol', () {
    expect(engine.currentEar, Ear.left);
    expect(engine.currentFrequencyHz, 1000);

    engine.evaluateTrial(TrialOutcome.heard);
    engine.evaluateTrial(TrialOutcome.notHeard);
    engine.evaluateTrial(TrialOutcome.heard);
    engine.evaluateTrial(TrialOutcome.notHeard);
    engine.evaluateTrial(TrialOutcome.notHeard);
    final r1 = engine.evaluateTrial(TrialOutcome.heard);
    expect(r1, isA<StrategyThresholdFound>());

    expect(engine.currentEar, Ear.left);
    expect(engine.currentFrequencyHz, 2000);
  });

  test('max trials guard prevents infinite search', () {
    final shortEngine = ModifiedHughsonWestlakeEngine(
      config: const ProtocolConfig(
        startingLevelDb: 40,
        maxTrialsPerTarget: 4,
        frequencies: [1000],
        ears: [Ear.left],
      ),
    );
    shortEngine.evaluateTrial(TrialOutcome.notHeard);
    shortEngine.evaluateTrial(TrialOutcome.notHeard);
    shortEngine.evaluateTrial(TrialOutcome.notHeard);
    final finalStep = shortEngine.evaluateTrial(TrialOutcome.notHeard);
    expect(
      finalStep is StrategyAllTargetsCompleted ||
          finalStep is StrategyMaxTrialsExceeded,
      isTrue,
    );
  });

  test(
    'backward compatible evaluateTrialStaircase returns StaircaseStepResult',
    () {
      final r = engine.evaluateTrialStaircase(TrialOutcome.heard);
      expect(r, isA<StaircaseNextTrial>());
      expect((r as StaircaseNextTrial).nextLevelDb, 30);
    },
  );
}
