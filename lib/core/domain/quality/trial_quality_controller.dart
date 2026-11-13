import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/foundation.dart';

/// Quality evaluation result for an individual presentation trial.
@immutable
class TrialQualityEvaluation {
  const TrialQualityEvaluation({
    required this.outcome,
    required this.isTrialValid,
    required this.latencyMs,
    required this.isPlausibleLatency,
    this.qualityFlags = const {},
    this.notes,
  });

  final TrialOutcome outcome;
  final bool isTrialValid;
  final int? latencyMs;
  final bool isPlausibleLatency;
  final Set<QualityFlag> qualityFlags;
  final String? notes;
}

/// Dedicated controller enforcing audio quality controls and trial validity safeguards.
///
/// - Rejects responses faster than physiological auditory reaction time (< 150ms).
/// - Invalidates trials contaminated by ambient noise spikes or disconnected headphones.
class TrialQualityController {
  const TrialQualityController({
    this.minPlausibleLatencyMs = 150,
    this.maxPlausibleLatencyMs = 3000,
  });

  final int minPlausibleLatencyMs;
  final int maxPlausibleLatencyMs;

  TrialQualityEvaluation evaluateTrialQuality({
    required bool userTappedHeard,
    required int? latencyMs,
    required NoiseAssessment noiseAssessment,
    required bool isNoiseDisturbedDuringTrial,
    required AudioRouteInfo? routeInfo,
    bool explicitNotHeard = false,
  }) {
    final flags = <QualityFlag>{};

    if (routeInfo == null || !routeInfo.routeType.isHeadphone) {
      flags.add(QualityFlag.audioRouteChangedDuringTest);
      return TrialQualityEvaluation(
        outcome: TrialOutcome.invalidInterrupted,
        isTrialValid: false,
        latencyMs: latencyMs,
        isPlausibleLatency: false,
        qualityFlags: Set.unmodifiable(flags),
        notes: 'Audio route invalid or headphone disconnected during trial',
      );
    }

    if (isNoiseDisturbedDuringTrial ||
        noiseAssessment == NoiseAssessment.invalid ||
        noiseAssessment == NoiseAssessment.suspect) {
      flags.add(QualityFlag.environmentalNoisePausesDetected);
      return TrialQualityEvaluation(
        outcome: TrialOutcome.contaminatedByNoise,
        isTrialValid: false,
        latencyMs: latencyMs,
        isPlausibleLatency: false,
        qualityFlags: Set.unmodifiable(flags),
        notes: 'Trial contaminated by ambient noise ($noiseAssessment)',
      );
    }

    if (explicitNotHeard) {
      return TrialQualityEvaluation(
        outcome: TrialOutcome.notHeard,
        isTrialValid: true,
        latencyMs: latencyMs,
        isPlausibleLatency: true,
        qualityFlags: Set.unmodifiable(flags),
        notes: 'User explicitly reported tone was not heard',
      );
    }

    if (!userTappedHeard) {
      return TrialQualityEvaluation(
        outcome: TrialOutcome.unansweredTimeout,
        isTrialValid: false,
        latencyMs: null,
        isPlausibleLatency: false,
        qualityFlags: Set.unmodifiable(flags),
        notes:
            'No response within presentation and response window (unanswered timeout)',
      );
    }

    final actualLatency = latencyMs ?? 0;
    final isAnticipatory = actualLatency < minPlausibleLatencyMs;
    final isExpired = actualLatency > maxPlausibleLatencyMs;

    if (isAnticipatory) {
      flags.add(QualityFlag.excessiveReversals);
      return TrialQualityEvaluation(
        outcome: TrialOutcome.invalidInterrupted,
        isTrialValid: false,
        latencyMs: actualLatency,
        isPlausibleLatency: false,
        qualityFlags: Set.unmodifiable(flags),
        notes: 'Anticipatory tap rejected (< ${minPlausibleLatencyMs}ms)',
      );
    } else if (isExpired) {
      return TrialQualityEvaluation(
        outcome: TrialOutcome.unansweredTimeout,
        isTrialValid: true,
        latencyMs: actualLatency,
        isPlausibleLatency: false,
        qualityFlags: Set.unmodifiable(flags),
        notes: 'Response arrived after cutoff window (> ${maxPlausibleLatencyMs}ms)',
      );
    } else {
      return TrialQualityEvaluation(
        outcome: TrialOutcome.heard,
        isTrialValid: true,
        latencyMs: actualLatency,
        isPlausibleLatency: true,
        qualityFlags: Set.unmodifiable(flags),
        notes: 'Valid response confirmed (latency: ${actualLatency}ms)',
      );
    }
  }
}

