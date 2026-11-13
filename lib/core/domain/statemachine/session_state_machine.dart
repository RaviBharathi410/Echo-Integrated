import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/foundation.dart';

/// Explicit, typed session states representing the lifecycle of an audiometric screening.
enum SessionState {
  notStarted,
  onboardingConsent,
  deviceReadiness,
  calibrationGate,
  environmentalNoiseCheck,
  testPrep,
  practicePresentation,
  practiceFeedback,
  stimulusPresentation,
  waitingForResponse,
  trialValidation,
  automaticPauseNoise,
  automaticPauseDevice,
  recoveryRecheck,
  thresholdEstimation,
  results,
  completed,
  cancelled,
  aborted,
}

/// Domain events that trigger state transitions.
sealed class SessionEvent {
  const SessionEvent();
}

final class StartOnboardingEvent extends SessionEvent {
  const StartOnboardingEvent();
}

final class ConsentAgreedEvent extends SessionEvent {
  const ConsentAgreedEvent(this.agreed);
  final bool agreed;
}

final class DeviceEvaluatedEvent extends SessionEvent {
  const DeviceEvaluatedEvent({required this.route, required this.isSupported});
  final AudioRouteInfo route;
  final bool isSupported;
}

final class CalibrationEvaluatedEvent extends SessionEvent {
  const CalibrationEvaluatedEvent(this.calibration);
  final CalibrationInfo calibration;
}

final class NoiseBaselineCheckedEvent extends SessionEvent {
  const NoiseBaselineCheckedEvent(this.assessment);
  final NoiseAssessment assessment;
}

final class StartPracticeEvent extends SessionEvent {
  const StartPracticeEvent();
}

final class PracticeResponseReceivedEvent extends SessionEvent {
  const PracticeResponseReceivedEvent({
    required this.heard,
    required this.latencyMs,
  });
  final bool heard;
  final int latencyMs;
}

final class FinishPracticeEvent extends SessionEvent {
  const FinishPracticeEvent();
}

final class StartTestEvent extends SessionEvent {
  const StartTestEvent();
}

final class PrepareTrialEvent extends SessionEvent {
  const PrepareTrialEvent({
    required this.ear,
    required this.frequencyHz,
    required this.levelDb,
  });
  final Ear ear;
  final int frequencyHz;
  final int levelDb;
}

final class StimulusStartedEvent extends SessionEvent {
  const StimulusStartedEvent();
}

final class StimulusEndedEvent extends SessionEvent {
  const StimulusEndedEvent();
}

final class UserRespondedHeardEvent extends SessionEvent {
  const UserRespondedHeardEvent(this.latencyMs);
  final int latencyMs;
}

final class UserRespondedNotHeardEvent extends SessionEvent {
  const UserRespondedNotHeardEvent(this.latencyMs);
  final int latencyMs;
}

final class ResponseTimedOutEvent extends SessionEvent {
  const ResponseTimedOutEvent();
}

final class NoiseDisturbanceDetectedEvent extends SessionEvent {
  const NoiseDisturbanceDetectedEvent(this.overlapsStimulus);
  final bool overlapsStimulus;
}

final class DeviceDisconnectedEvent extends SessionEvent {
  const DeviceDisconnectedEvent();
}

final class NoiseRecoveredEvent extends SessionEvent {
  const NoiseRecoveredEvent(this.isStable);
  final bool isStable;
}

final class ResumeRequestedEvent extends SessionEvent {
  const ResumeRequestedEvent();
}

final class TargetThresholdFoundEvent extends SessionEvent {
  const TargetThresholdFoundEvent();
}

final class NextTrialNeededEvent extends SessionEvent {
  const NextTrialNeededEvent();
}

final class AllTargetsCompletedEvent extends SessionEvent {
  const AllTargetsCompletedEvent();
}

final class CancelRequestedEvent extends SessionEvent {
  const CancelRequestedEvent();
}

final class RestartRequestedEvent extends SessionEvent {
  const RestartRequestedEvent();
}

final class RetrySessionEvent extends SessionEvent {
  const RetrySessionEvent();
}

/// Result of attempting a state transition.
@immutable
class StateTransitionResult {
  const StateTransitionResult({
    required this.previousState,
    required this.newState,
    required this.event,
    this.isIllegal = false,
    this.errorMessage,
  });

  final SessionState previousState;
  final SessionState newState;
  final SessionEvent event;
  final bool isIllegal;
  final String? errorMessage;
}

/// Finite state machine enforcing legal transitions and audit trail.
class SessionStateMachine {
  SessionStateMachine({SessionState initialState = SessionState.notStarted})
    : _currentState = initialState;

  SessionState _currentState;
  SessionState get currentState => _currentState;

  final List<StateTransitionResult> _transitionHistory = [];
  List<StateTransitionResult> get transitionHistory =>
      List.unmodifiable(_transitionHistory);

  bool canTransition(SessionEvent event) {
    return _determineNextState(_currentState, event) != null;
  }

  /// Attempts a transition with the given event.
  /// Throws [StateError] if the transition is invalid, preserving strict contract.
  StateTransitionResult transition(SessionEvent event) {
    final next = _determineNextState(_currentState, event);
    if (next == null) {
      final failure = StateTransitionResult(
        previousState: _currentState,
        newState: _currentState,
        event: event,
        isIllegal: true,
        errorMessage:
            'Illegal state transition from $_currentState via event ${event.runtimeType}',
      );
      _transitionHistory.add(failure);
      throw StateError(failure.errorMessage!);
    }

    final result = StateTransitionResult(
      previousState: _currentState,
      newState: next,
      event: event,
      isIllegal: false,
    );
    _currentState = next;
    _transitionHistory.add(result);
    return result;
  }

  SessionState? _determineNextState(SessionState current, SessionEvent event) {
    if (event is CancelRequestedEvent) {
      return (current != SessionState.notStarted &&
              current != SessionState.completed)
          ? SessionState.cancelled
          : null;
    }
    if (event is RestartRequestedEvent) {
      return SessionState.notStarted;
    }

    return switch (current) {
      SessionState.notStarted => switch (event) {
        StartOnboardingEvent() => SessionState.onboardingConsent,
        _ => null,
      },
      SessionState.onboardingConsent => switch (event) {
        ConsentAgreedEvent(:final agreed) =>
          agreed ? SessionState.deviceReadiness : SessionState.aborted,
        _ => null,
      },
      SessionState.deviceReadiness => switch (event) {
        DeviceEvaluatedEvent(:final isSupported) =>
          isSupported ? SessionState.calibrationGate : SessionState.aborted,
        _ => null,
      },
      SessionState.calibrationGate => switch (event) {
        CalibrationEvaluatedEvent() => SessionState.environmentalNoiseCheck,
        _ => null,
      },
      SessionState.environmentalNoiseCheck => switch (event) {
        NoiseBaselineCheckedEvent(:final assessment) => switch (assessment) {
          NoiseAssessment.valid => SessionState.testPrep,
          NoiseAssessment.suspect ||
          NoiseAssessment.invalid ||
          NoiseAssessment.unavailable => SessionState.automaticPauseNoise,
        },
        _ => null,
      },
      SessionState.testPrep => switch (event) {
        StartPracticeEvent() => SessionState.practicePresentation,
        StartTestEvent() => SessionState.stimulusPresentation,
        PrepareTrialEvent() => SessionState.stimulusPresentation,
        _ => null,
      },
      SessionState.practicePresentation => switch (event) {
        UserRespondedHeardEvent() ||
        UserRespondedNotHeardEvent() ||
        ResponseTimedOutEvent() ||
        PracticeResponseReceivedEvent() => SessionState.practiceFeedback,
        NoiseDisturbanceDetectedEvent() => SessionState.automaticPauseNoise,
        DeviceDisconnectedEvent() => SessionState.automaticPauseDevice,
        _ => null,
      },
      SessionState.practiceFeedback => switch (event) {
        StartPracticeEvent() => SessionState.practicePresentation,
        FinishPracticeEvent() => SessionState.testPrep,
        StartTestEvent() => SessionState.stimulusPresentation,
        _ => null,
      },
      SessionState.stimulusPresentation => switch (event) {
        StimulusStartedEvent() => SessionState.stimulusPresentation,
        UserRespondedHeardEvent() ||
        UserRespondedNotHeardEvent() => SessionState.trialValidation,
        StimulusEndedEvent() => SessionState.waitingForResponse,
        NoiseDisturbanceDetectedEvent() => SessionState.automaticPauseNoise,
        DeviceDisconnectedEvent() => SessionState.automaticPauseDevice,
        _ => null,
      },
      SessionState.waitingForResponse => switch (event) {
        UserRespondedHeardEvent() ||
        UserRespondedNotHeardEvent() ||
        ResponseTimedOutEvent() => SessionState.trialValidation,
        NoiseDisturbanceDetectedEvent() => SessionState.automaticPauseNoise,
        DeviceDisconnectedEvent() => SessionState.automaticPauseDevice,
        _ => null,
      },
      SessionState.trialValidation => switch (event) {
        NextTrialNeededEvent() => SessionState.stimulusPresentation,
        TargetThresholdFoundEvent() => SessionState.thresholdEstimation,
        AllTargetsCompletedEvent() => SessionState.results,
        NoiseDisturbanceDetectedEvent() => SessionState.automaticPauseNoise,
        _ => null,
      },
      SessionState.thresholdEstimation => switch (event) {
        NextTrialNeededEvent() => SessionState.stimulusPresentation,
        AllTargetsCompletedEvent() => SessionState.results,
        _ => null,
      },
      SessionState.automaticPauseNoise => switch (event) {
        NoiseRecoveredEvent(:final isStable) =>
          isStable
              ? SessionState.recoveryRecheck
              : SessionState.automaticPauseNoise,
        ResumeRequestedEvent() => SessionState.recoveryRecheck,
        _ => null,
      },
      SessionState.automaticPauseDevice => switch (event) {
        DeviceEvaluatedEvent(:final isSupported) =>
          isSupported
              ? SessionState.recoveryRecheck
              : SessionState.automaticPauseDevice,
        ResumeRequestedEvent() => SessionState.recoveryRecheck,
        _ => null,
      },
      SessionState.recoveryRecheck => switch (event) {
        NoiseBaselineCheckedEvent(:final assessment) =>
          assessment == NoiseAssessment.valid
              ? SessionState.stimulusPresentation
              : SessionState.automaticPauseNoise,
        StartTestEvent() => SessionState.stimulusPresentation,
        NoiseDisturbanceDetectedEvent() => SessionState.automaticPauseNoise,
        DeviceDisconnectedEvent() => SessionState.automaticPauseDevice,
        _ => null,
      },
      SessionState.results ||
      SessionState.completed ||
      SessionState.cancelled ||
      SessionState.aborted => switch (event) {
        RestartRequestedEvent() => SessionState.notStarted,
        RetrySessionEvent() => SessionState.deviceReadiness,
        _ => null,
      },
    };
  }
}

