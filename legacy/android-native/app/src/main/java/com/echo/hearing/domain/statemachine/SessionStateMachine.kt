package com.echo.hearing.domain.statemachine

import com.echo.hearing.domain.model.*

/**
 * Explicit, typed session states representing the lifecycle of an audiometric screening.
 */
enum class SessionState {
    NOT_STARTED,
    ONBOARDING_CONSENT,
    DEVICE_READINESS,
    CALIBRATION_GATE,
    ENVIRONMENTAL_NOISE_CHECK,
    TEST_PREP,
    PRACTICE_PRESENTATION,
    PRACTICE_FEEDBACK,
    STIMULUS_PRESENTATION,
    WAITING_FOR_RESPONSE,
    TRIAL_VALIDATION,
    AUTOMATIC_PAUSE_NOISE,
    AUTOMATIC_PAUSE_DEVICE,
    RECOVERY_RECHECK,
    THRESHOLD_ESTIMATION,
    RESULTS,
    COMPLETED,
    CANCELLED,
    ABORTED
}

/**
 * Domain events that trigger state transitions.
 */
sealed interface SessionEvent {
    data object StartOnboarding : SessionEvent
    data class ConsentAgreed(val agreed: Boolean) : SessionEvent
    data class DeviceEvaluated(val route: AudioRouteInfo, val isSupported: Boolean) : SessionEvent
    data class CalibrationEvaluated(val calibration: CalibrationInfo) : SessionEvent
    data class NoiseBaselineChecked(val assessment: NoiseAssessment) : SessionEvent
    data object StartPractice : SessionEvent
    data class PracticeResponseReceived(val heard: Boolean, val latencyMs: Long) : SessionEvent
    data object FinishPractice : SessionEvent
    data object StartTest : SessionEvent
    data class PrepareTrial(val ear: Ear, val frequencyHz: Int, val levelDb: Int) : SessionEvent
    data object StimulusStarted : SessionEvent
    data object StimulusEnded : SessionEvent
    data class UserRespondedHeard(val latencyMs: Long) : SessionEvent
    data class UserRespondedNotHeard(val latencyMs: Long) : SessionEvent
    data object ResponseTimedOut : SessionEvent
    data class NoiseDisturbanceDetected(val overlapsStimulus: Boolean) : SessionEvent
    data object DeviceDisconnected : SessionEvent
    data class NoiseRecovered(val isStable: Boolean) : SessionEvent
    data object ResumeRequested : SessionEvent
    data object TargetThresholdFound : SessionEvent
    data object NextTrialNeeded : SessionEvent
    data object AllTargetsCompleted : SessionEvent
    data object CancelRequested : SessionEvent
    data object RestartRequested : SessionEvent
    data object RetrySession : SessionEvent
}

/**
 * Result of attempting a state transition.
 */
data class StateTransitionResult(
    val previousState: SessionState,
    val newState: SessionState,
    val event: SessionEvent,
    val isIllegal: Boolean = false,
    val errorMessage: String? = null
)

/**
 * Finite state machine enforcing legal transitions and audit trail.
 */
class SessionStateMachine(initialState: SessionState = SessionState.NOT_STARTED) {
    var currentState: SessionState = initialState
        private set

    private val _transitionHistory = mutableListOf<StateTransitionResult>()
    val transitionHistory: List<StateTransitionResult> get() = _transitionHistory.toList()

    /**
     * Determines whether the transition is legal under the state machine rules.
     */
    fun canTransition(event: SessionEvent): Boolean {
        return determineNextState(currentState, event) != null
    }

    /**
     * Attempts a transition with the given event.
     * Throws IllegalStateException if the transition is invalid, preserving strict contract.
     */
    fun transition(event: SessionEvent): StateTransitionResult {
        val next = determineNextState(currentState, event)
        if (next == null) {
            val failure = StateTransitionResult(
                previousState = currentState,
                newState = currentState,
                event = event,
                isIllegal = true,
                errorMessage = "Illegal state transition from $currentState via event ${event::class.simpleName}"
            )
            _transitionHistory.add(failure)
            throw IllegalStateException(failure.errorMessage)
        }

        val result = StateTransitionResult(
            previousState = currentState,
            newState = next,
            event = event,
            isIllegal = false
        )
        currentState = next
        _transitionHistory.add(result)
        return result
    }

    private fun determineNextState(current: SessionState, event: SessionEvent): SessionState? {
        // Universal global cancellations / resets
        if (event is SessionEvent.CancelRequested) {
            return if (current != SessionState.NOT_STARTED && current != SessionState.COMPLETED) {
                SessionState.CANCELLED
            } else null
        }
        if (event is SessionEvent.RestartRequested) {
            return SessionState.NOT_STARTED
        }

        return when (current) {
            SessionState.NOT_STARTED -> when (event) {
                is SessionEvent.StartOnboarding -> SessionState.ONBOARDING_CONSENT
                else -> null
            }

            SessionState.ONBOARDING_CONSENT -> when (event) {
                is SessionEvent.ConsentAgreed -> {
                    if (event.agreed) SessionState.DEVICE_READINESS else SessionState.ABORTED
                }
                else -> null
            }

            SessionState.DEVICE_READINESS -> when (event) {
                is SessionEvent.DeviceEvaluated -> {
                    if (event.isSupported) SessionState.CALIBRATION_GATE else SessionState.ABORTED
                }
                else -> null
            }

            SessionState.CALIBRATION_GATE -> when (event) {
                is SessionEvent.CalibrationEvaluated -> {
                    // Even uncalibrated can proceed in simulation/provisional mode, but notes flag
                    SessionState.ENVIRONMENTAL_NOISE_CHECK
                }
                else -> null
            }

            SessionState.ENVIRONMENTAL_NOISE_CHECK -> when (event) {
                is SessionEvent.NoiseBaselineChecked -> when (event.assessment) {
                    NoiseAssessment.VALID -> SessionState.TEST_PREP
                    NoiseAssessment.SUSPECT, NoiseAssessment.INVALID -> SessionState.AUTOMATIC_PAUSE_NOISE
                    NoiseAssessment.UNAVAILABLE -> SessionState.AUTOMATIC_PAUSE_NOISE
                }
                else -> null
            }

            SessionState.TEST_PREP -> when (event) {
                is SessionEvent.StartPractice -> SessionState.PRACTICE_PRESENTATION
                is SessionEvent.StartTest -> SessionState.STIMULUS_PRESENTATION
                is SessionEvent.PrepareTrial -> SessionState.STIMULUS_PRESENTATION
                else -> null
            }

            SessionState.PRACTICE_PRESENTATION -> when (event) {
                is SessionEvent.UserRespondedHeard -> SessionState.PRACTICE_FEEDBACK
                is SessionEvent.UserRespondedNotHeard -> SessionState.PRACTICE_FEEDBACK
                is SessionEvent.ResponseTimedOut -> SessionState.PRACTICE_FEEDBACK
                is SessionEvent.PracticeResponseReceived -> SessionState.PRACTICE_FEEDBACK
                is SessionEvent.NoiseDisturbanceDetected -> SessionState.AUTOMATIC_PAUSE_NOISE
                is SessionEvent.DeviceDisconnected -> SessionState.AUTOMATIC_PAUSE_DEVICE
                else -> null
            }

            SessionState.PRACTICE_FEEDBACK -> when (event) {
                is SessionEvent.StartPractice -> SessionState.PRACTICE_PRESENTATION
                is SessionEvent.FinishPractice -> SessionState.TEST_PREP
                is SessionEvent.StartTest -> SessionState.STIMULUS_PRESENTATION
                else -> null
            }

            SessionState.STIMULUS_PRESENTATION -> when (event) {
                is SessionEvent.StimulusStarted -> SessionState.STIMULUS_PRESENTATION
                is SessionEvent.UserRespondedHeard -> SessionState.TRIAL_VALIDATION
                is SessionEvent.UserRespondedNotHeard -> SessionState.TRIAL_VALIDATION
                is SessionEvent.StimulusEnded -> SessionState.WAITING_FOR_RESPONSE
                is SessionEvent.NoiseDisturbanceDetected -> SessionState.AUTOMATIC_PAUSE_NOISE
                is SessionEvent.DeviceDisconnected -> SessionState.AUTOMATIC_PAUSE_DEVICE
                else -> null
            }

            SessionState.WAITING_FOR_RESPONSE -> when (event) {
                is SessionEvent.UserRespondedHeard -> SessionState.TRIAL_VALIDATION
                is SessionEvent.UserRespondedNotHeard -> SessionState.TRIAL_VALIDATION
                is SessionEvent.ResponseTimedOut -> SessionState.TRIAL_VALIDATION
                is SessionEvent.NoiseDisturbanceDetected -> SessionState.AUTOMATIC_PAUSE_NOISE
                is SessionEvent.DeviceDisconnected -> SessionState.AUTOMATIC_PAUSE_DEVICE
                else -> null
            }

            SessionState.TRIAL_VALIDATION -> when (event) {
                is SessionEvent.NextTrialNeeded -> SessionState.STIMULUS_PRESENTATION
                is SessionEvent.TargetThresholdFound -> SessionState.THRESHOLD_ESTIMATION
                is SessionEvent.AllTargetsCompleted -> SessionState.RESULTS
                is SessionEvent.NoiseDisturbanceDetected -> SessionState.AUTOMATIC_PAUSE_NOISE
                else -> null
            }

            SessionState.THRESHOLD_ESTIMATION -> when (event) {
                is SessionEvent.NextTrialNeeded -> SessionState.STIMULUS_PRESENTATION
                is SessionEvent.AllTargetsCompleted -> SessionState.RESULTS
                else -> null
            }

            SessionState.AUTOMATIC_PAUSE_NOISE -> when (event) {
                is SessionEvent.NoiseRecovered -> {
                    if (event.isStable) SessionState.RECOVERY_RECHECK else SessionState.AUTOMATIC_PAUSE_NOISE
                }
                is SessionEvent.ResumeRequested -> SessionState.RECOVERY_RECHECK
                else -> null
            }

            SessionState.AUTOMATIC_PAUSE_DEVICE -> when (event) {
                is SessionEvent.DeviceEvaluated -> {
                    if (event.isSupported) SessionState.RECOVERY_RECHECK else SessionState.AUTOMATIC_PAUSE_DEVICE
                }
                is SessionEvent.ResumeRequested -> SessionState.RECOVERY_RECHECK
                else -> null
            }

            SessionState.RECOVERY_RECHECK -> when (event) {
                is SessionEvent.NoiseBaselineChecked -> {
                    if (event.assessment == NoiseAssessment.VALID) SessionState.STIMULUS_PRESENTATION else SessionState.AUTOMATIC_PAUSE_NOISE
                }
                is SessionEvent.StartTest -> SessionState.STIMULUS_PRESENTATION
                is SessionEvent.NoiseDisturbanceDetected -> SessionState.AUTOMATIC_PAUSE_NOISE
                is SessionEvent.DeviceDisconnected -> SessionState.AUTOMATIC_PAUSE_DEVICE
                else -> null
            }

            SessionState.RESULTS -> when (event) {
                is SessionEvent.RestartRequested -> SessionState.NOT_STARTED
                is SessionEvent.RetrySession -> SessionState.DEVICE_READINESS
                else -> null
            }

            SessionState.COMPLETED, SessionState.CANCELLED, SessionState.ABORTED -> when (event) {
                is SessionEvent.RestartRequested -> SessionState.NOT_STARTED
                is SessionEvent.RetrySession -> SessionState.DEVICE_READINESS
                else -> null
            }
        }
    }
}
