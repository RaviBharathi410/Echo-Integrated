package com.echo.hearing.domain.threshold

import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.ThresholdResult
import com.echo.hearing.domain.model.TrialOutcome
import com.echo.hearing.domain.model.TrialRecord

/**
 * Identifies the threshold estimation algorithm in use.
 */
enum class StrategyType(val displayName: String) {
    MODIFIED_HUGHSON_WESTLAKE("Modified Hughson–Westlake (Staircase)"),
    BINARY_SEARCH_REFINEMENT("Binary Search Refinement (Experimental)")
}

/**
 * Result of a single strategy evaluation step.
 * Intentionally parallel to [StaircaseStepResult] but strategy-agnostic.
 */
sealed interface StrategyResult {
    /** Continue testing at the specified level. */
    data class NextTrial(val ear: Ear, val frequencyHz: Int, val nextLevelDb: Int) : StrategyResult

    /** Threshold estimated for the current target; optionally proceed to next. */
    data class ThresholdFound(val result: ThresholdResult, val nextTarget: TargetPair?) : StrategyResult

    /** Maximum trials reached for the current target without a conclusive threshold. */
    data class MaxTrialsExceeded(val ear: Ear, val frequencyHz: Int, val nextTarget: TargetPair?) : StrategyResult

    /** The strategy cannot establish a valid bracket or conclusive result for this target. */
    data class Inconclusive(val ear: Ear, val frequencyHz: Int, val reason: String, val nextTarget: TargetPair?) : StrategyResult

    /** All configured ear/frequency targets have been completed. */
    data object AllTargetsCompleted : StrategyResult
}

/**
 * Common contract for threshold estimation strategies.
 *
 * Implementations must:
 * - Keep state isolated per ear and frequency.
 * - Never update estimation state from invalid, contaminated, or interrupted trials.
 * - Never silently switch to another strategy's decision rules.
 * - Record the strategy type and version in result metadata.
 */
interface ThresholdEstimationStrategy {

    /** The type of strategy this implementation represents. */
    val strategyType: StrategyType

    /** A version string for audit/metadata purposes. */
    val strategyVersion: String

    /** The current ear being tested. */
    val currentEar: Ear

    /** The current frequency being tested in Hz. */
    val currentFrequencyHz: Int

    /** The current digital presentation level (0–80 digital attenuation step, NOT calibrated). */
    val currentLevelDb: Int

    /** All recorded trials. */
    val allTrials: List<TrialRecord>

    /** All threshold results found so far. */
    val thresholdResults: List<ThresholdResult>

    /** Whether all targets have been completed. */
    fun isComplete(): Boolean

    /**
     * Evaluate a trial outcome and return the next action.
     *
     * [outcome] must be a valid TrialOutcome. Contaminated, invalid, and interrupted
     * outcomes are recorded but MUST NOT update the estimation state (bracket, staircase level, etc.).
     *
     * @param outcome The trial result.
     * @param latencyMs Response latency in milliseconds, if available.
     * @param ambientNoiseDbFs Ambient noise level in dBFS at time of trial, if available.
     * @return The next action the test engine should take.
     */
    fun evaluateTrial(
        outcome: TrialOutcome,
        latencyMs: Long? = null,
        ambientNoiseDbFs: Double? = null
    ): StrategyResult

    /** Reset all state for a fresh test. */
    fun reset()
}
