package com.echo.hearing.domain.quality

import com.echo.hearing.domain.model.AudioRouteInfo
import com.echo.hearing.domain.model.NoiseAssessment
import com.echo.hearing.domain.model.QualityFlag
import com.echo.hearing.domain.model.TrialOutcome

/**
 * Quality evaluation result for an individual presentation trial.
 */
data class TrialQualityEvaluation(
    val outcome: TrialOutcome,
    val isTrialValid: Boolean,
    val latencyMs: Long?,
    val isPlausibleLatency: Boolean,
    val qualityFlags: Set<QualityFlag> = emptySet(),
    val notes: String? = null
)

/**
 * Dedicated controller enforcing strict audio quality controls and trial validity safeguards.
 *
 * Requirements:
 * - Rejects responses faster than physiological auditory reaction time (< 150ms) as anticipatory guessing.
 * - Detects noise spikes and automatically invalidates contaminated trials.
 * - Detects disconnected headphones and suspends testing.
 * - Maintains comprehensive quality audit trail flags.
 */
class TrialQualityController(
    val minPlausibleLatencyMs: Long = 150L,
    val maxPlausibleLatencyMs: Long = 3000L
) {

    /**
     * Evaluates the outcome of a trial given environmental and physical route state.
     */
    fun evaluateTrialQuality(
        userTappedHeard: Boolean,
        latencyMs: Long?,
        noiseAssessment: NoiseAssessment,
        isNoiseDisturbedDuringTrial: Boolean,
        routeInfo: AudioRouteInfo?,
        explicitNotHeard: Boolean = false
    ): TrialQualityEvaluation {
        val flags = mutableSetOf<QualityFlag>()

        // Check audio route validity
        if (routeInfo == null || !routeInfo.routeType.isHeadphone) {
            flags.add(QualityFlag.AUDIO_ROUTE_CHANGED_DURING_TEST)
            return TrialQualityEvaluation(
                outcome = TrialOutcome.INVALID_INTERRUPTED,
                isTrialValid = false,
                latencyMs = latencyMs,
                isPlausibleLatency = false,
                qualityFlags = flags,
                notes = "Audio route invalid or headphone disconnected during trial"
            )
        }

        // Check noise contamination
        if (isNoiseDisturbedDuringTrial || noiseAssessment == NoiseAssessment.INVALID || noiseAssessment == NoiseAssessment.SUSPECT) {
            flags.add(QualityFlag.ENVIRONMENTAL_NOISE_PAUSES_DETECTED)
            return TrialQualityEvaluation(
                outcome = TrialOutcome.CONTAMINATED_BY_NOISE,
                isTrialValid = false,
                latencyMs = latencyMs,
                isPlausibleLatency = false,
                qualityFlags = flags,
                notes = "Trial contaminated by ambient noise ($noiseAssessment)"
            )
        }

        // Explicit user report: "I CAN'T HEAR IT"
        if (explicitNotHeard) {
            return TrialQualityEvaluation(
                outcome = TrialOutcome.NOT_HEARD,
                isTrialValid = true,
                latencyMs = latencyMs,
                isPlausibleLatency = true,
                qualityFlags = flags,
                notes = "User explicitly reported tone was not heard"
            )
        }

        // Passive timeout: no button pressed (missing response)
        if (!userTappedHeard) {
            return TrialQualityEvaluation(
                outcome = TrialOutcome.UNANSWERED_TIMEOUT,
                isTrialValid = false,
                latencyMs = null,
                isPlausibleLatency = false,
                qualityFlags = flags,
                notes = "No response within presentation and response window (unanswered timeout)"
            )
        }

        // Latency validation for positive response
        val actualLatency = latencyMs ?: 0L
        val isAnticipatory = actualLatency < minPlausibleLatencyMs
        val isExpired = actualLatency > maxPlausibleLatencyMs

        return if (isAnticipatory) {
            // Premature false alarm / guessing
            flags.add(QualityFlag.EXCESSIVE_REVERSALS)
            TrialQualityEvaluation(
                outcome = TrialOutcome.INVALID_INTERRUPTED,
                isTrialValid = false,
                latencyMs = actualLatency,
                isPlausibleLatency = false,
                qualityFlags = flags,
                notes = "Anticipatory tap rejected (< ${minPlausibleLatencyMs}ms)"
            )
        } else if (isExpired) {
            TrialQualityEvaluation(
                outcome = TrialOutcome.UNANSWERED_TIMEOUT,
                isTrialValid = true,
                latencyMs = actualLatency,
                isPlausibleLatency = false,
                qualityFlags = flags,
                notes = "Response arrived after cutoff window (> ${maxPlausibleLatencyMs}ms)"
            )
        } else {
            TrialQualityEvaluation(
                outcome = TrialOutcome.HEARD,
                isTrialValid = true,
                latencyMs = actualLatency,
                isPlausibleLatency = true,
                qualityFlags = flags,
                notes = "Valid response confirmed (latency: ${actualLatency}ms)"
            )
        }
    }
}
