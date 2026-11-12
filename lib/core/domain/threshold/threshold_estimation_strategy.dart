import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/foundation.dart';

/// Identifies the threshold estimation algorithm in use.
enum StrategyType {
  modifiedHughsonWestlake('Modified Hughson–Westlake (Staircase)'),
  binarySearchRefinement('Binary Search Refinement (Experimental)');

  const StrategyType(this.displayName);
  final String displayName;
}

@immutable
class TargetPair {
  const TargetPair(this.ear, this.frequencyHz);

  final Ear ear;
  final int frequencyHz;

  @override
  bool operator ==(Object other) =>
      other is TargetPair &&
      other.ear == ear &&
      other.frequencyHz == frequencyHz;

  @override
  int get hashCode => Object.hash(ear, frequencyHz);

  @override
  String toString() => 'TargetPair($ear, $frequencyHz)';
}

/// Result of a single strategy evaluation step.
sealed class StrategyResult {
  const StrategyResult();
}

final class StrategyNextTrial extends StrategyResult {
  const StrategyNextTrial({
    required this.ear,
    required this.frequencyHz,
    required this.nextLevelDb,
  });
  final Ear ear;
  final int frequencyHz;
  final int nextLevelDb;
}

final class StrategyThresholdFound extends StrategyResult {
  const StrategyThresholdFound({
    required this.result,
    required this.nextTarget,
  });
  final ThresholdResult result;
  final TargetPair? nextTarget;
}

final class StrategyMaxTrialsExceeded extends StrategyResult {
  const StrategyMaxTrialsExceeded({
    required this.ear,
    required this.frequencyHz,
    required this.nextTarget,
  });
  final Ear ear;
  final int frequencyHz;
  final TargetPair? nextTarget;
}

final class StrategyInconclusive extends StrategyResult {
  const StrategyInconclusive({
    required this.ear,
    required this.frequencyHz,
    required this.reason,
    required this.nextTarget,
  });
  final Ear ear;
  final int frequencyHz;
  final String reason;
  final TargetPair? nextTarget;
}

final class StrategyAllTargetsCompleted extends StrategyResult {
  const StrategyAllTargetsCompleted();
}

/// Common contract for threshold estimation strategies.
abstract interface class ThresholdEstimationStrategy {
  StrategyType get strategyType;
  String get strategyVersion;
  Ear get currentEar;
  int get currentFrequencyHz;
  int get currentLevelDb;
  List<TrialRecord> get allTrials;
  List<ThresholdResult> get thresholdResults;
  bool isComplete();

  StrategyResult evaluateTrial(
    TrialOutcome outcome, {
    int? latencyMs,
    double? ambientNoiseDbFs,
  });

  void reset();
}
