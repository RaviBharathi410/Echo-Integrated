import 'dart:math' as math;

import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:flutter/foundation.dart';

/// Configuration parameters for the Modified Hughson-Westlake staircase protocol.
@immutable
class ProtocolConfig {
  const ProtocolConfig({
    this.startingLevelDb = 40,
    this.downStepDb = 10,
    this.upStepDb = 5,
    this.minLevelDb = 0,
    this.maxLevelDb = 80,
    this.requiredAscendingResponses = 2,
    this.maxTrialsPerTarget = 18,
    this.frequencies = AudiometricFrequencies.defaultScreeningFrequencies,
    this.ears = const [Ear.left, Ear.right],
    this.protocolVersion = 'HW-2026-v1-provisional',
    this.supportedLevels = const [],
  });

  final int startingLevelDb;
  final int downStepDb;
  final int upStepDb;
  final int minLevelDb;
  final int maxLevelDb;
  final int requiredAscendingResponses;
  final int maxTrialsPerTarget;
  final List<int> frequencies;
  final List<Ear> ears;
  final String protocolVersion;
  final List<int> supportedLevels;
}

/// Result of evaluating a trial within the staircase search.
sealed class StaircaseStepResult {
  const StaircaseStepResult();
}

final class StaircaseNextTrial extends StaircaseStepResult {
  const StaircaseNextTrial(this.ear, this.frequencyHz, this.nextLevelDb);
  final Ear ear;
  final int frequencyHz;
  final int nextLevelDb;
}

final class StaircaseThresholdFound extends StaircaseStepResult {
  const StaircaseThresholdFound(this.result, this.nextTarget);
  final ThresholdResult result;
  final TargetPair? nextTarget;
}

final class StaircaseMaxTrialsExceeded extends StaircaseStepResult {
  const StaircaseMaxTrialsExceeded(this.ear, this.frequencyHz, this.nextTarget);
  final Ear ear;
  final int frequencyHz;
  final TargetPair? nextTarget;
}

final class StaircaseAllTargetsCompleted extends StaircaseStepResult {
  const StaircaseAllTargetsCompleted();
}

/// Pure, deterministic Modified Hughson-Westlake threshold search engine.
class ModifiedHughsonWestlakeEngine implements ThresholdEstimationStrategy {
  ModifiedHughsonWestlakeEngine({this.config = const ProtocolConfig()})
    : _currentLevelDb = config.startingLevelDb,
      _previousLevelDb = config.startingLevelDb;

  final ProtocolConfig config;

  @override
  StrategyType get strategyType => StrategyType.modifiedHughsonWestlake;

  @override
  String get strategyVersion => 'MHW-2026-v1.1';

  int _earIndex = 0;
  int _frequencyIndex = 0;
  int _currentLevelDb;
  int _previousLevelDb;
  bool _wasLastStepAscending = false;

  final Map<int, int> _ascendingResponsesAtLevel = {};
  final List<TrialRecord> _allTrials = [];
  final List<ThresholdResult> _thresholdResults = [];

  @override
  int get currentLevelDb => _currentLevelDb;

  int get previousLevelDb => _previousLevelDb;

  @override
  List<TrialRecord> get allTrials => List.unmodifiable(_allTrials);

  @override
  List<ThresholdResult> get thresholdResults =>
      List.unmodifiable(_thresholdResults);

  @override
  Ear get currentEar => config.ears[_earIndex];

  @override
  int get currentFrequencyHz => config.frequencies[_frequencyIndex];

  List<TrialRecord> get currentTargetTrials => _allTrials
      .where((t) => t.ear == currentEar && t.frequencyHz == currentFrequencyHz)
      .toList();

  StaircaseStepResult evaluateTrialStaircase(
    TrialOutcome outcome, {
    int? latencyMs,
    double? ambientNoiseDbFs,
  }) {
    final trialNumber = _allTrials.length + 1;
    final record = TrialRecord(
      trialNumber: trialNumber,
      ear: currentEar,
      frequencyHz: currentFrequencyHz,
      levelDb: _currentLevelDb,
      outcome: outcome,
      latencyMs: latencyMs,
      ambientNoiseLevelDbFs: ambientNoiseDbFs,
    );
    _allTrials.add(record);

    if (outcome == TrialOutcome.contaminatedByNoise ||
        outcome == TrialOutcome.invalidInterrupted) {
      return StaircaseNextTrial(currentEar, currentFrequencyHz, _currentLevelDb);
    }

    final targetTrials = currentTargetTrials
        .where(
          (t) =>
              t.outcome == TrialOutcome.heard ||
              t.outcome == TrialOutcome.notHeard ||
              t.outcome == TrialOutcome.unansweredTimeout,
        )
        .toList();

    if (targetTrials.length >= config.maxTrialsPerTarget) {
      final nextTarget = _advanceToNextTarget();
      if (nextTarget != null) {
        return StaircaseMaxTrialsExceeded(
          record.ear,
          record.frequencyHz,
          nextTarget,
        );
      }
      return const StaircaseAllTargetsCompleted();
    }

    switch (outcome) {
      case TrialOutcome.heard:
        if (_wasLastStepAscending) {
          final count = (_ascendingResponsesAtLevel[_currentLevelDb] ?? 0) + 1;
          _ascendingResponsesAtLevel[_currentLevelDb] = count;

          if (count >= config.requiredAscendingResponses) {
            final threshold = ThresholdResult(
              ear: currentEar,
              frequencyHz: currentFrequencyHz,
              thresholdDb: _currentLevelDb,
              validAscendingResponses: count,
              totalTrialsForTarget: targetTrials.length,
              method: 'MODIFIED_HUGHSON_WESTLAKE',
              strategyVersion: strategyVersion,
            );
            _thresholdResults.add(threshold);
            final next = _advanceToNextTarget();
            if (next != null) {
              return StaircaseThresholdFound(threshold, next);
            }
            return const StaircaseAllTargetsCompleted();
          }
        }

        _previousLevelDb = _currentLevelDb;
        _currentLevelDb = math.max(
          config.minLevelDb,
          _currentLevelDb - config.downStepDb,
        );
        _wasLastStepAscending = false;
        break;

      case TrialOutcome.notHeard:
      case TrialOutcome.unansweredTimeout:
        _previousLevelDb = _currentLevelDb;
        _currentLevelDb = math.min(
          config.maxLevelDb,
          _currentLevelDb + config.upStepDb,
        );
        _wasLastStepAscending = true;
        break;

      case TrialOutcome.contaminatedByNoise:
      case TrialOutcome.invalidInterrupted:
        break;
    }

    return StaircaseNextTrial(currentEar, currentFrequencyHz, _currentLevelDb);
  }

  @override
  StrategyResult evaluateTrial(
    TrialOutcome outcome, {
    int? latencyMs,
    double? ambientNoiseDbFs,
  }) {
    final result = evaluateTrialStaircase(
      outcome,
      latencyMs: latencyMs,
      ambientNoiseDbFs: ambientNoiseDbFs,
    );
    return switch (result) {
      StaircaseNextTrial(:final ear, :final frequencyHz, :final nextLevelDb) =>
        StrategyNextTrial(
          ear: ear,
          frequencyHz: frequencyHz,
          nextLevelDb: nextLevelDb,
        ),
      StaircaseThresholdFound(:final result, :final nextTarget) =>
        StrategyThresholdFound(result: result, nextTarget: nextTarget),
      StaircaseMaxTrialsExceeded(
        :final ear,
        :final frequencyHz,
        :final nextTarget,
      ) =>
        StrategyMaxTrialsExceeded(
          ear: ear,
          frequencyHz: frequencyHz,
          nextTarget: nextTarget,
        ),
      StaircaseAllTargetsCompleted() => const StrategyAllTargetsCompleted(),
    };
  }

  TargetPair? _advanceToNextTarget() {
    _ascendingResponsesAtLevel.clear();
    _wasLastStepAscending = false;
    _currentLevelDb = config.startingLevelDb;
    _previousLevelDb = config.startingLevelDb;

    _frequencyIndex++;
    if (_frequencyIndex < config.frequencies.length) {
      return TargetPair(currentEar, currentFrequencyHz);
    }

    _frequencyIndex = 0;
    _earIndex++;
    if (_earIndex < config.ears.length) {
      return TargetPair(currentEar, currentFrequencyHz);
    }

    return null;
  }

  @override
  bool isComplete() => _earIndex >= config.ears.length;

  @override
  void reset() {
    _earIndex = 0;
    _frequencyIndex = 0;
    _currentLevelDb = config.startingLevelDb;
    _previousLevelDb = config.startingLevelDb;
    _wasLastStepAscending = false;
    _ascendingResponsesAtLevel.clear();
    _allTrials.clear();
    _thresholdResults.clear();
  }
}

