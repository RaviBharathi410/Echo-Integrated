package com.echo.hearing.domain.threshold

import com.echo.hearing.domain.model.AudiometricFrequencies
import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.ThresholdResult
import com.echo.hearing.domain.model.TrialOutcome
import com.echo.hearing.domain.model.TrialRecord

/**
 * Configuration parameters for the Modified Hughson-Westlake staircase protocol.
 *
 * ## Level mapping (inspected from StimulusEngine)
 * [startingLevelDb] and all level values in this config are **digital attenuation steps**
 * in the range [minLevelDb]..[maxLevelDb]. In the stimulus engine, these map to dBFS as:
 *   attenuationDb = (levelDb - 80)  →  levelDb=0 ≡ -80 dBFS, levelDb=40 ≡ -40 dBFS, levelDb=80 ≡ 0 dBFS (full scale).
 * These are NOT dB SPL or dB HL. No calibrated conversion exists without a validated
 * acoustic calibration chain for a specific device + transducer combination.
 */
data class ProtocolConfig(
    val startingLevelDb: Int = 40,
    val downStepDb: Int = 10,
    val upStepDb: Int = 5,
    val minLevelDb: Int = 0,
    val maxLevelDb: Int = 80,
    val requiredAscendingResponses: Int = 2,
    val maxTrialsPerTarget: Int = 18,
    val frequencies: List<Int> = AudiometricFrequencies.DEFAULT_SCREENING_FREQUENCIES,
    val ears: List<Ear> = listOf(Ear.LEFT, Ear.RIGHT),
    val protocolVersion: String = "HW-2026-v1-provisional",
    /** The supported presentation levels. If empty, any integer in [minLevelDb]..[maxLevelDb] is valid. */
    val supportedLevels: List<Int> = emptyList()
)

/**
 * Result of evaluating a trial within the staircase search.
 * Preserved for backward compatibility with existing callers.
 */
sealed interface StaircaseStepResult {
    data class NextTrial(val ear: Ear, val frequencyHz: Int, val nextLevelDb: Int) : StaircaseStepResult
    data class ThresholdFound(val result: ThresholdResult, val nextTarget: TargetPair?) : StaircaseStepResult
    data class MaxTrialsExceeded(val ear: Ear, val frequencyHz: Int, val nextTarget: TargetPair?) : StaircaseStepResult
    data object AllTargetsCompleted : StaircaseStepResult
}

data class TargetPair(val ear: Ear, val frequencyHz: Int)

/**
 * Pure, deterministic Modified Hughson-Westlake threshold search engine.
 * Fully decoupled from Android UI and audio hardware, ensuring 100% testability.
 *
 * Now also implements [ThresholdEstimationStrategy] for the unified strategy interface.
 *
 * ## Documented algorithm behavior (inspected Phase 2):
 * - **Initial level**: [ProtocolConfig.startingLevelDb] (default 40 digital level steps)
 * - **Heard → descend**: subtract [ProtocolConfig.downStepDb] (default 10), mark step as non-ascending
 * - **Not heard / timeout → ascend**: add [ProtocolConfig.upStepDb] (default 5), mark step as ascending
 * - **Ascending response criterion**: Threshold accepted when [ProtocolConfig.requiredAscendingResponses]
 *   (default 2) responses occur at the same level during ascending runs
 * - **Contaminated / invalid trials**: recorded in audit trail but do NOT update the staircase level,
 *   ascending counter, or count toward the max-trials limit
 * - **Max trials**: [ProtocolConfig.maxTrialsPerTarget] (default 18) valid trials per ear/frequency target
 * - **Order**: left ear frequencies in order, then right ear frequencies in order
 */
class ModifiedHughsonWestlakeEngine(
    val config: ProtocolConfig = ProtocolConfig()
) : ThresholdEstimationStrategy {

    override val strategyType: StrategyType = StrategyType.MODIFIED_HUGHSON_WESTLAKE
    override val strategyVersion: String = "MHW-2026-v1.1"

    private var earIndex: Int = 0
    private var frequencyIndex: Int = 0

    private var _currentLevelDb: Int = config.startingLevelDb
    override var currentLevelDb: Int
        get() = _currentLevelDb
        private set(value) { _currentLevelDb = value }

    private var previousLevelDb: Int = config.startingLevelDb
    private var wasLastStepAscending: Boolean = false

    // Tracks levels at which responses were given during ascending steps
    private val ascendingResponsesAtLevel = mutableMapOf<Int, Int>()

    private val _allTrials = mutableListOf<TrialRecord>()
    override val allTrials: List<TrialRecord> get() = _allTrials.toList()

    private val _thresholdResults = mutableListOf<ThresholdResult>()
    override val thresholdResults: List<ThresholdResult> get() = _thresholdResults.toList()

    override val currentEar: Ear get() = config.ears[earIndex]
    override val currentFrequencyHz: Int get() = config.frequencies[frequencyIndex]

    val currentTargetTrials: List<TrialRecord>
        get() = _allTrials.filter { it.ear == currentEar && it.frequencyHz == currentFrequencyHz }

    /**
     * Evaluates a response trial using the Modified Hughson-Westlake staircase.
     * Contaminated or invalid trials are recorded but DO NOT affect the staircase level or count as non-response!
     *
     * Returns [StaircaseStepResult] for backward-compatible callers.
     */
    fun evaluateTrialStaircase(
        outcome: TrialOutcome,
        latencyMs: Long? = null,
        ambientNoiseDbFs: Double? = null
    ): StaircaseStepResult {
        val trialNumber = _allTrials.size + 1
        val record = TrialRecord(
            trialNumber = trialNumber,
            ear = currentEar,
            frequencyHz = currentFrequencyHz,
            levelDb = currentLevelDb,
            outcome = outcome,
            latencyMs = latencyMs,
            ambientNoiseLevelDbFs = ambientNoiseDbFs
        )
        _allTrials.add(record)

        // Invalid / contaminated trial guard: retry at the same level without advancing staircase
        if (outcome == TrialOutcome.CONTAMINATED_BY_NOISE || outcome == TrialOutcome.INVALID_INTERRUPTED) {
            return StaircaseStepResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
        }

        val targetTrials = currentTargetTrials.filter {
            it.outcome == TrialOutcome.HEARD || it.outcome == TrialOutcome.NOT_HEARD || it.outcome == TrialOutcome.UNANSWERED_TIMEOUT
        }

        // Check if maximum trials exceeded
        if (targetTrials.size >= config.maxTrialsPerTarget) {
            val nextTarget = advanceToNextTarget()
            return if (nextTarget != null) {
                StaircaseStepResult.MaxTrialsExceeded(record.ear, record.frequencyHz, nextTarget)
            } else {
                StaircaseStepResult.AllTargetsCompleted
            }
        }

        when (outcome) {
            TrialOutcome.HEARD -> {
                // If the previous step was ascending (going up after a non-response) and user heard it
                if (wasLastStepAscending) {
                    val count = (ascendingResponsesAtLevel[currentLevelDb] ?: 0) + 1
                    ascendingResponsesAtLevel[currentLevelDb] = count

                    // Check Hughson-Westlake stopping rule (e.g. 2 responses at this level on ascending runs)
                    if (count >= config.requiredAscendingResponses) {
                        val threshold = ThresholdResult(
                            ear = currentEar,
                            frequencyHz = currentFrequencyHz,
                            thresholdDb = currentLevelDb,
                            validAscendingResponses = count,
                            totalTrialsForTarget = targetTrials.size,
                            method = "MODIFIED_HUGHSON_WESTLAKE",
                            strategyVersion = strategyVersion
                        )
                        _thresholdResults.add(threshold)
                        val next = advanceToNextTarget()
                        return if (next != null) {
                            StaircaseStepResult.ThresholdFound(threshold, next)
                        } else {
                            StaircaseStepResult.AllTargetsCompleted
                        }
                    }
                }

                // Down 10 dB on response
                previousLevelDb = currentLevelDb
                currentLevelDb = (currentLevelDb - config.downStepDb).coerceAtLeast(config.minLevelDb)
                wasLastStepAscending = false
            }

            TrialOutcome.NOT_HEARD, TrialOutcome.UNANSWERED_TIMEOUT -> {
                // Up 5 dB on non-response (ascending step)
                previousLevelDb = currentLevelDb
                currentLevelDb = (currentLevelDb + config.upStepDb).coerceAtMost(config.maxLevelDb)
                wasLastStepAscending = true
            }

            else -> {
                // Handled above
            }
        }

        return StaircaseStepResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
    }

    /**
     * Strategy interface implementation: delegates to [evaluateTrialStaircase] and
     * converts [StaircaseStepResult] to [StrategyResult].
     */
    override fun evaluateTrial(
        outcome: TrialOutcome,
        latencyMs: Long?,
        ambientNoiseDbFs: Double?
    ): StrategyResult {
        return when (val r = evaluateTrialStaircase(outcome, latencyMs, ambientNoiseDbFs)) {
            is StaircaseStepResult.NextTrial -> StrategyResult.NextTrial(r.ear, r.frequencyHz, r.nextLevelDb)
            is StaircaseStepResult.ThresholdFound -> StrategyResult.ThresholdFound(r.result, r.nextTarget)
            is StaircaseStepResult.MaxTrialsExceeded -> StrategyResult.MaxTrialsExceeded(r.ear, r.frequencyHz, r.nextTarget)
            is StaircaseStepResult.AllTargetsCompleted -> StrategyResult.AllTargetsCompleted
        }
    }

    private fun advanceToNextTarget(): TargetPair? {
        ascendingResponsesAtLevel.clear()
        wasLastStepAscending = false
        currentLevelDb = config.startingLevelDb
        previousLevelDb = config.startingLevelDb

        frequencyIndex++
        if (frequencyIndex < config.frequencies.size) {
            return TargetPair(currentEar, currentFrequencyHz)
        }

        // Advance to next ear
        frequencyIndex = 0
        earIndex++
        if (earIndex < config.ears.size) {
            return TargetPair(currentEar, currentFrequencyHz)
        }

        // Completed all ears and frequencies
        return null
    }

    override fun isComplete(): Boolean {
        return earIndex >= config.ears.size
    }

    override fun reset() {
        earIndex = 0
        frequencyIndex = 0
        currentLevelDb = config.startingLevelDb
        previousLevelDb = config.startingLevelDb
        wasLastStepAscending = false
        ascendingResponsesAtLevel.clear()
        _allTrials.clear()
        _thresholdResults.clear()
    }
}
