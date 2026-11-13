import 'dart:math' as math;

import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:flutter/foundation.dart';

/// Midpoint rounding policy for binary search interval halving.
enum MidpointRoundingPolicy { roundUp, roundDown, snapGridUp, snapGridDown }

/// Configuration for the Binary Search Refinement strategy.
@immutable
class BinarySearchConfig {
  const BinarySearchConfig({
    this.startingLevelDb = 40,
    this.bracketStepDb = 20,
    this.resolutionDb = 5,
    this.minLevelDb = 0,
    this.maxLevelDb = 80,
    this.maxTrialsPerTarget = 18,
    this.midpointRounding = MidpointRoundingPolicy.roundUp,
    this.gridStepDb = 5,
    this.frequencies = AudiometricFrequencies.defaultScreeningFrequencies,
    this.ears = const [Ear.left, Ear.right],
    this.strategyVersion = 'BSR-2026-v1.0-experimental',
  });

  final int startingLevelDb;
  final int bracketStepDb;
  final int resolutionDb;
  final int minLevelDb;
  final int maxLevelDb;
  final int maxTrialsPerTarget;
  final MidpointRoundingPolicy midpointRounding;
  final int gridStepDb;
  final List<int> frequencies;
  final List<Ear> ears;
  final String strategyVersion;
}

/// Internal tracking state of the bracket for a single target (ear + frequency).
class TargetBracketState {
  TargetBracketState({
    required this.ear,
    required this.frequencyHz,
    this.lowerInaudibleDb,
    this.upperAudibleDb,
    this.isBracketEstablished = false,
    this.isResolved = false,
    this.isInconclusive = false,
    this.inconclusiveReason,
  });

  final Ear ear;
  final int frequencyHz;
  int? lowerInaudibleDb;
  int? upperAudibleDb;
  bool isBracketEstablished;
  bool isResolved;
  bool isInconclusive;
  String? inconclusiveReason;
}

/// Experimental binary-search refinement threshold estimation strategy.
class BinarySearchStrategy implements ThresholdEstimationStrategy {
  BinarySearchStrategy({this.config = const BinarySearchConfig()})
    : _currentLevelDb = config.startingLevelDb {
    _activeBracket = TargetBracketState(
      ear: currentEar,
      frequencyHz: currentFrequencyHz,
    );
  }

  final BinarySearchConfig config;

  @override
  StrategyType get strategyType => StrategyType.binarySearchRefinement;

  @override
  String get strategyVersion => config.strategyVersion;

  int _earIndex = 0;
  int _frequencyIndex = 0;
  int _currentLevelDb;
  late TargetBracketState _activeBracket;

  final List<TrialRecord> _allTrials = [];
  final List<ThresholdResult> _thresholdResults = [];

  @override
  Ear get currentEar => _earIndex < config.ears.length
      ? config.ears[_earIndex]
      : config.ears.last;

  @override
  int get currentFrequencyHz => _frequencyIndex < config.frequencies.length
      ? config.frequencies[_frequencyIndex]
      : config.frequencies.last;

  @override
  int get currentLevelDb => _currentLevelDb;

  @override
  List<TrialRecord> get allTrials => List.unmodifiable(_allTrials);

  @override
  List<ThresholdResult> get thresholdResults =>
      List.unmodifiable(_thresholdResults);

  List<TrialRecord> get currentTargetTrials => _allTrials
      .where((t) => t.ear == currentEar && t.frequencyHz == currentFrequencyHz)
      .toList();

  @override
  StrategyResult evaluateTrial(
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
      return StrategyNextTrial(
        ear: currentEar,
        frequencyHz: currentFrequencyHz,
        nextLevelDb: _currentLevelDb,
      );
    }

    final validTargetTrials = currentTargetTrials
        .where(
          (t) =>
              t.outcome == TrialOutcome.heard ||
              t.outcome == TrialOutcome.notHeard ||
              t.outcome == TrialOutcome.unansweredTimeout,
        )
        .toList();

    if (validTargetTrials.length >= config.maxTrialsPerTarget) {
      final targetEar = currentEar;
      final targetFreq = currentFrequencyHz;
      final next = _advanceToNextTarget();
      return StrategyMaxTrialsExceeded(
        ear: targetEar,
        frequencyHz: targetFreq,
        nextTarget: next,
      );
    }

    if (!_activeBracket.isBracketEstablished) {
      return _processInitialBracketPhase(outcome, validTargetTrials.length);
    }
    return _processBinaryRefinementPhase(outcome, validTargetTrials.length);
  }

  StrategyResult _processInitialBracketPhase(
    TrialOutcome outcome,
    int validTrialCount,
  ) {
    switch (outcome) {
      case TrialOutcome.heard:
        final prevAudible = _activeBracket.upperAudibleDb;
        _activeBracket.upperAudibleDb = prevAudible == null
            ? _currentLevelDb
            : math.min(prevAudible, _currentLevelDb);

        if (_activeBracket.lowerInaudibleDb != null &&
            _activeBracket.lowerInaudibleDb! < _activeBracket.upperAudibleDb!) {
          _activeBracket.isBracketEstablished = true;
          return _checkRefinementOrNextStep(validTrialCount);
        }

        final nextLevel = _currentLevelDb - config.bracketStepDb;
        if (_currentLevelDb <= config.minLevelDb ||
            nextLevel < config.minLevelDb) {
          _activeBracket.isInconclusive = true;
          _activeBracket.inconclusiveReason =
              'Hearing detected at or below floor level (${config.minLevelDb} dBFS). Inaudible bound cannot be bracketed.';
          final targetEar = currentEar;
          final targetFreq = currentFrequencyHz;
          final nextTarget = _advanceToNextTarget();
          return StrategyInconclusive(
            ear: targetEar,
            frequencyHz: targetFreq,
            reason: _activeBracket.inconclusiveReason!,
            nextTarget: nextTarget,
          );
        }

        _currentLevelDb = math.max(config.minLevelDb, nextLevel);
        return StrategyNextTrial(
          ear: currentEar,
          frequencyHz: currentFrequencyHz,
          nextLevelDb: _currentLevelDb,
        );

      case TrialOutcome.notHeard:
      case TrialOutcome.unansweredTimeout:
        final prevInaudible = _activeBracket.lowerInaudibleDb;
        _activeBracket.lowerInaudibleDb = prevInaudible == null
            ? _currentLevelDb
            : math.max(prevInaudible, _currentLevelDb);

        if (_activeBracket.upperAudibleDb != null &&
            _activeBracket.lowerInaudibleDb! < _activeBracket.upperAudibleDb!) {
          _activeBracket.isBracketEstablished = true;
          return _checkRefinementOrNextStep(validTrialCount);
        }

        final nextLevel = _currentLevelDb + config.bracketStepDb;
        if (_currentLevelDb >= config.maxLevelDb ||
            nextLevel > config.maxLevelDb) {
          _activeBracket.isInconclusive = true;
          _activeBracket.inconclusiveReason =
              'Non-response at or above ceiling level (${config.maxLevelDb} dBFS). Audible bound cannot be bracketed.';
          final targetEar = currentEar;
          final targetFreq = currentFrequencyHz;
          final nextTarget = _advanceToNextTarget();
          return StrategyInconclusive(
            ear: targetEar,
            frequencyHz: targetFreq,
            reason: _activeBracket.inconclusiveReason!,
            nextTarget: nextTarget,
          );
        }

        _currentLevelDb = math.min(config.maxLevelDb, nextLevel);
        return StrategyNextTrial(
          ear: currentEar,
          frequencyHz: currentFrequencyHz,
          nextLevelDb: _currentLevelDb,
        );

      case TrialOutcome.contaminatedByNoise:
      case TrialOutcome.invalidInterrupted:
        return StrategyNextTrial(
          ear: currentEar,
          frequencyHz: currentFrequencyHz,
          nextLevelDb: _currentLevelDb,
        );
    }
  }

  StrategyResult _processBinaryRefinementPhase(
    TrialOutcome outcome,
    int validTrialCount,
  ) {
    switch (outcome) {
      case TrialOutcome.heard:
        _activeBracket.upperAudibleDb = _currentLevelDb;
        break;
      case TrialOutcome.notHeard:
      case TrialOutcome.unansweredTimeout:
        _activeBracket.lowerInaudibleDb = _currentLevelDb;
        break;
      case TrialOutcome.contaminatedByNoise:
      case TrialOutcome.invalidInterrupted:
        break;
    }
    return _checkRefinementOrNextStep(validTrialCount);
  }

  StrategyResult _checkRefinementOrNextStep(int validTrialCount) {
    final lower = _activeBracket.lowerInaudibleDb;
    final upper = _activeBracket.upperAudibleDb;
    if (lower == null || upper == null) {
      return StrategyNextTrial(
        ear: currentEar,
        frequencyHz: currentFrequencyHz,
        nextLevelDb: _currentLevelDb,
      );
    }

    final span = upper - lower;
    if (span <= config.resolutionDb) {
      return _commitBracketResult(lower, upper, validTrialCount);
    }

    final mid = calculateMidpoint(
      lower,
      upper,
      config.midpointRounding,
      gridStepDb: config.gridStepDb,
    );

    if (mid <= lower || mid >= upper) {
      return _commitBracketResult(lower, upper, validTrialCount);
    }

    _currentLevelDb = mid;
    return StrategyNextTrial(
      ear: currentEar,
      frequencyHz: currentFrequencyHz,
      nextLevelDb: _currentLevelDb,
    );
  }

  StrategyResult _commitBracketResult(
    int lower,
    int upper,
    int validTrialCount,
  ) {
    final threshold = ThresholdResult(
      ear: currentEar,
      frequencyHz: currentFrequencyHz,
      thresholdDb: upper,
      validAscendingResponses: 1,
      totalTrialsForTarget: validTrialCount,
      method: 'BINARY_SEARCH_REFINEMENT',
      confidence: 'EXPERIMENTAL_BINARY_REFINED',
      strategyVersion: strategyVersion,
      bracketLowerDb: lower,
      bracketUpperDb: upper,
    );
    _thresholdResults.add(threshold);
    _activeBracket.isResolved = true;

    final next = _advanceToNextTarget();
    if (next != null) {
      return StrategyThresholdFound(result: threshold, nextTarget: next);
    }
    return const StrategyAllTargetsCompleted();
  }

  int calculateMidpoint(
    int lower,
    int upper,
    MidpointRoundingPolicy policy, {
    int gridStepDb = 5,
  }) {
    final rawMid = (lower + upper) / 2.0;
    return switch (policy) {
      MidpointRoundingPolicy.roundUp => rawMid.ceil(),
      MidpointRoundingPolicy.roundDown => rawMid.floor(),
      MidpointRoundingPolicy.snapGridUp =>
        ((rawMid / gridStepDb).ceil() * gridStepDb).toInt(),
      MidpointRoundingPolicy.snapGridDown =>
        ((rawMid / gridStepDb).floor() * gridStepDb).toInt(),
    };
  }

  TargetPair? _advanceToNextTarget() {
    _frequencyIndex++;
    if (_frequencyIndex < config.frequencies.length) {
      _initTargetBracket();
      return TargetPair(currentEar, currentFrequencyHz);
    }

    _frequencyIndex = 0;
    _earIndex++;
    if (_earIndex < config.ears.length) {
      _initTargetBracket();
      return TargetPair(currentEar, currentFrequencyHz);
    }

    return null;
  }

  void _initTargetBracket() {
    if (!isComplete()) {
      _activeBracket = TargetBracketState(
        ear: currentEar,
        frequencyHz: currentFrequencyHz,
      );
      _currentLevelDb = config.startingLevelDb;
    }
  }

  @override
  bool isComplete() => _earIndex >= config.ears.length;

  @override
  void reset() {
    _earIndex = 0;
    _frequencyIndex = 0;
    _currentLevelDb = config.startingLevelDb;
    _allTrials.clear();
    _thresholdResults.clear();
    _initTargetBracket();
  }

  TargetBracketState getActiveBracket() => _activeBracket;
}

