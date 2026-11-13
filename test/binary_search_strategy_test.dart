import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/threshold/binary_search_strategy.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'initial bracket established when user hears at 40 dB and steps down to inaudible at 20 dB',
    () {
      final strategy = BinarySearchStrategy(
        config: const BinarySearchConfig(
          startingLevelDb: 40,
          bracketStepDb: 20,
          resolutionDb: 5,
          frequencies: [1000],
          ears: [Ear.left],
        ),
      );

      expect(strategy.currentLevelDb, 40);
      final r1 = strategy.evaluateTrial(TrialOutcome.heard);
      expect(r1, isA<StrategyNextTrial>());
      expect(strategy.currentLevelDb, 20);
      expect(strategy.getActiveBracket().isBracketEstablished, isFalse);
      expect(strategy.getActiveBracket().upperAudibleDb, 40);
      expect(strategy.getActiveBracket().lowerInaudibleDb, isNull);

      final r2 = strategy.evaluateTrial(TrialOutcome.notHeard);
      expect(strategy.getActiveBracket().isBracketEstablished, isTrue);
      expect(strategy.getActiveBracket().lowerInaudibleDb, 20);
      expect(strategy.getActiveBracket().upperAudibleDb, 40);
      expect(r2, isA<StrategyNextTrial>());
      expect(strategy.currentLevelDb, 30);
    },
  );

  test(
    'initial bracket established when user does not hear at 40 dB and steps up to audible at 60 dB',
    () {
      final strategy = BinarySearchStrategy(
        config: const BinarySearchConfig(
          startingLevelDb: 40,
          bracketStepDb: 20,
          resolutionDb: 5,
          frequencies: [1000],
          ears: [Ear.left],
        ),
      );

      expect(strategy.currentLevelDb, 40);
      final r1 = strategy.evaluateTrial(TrialOutcome.notHeard);
      expect(r1, isA<StrategyNextTrial>());
      expect(strategy.currentLevelDb, 60);
      expect(strategy.getActiveBracket().isBracketEstablished, isFalse);
      expect(strategy.getActiveBracket().lowerInaudibleDb, 40);
      expect(strategy.getActiveBracket().upperAudibleDb, isNull);

      final r2 = strategy.evaluateTrial(TrialOutcome.heard);
      expect(strategy.getActiveBracket().isBracketEstablished, isTrue);
      expect(strategy.getActiveBracket().lowerInaudibleDb, 40);
      expect(strategy.getActiveBracket().upperAudibleDb, 60);
      expect(r2, isA<StrategyNextTrial>());
      expect(strategy.currentLevelDb, 50);
    },
  );

  test(
    'contaminated and invalid trials never alter bracket bounds or presentation level',
    () {
      final strategy = BinarySearchStrategy(
        config: const BinarySearchConfig(
          startingLevelDb: 40,
          bracketStepDb: 20,
          frequencies: [1000],
          ears: [Ear.left],
        ),
      );

      final r1 = strategy.evaluateTrial(
        TrialOutcome.contaminatedByNoise,
        ambientNoiseDbFs: -25.0,
      );
      expect(r1, isA<StrategyNextTrial>());
      expect(strategy.currentLevelDb, 40);
      expect(strategy.getActiveBracket().lowerInaudibleDb, isNull);
      expect(strategy.getActiveBracket().upperAudibleDb, isNull);

      strategy.evaluateTrial(TrialOutcome.heard);
      expect(strategy.currentLevelDb, 20);
      expect(strategy.getActiveBracket().upperAudibleDb, 40);

      final r3 = strategy.evaluateTrial(TrialOutcome.invalidInterrupted);
      expect(r3, isA<StrategyNextTrial>());
      expect(strategy.currentLevelDb, 20);
      expect(strategy.getActiveBracket().lowerInaudibleDb, isNull);
      expect(strategy.getActiveBracket().upperAudibleDb, 40);
    },
  );

  test('floor limit reached without inaudible response produces Inconclusive', () {
    final strategy = BinarySearchStrategy(
      config: const BinarySearchConfig(
        startingLevelDb: 20,
        bracketStepDb: 20,
        minLevelDb: 0,
        frequencies: [1000],
        ears: [Ear.left],
      ),
    );

    strategy.evaluateTrial(TrialOutcome.heard);
    expect(strategy.currentLevelDb, 0);

    final r2 = strategy.evaluateTrial(TrialOutcome.heard);
    expect(r2, isA<StrategyInconclusive>());
    final inc = r2 as StrategyInconclusive;
    expect(inc.ear, Ear.left);
    expect(inc.frequencyHz, 1000);
    expect(inc.reason, contains('floor level'));
  });

  test('ceiling limit reached without audible response produces Inconclusive', () {
    final strategy = BinarySearchStrategy(
      config: const BinarySearchConfig(
        startingLevelDb: 60,
        bracketStepDb: 20,
        maxLevelDb: 80,
        frequencies: [1000],
        ears: [Ear.left],
      ),
    );

    strategy.evaluateTrial(TrialOutcome.notHeard);
    expect(strategy.currentLevelDb, 80);

    final r2 = strategy.evaluateTrial(TrialOutcome.notHeard);
    expect(r2, isA<StrategyInconclusive>());
    final inc = r2 as StrategyInconclusive;
    expect(inc.ear, Ear.left);
    expect(inc.frequencyHz, 1000);
    expect(inc.reason, contains('ceiling level'));
  });

  test(
    'midpoint rounding deterministic test - 60 to 65 bracket with ROUND_UP policy',
    () {
      const configRoundUp = BinarySearchConfig(
        startingLevelDb: 65,
        bracketStepDb: 5,
        resolutionDb: 2,
        midpointRounding: MidpointRoundingPolicy.roundUp,
        frequencies: [1000],
        ears: [Ear.left],
      );

      final strategyA = BinarySearchStrategy(config: configRoundUp);
      strategyA.evaluateTrial(TrialOutcome.heard);
      strategyA.evaluateTrial(TrialOutcome.notHeard);
      expect(strategyA.getActiveBracket().isBracketEstablished, isTrue);
      expect(strategyA.getActiveBracket().lowerInaudibleDb, 60);
      expect(strategyA.getActiveBracket().upperAudibleDb, 65);
      expect(strategyA.currentLevelDb, 63);

      strategyA.evaluateTrial(TrialOutcome.heard);
      expect(strategyA.getActiveBracket().lowerInaudibleDb, 60);
      expect(strategyA.getActiveBracket().upperAudibleDb, 63);

      final strategyB = BinarySearchStrategy(config: configRoundUp);
      strategyB.evaluateTrial(TrialOutcome.heard);
      strategyB.evaluateTrial(TrialOutcome.notHeard);
      expect(strategyB.currentLevelDb, 63);

      strategyB.evaluateTrial(TrialOutcome.notHeard);
      expect(strategyB.getActiveBracket().lowerInaudibleDb, 63);
      expect(strategyB.getActiveBracket().upperAudibleDb, 65);
    },
  );

  test(
    'midpoint rounding deterministic test - 60 to 65 bracket with ROUND_DOWN policy',
    () {
      final strategy = BinarySearchStrategy(
        config: const BinarySearchConfig(
          startingLevelDb: 65,
          bracketStepDb: 5,
          resolutionDb: 2,
          midpointRounding: MidpointRoundingPolicy.roundDown,
          frequencies: [1000],
          ears: [Ear.left],
        ),
      );
      strategy.evaluateTrial(TrialOutcome.heard);
      strategy.evaluateTrial(TrialOutcome.notHeard);
      expect(strategy.currentLevelDb, 62);

      strategy.evaluateTrial(TrialOutcome.heard);
      expect(strategy.getActiveBracket().lowerInaudibleDb, 60);
      expect(strategy.getActiveBracket().upperAudibleDb, 62);
    },
  );

  test('midpoint calculation helper direct verification', () {
    final strategy = BinarySearchStrategy();
    expect(strategy.calculateMidpoint(60, 65, MidpointRoundingPolicy.roundUp), 63);
    expect(
      strategy.calculateMidpoint(60, 65, MidpointRoundingPolicy.roundDown),
      62,
    );
    expect(
      strategy.calculateMidpoint(
        60,
        65,
        MidpointRoundingPolicy.snapGridUp,
        gridStepDb: 5,
      ),
      65,
    );
    expect(
      strategy.calculateMidpoint(
        60,
        65,
        MidpointRoundingPolicy.snapGridDown,
        gridStepDb: 5,
      ),
      60,
    );
  });

  test('converges to threshold when span is less than or equal to resolution', () {
    final strategy = BinarySearchStrategy(
      config: const BinarySearchConfig(
        startingLevelDb: 40,
        bracketStepDb: 20,
        resolutionDb: 5,
        frequencies: [1000],
        ears: [Ear.left],
      ),
    );
    strategy.evaluateTrial(TrialOutcome.heard);
    strategy.evaluateTrial(TrialOutcome.notHeard);
    expect(strategy.currentLevelDb, 30);

    strategy.evaluateTrial(TrialOutcome.notHeard);
    expect(strategy.currentLevelDb, 35);

    final res = strategy.evaluateTrial(TrialOutcome.heard);
    expect(res, isA<StrategyAllTargetsCompleted>());
    expect(strategy.thresholdResults.length, 1);
    final threshold = strategy.thresholdResults.first;
    expect(threshold.thresholdDb, 35);
    expect(threshold.bracketLowerDb, 30);
    expect(threshold.bracketUpperDb, 35);
    expect(threshold.method, 'BINARY_SEARCH_REFINEMENT');
  });
}

