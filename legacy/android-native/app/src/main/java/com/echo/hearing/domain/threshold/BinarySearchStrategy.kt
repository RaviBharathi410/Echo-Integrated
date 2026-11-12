package com.echo.hearing.domain.threshold

import com.echo.hearing.domain.model.AudiometricFrequencies
import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.ThresholdResult
import com.echo.hearing.domain.model.TrialOutcome
import com.echo.hearing.domain.model.TrialRecord
import kotlin.math.ceil
import kotlin.math.floor

/**
 * Midpoint rounding policy for binary search interval halving.
 */
enum class MidpointRoundingPolicy {
    /** Ceil: round fractional midpoints up towards higher level (e.g. 62.5 -> 63) */
    ROUND_UP,
    /** Floor: round fractional midpoints down towards lower level (e.g. 62.5 -> 62) */
    ROUND_DOWN,
    /** Snap up to the nearest multiple of grid step (e.g. 62.5 with 5dB step -> 65) */
    SNAP_GRID_UP,
    /** Snap down to the nearest multiple of grid step (e.g. 62.5 with 5dB step -> 60) */
    SNAP_GRID_DOWN
}

/**
 * Configuration for the Binary Search Refinement strategy.
 *
 * ## Level mapping note
 * All levels are digital attenuation steps (0–80) mapping to dBFS:
 * attenuationDb = (levelDb - 80).
 * These are NOT calibrated dB SPL or dB HL without verified acoustic hardware calibration.
 */
data class BinarySearchConfig(
    val startingLevelDb: Int = 40,
    val bracketStepDb: Int = 20,
    val resolutionDb: Int = 5,
    val minLevelDb: Int = 0,
    val maxLevelDb: Int = 80,
    val maxTrialsPerTarget: Int = 18,
    val midpointRounding: MidpointRoundingPolicy = MidpointRoundingPolicy.ROUND_UP,
    val gridStepDb: Int = 5,
    val frequencies: List<Int> = AudiometricFrequencies.DEFAULT_SCREENING_FREQUENCIES,
    val ears: List<Ear> = listOf(Ear.LEFT, Ear.RIGHT),
    val strategyVersion: String = "BSR-2026-v1.0-experimental"
)

/**
 * Internal tracking state of the bracket for a single target (ear + frequency).
 */
data class TargetBracketState(
    val ear: Ear,
    val frequencyHz: Int,
    var lowerInaudibleDb: Int? = null,
    var upperAudibleDb: Int? = null,
    var isBracketEstablished: Boolean = false,
    var isResolved: Boolean = false,
    var isInconclusive: Boolean = false,
    var inconclusiveReason: String? = null
)

/**
 * Experimental binary-search refinement threshold estimation strategy.
 *
 * ## Principles & Requirements:
 * 1. Independent implementation: does NOT combine decision rules with Hughson-Westlake.
 * 2. Explicit bracket establishment: requires a verified valid inaudible level and audible level
 *    where `lowerInaudible < upperAudible`.
 * 3. Trial validity guard: contaminated, interrupted, or invalid trials are recorded in audit trail
 *    but NEVER modify the bracket bounds or current level.
 * 4. Inconclusive return: if a valid bracket cannot be established within [minLevelDb]..[maxLevelDb],
 *    an explicit [StrategyResult.Inconclusive] outcome is returned.
 * 5. Deterministic midpoint halving: uses configurable [MidpointRoundingPolicy] for repeatable outcomes.
 */
class BinarySearchStrategy(
    val config: BinarySearchConfig = BinarySearchConfig()
) : ThresholdEstimationStrategy {

    override val strategyType: StrategyType = StrategyType.BINARY_SEARCH_REFINEMENT
    override val strategyVersion: String = config.strategyVersion

    private var earIndex: Int = 0
    private var frequencyIndex: Int = 0

    override val currentEar: Ear get() = config.ears.getOrElse(earIndex) { config.ears.last() }
    override val currentFrequencyHz: Int get() = config.frequencies.getOrElse(frequencyIndex) { config.frequencies.last() }

    private var _currentLevelDb: Int = config.startingLevelDb
    override var currentLevelDb: Int
        get() = _currentLevelDb
        private set(value) { _currentLevelDb = value }

    // Active bracket state for current ear + frequency target
    private var activeBracket = TargetBracketState(
        ear = currentEar,
        frequencyHz = currentFrequencyHz
    )

    private val _allTrials = mutableListOf<TrialRecord>()
    override val allTrials: List<TrialRecord> get() = _allTrials.toList()

    private val _thresholdResults = mutableListOf<ThresholdResult>()
    override val thresholdResults: List<ThresholdResult> get() = _thresholdResults.toList()

    val currentTargetTrials: List<TrialRecord>
        get() = _allTrials.filter { it.ear == currentEar && it.frequencyHz == currentFrequencyHz }

    /**
     * Evaluates a presentation trial for the binary search strategy.
     */
    override fun evaluateTrial(
        outcome: TrialOutcome,
        latencyMs: Long?,
        ambientNoiseDbFs: Double?
    ): StrategyResult {
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

        // Rule 2 & Clarification 2: Contaminated or invalid trials MUST NOT initialize or update the bracket
        if (outcome == TrialOutcome.CONTAMINATED_BY_NOISE || outcome == TrialOutcome.INVALID_INTERRUPTED) {
            return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
        }

        val validTargetTrials = currentTargetTrials.filter {
            it.outcome == TrialOutcome.HEARD ||
                    it.outcome == TrialOutcome.NOT_HEARD ||
                    it.outcome == TrialOutcome.UNANSWERED_TIMEOUT
        }

        // Max trials limit check
        if (validTargetTrials.size >= config.maxTrialsPerTarget) {
            val targetEar = currentEar
            val targetFreq = currentFrequencyHz
            val next = advanceToNextTarget()
            return StrategyResult.MaxTrialsExceeded(targetEar, targetFreq, next)
        }

        return if (!activeBracket.isBracketEstablished) {
            processInitialBracketPhase(outcome, validTargetTrials.size)
        } else {
            processBinaryRefinementPhase(outcome, validTargetTrials.size)
        }
    }

    /**
     * Phase 1: Establish valid bracket [lowerInaudibleDb, upperAudibleDb]
     * where lowerInaudibleDb < upperAudibleDb.
     */
    private fun processInitialBracketPhase(outcome: TrialOutcome, validTrialCount: Int): StrategyResult {
        when (outcome) {
            TrialOutcome.HEARD -> {
                // User heard at current level -> establishes or refines upper audible anchor
                val prevAudible = activeBracket.upperAudibleDb
                activeBracket.upperAudibleDb = if (prevAudible == null) currentLevelDb else minOf(prevAudible, currentLevelDb)

                if (activeBracket.lowerInaudibleDb != null) {
                    // Both bounds now established!
                    if (activeBracket.lowerInaudibleDb!! < activeBracket.upperAudibleDb!!) {
                        activeBracket.isBracketEstablished = true
                        return checkRefinementOrNextStep(validTrialCount)
                    }
                }

                // Need to find lower inaudible bound: step down
                val nextLevel = currentLevelDb - config.bracketStepDb
                if (currentLevelDb <= config.minLevelDb || nextLevel < config.minLevelDb) {
                    // Cannot establish inaudible level at or below minLevelDb
                    activeBracket.isInconclusive = true
                    activeBracket.inconclusiveReason = "Hearing detected at or below floor level (${config.minLevelDb} dBFS). Inaudible bound cannot be bracketed."
                    val targetEar = currentEar
                    val targetFreq = currentFrequencyHz
                    val nextTarget = advanceToNextTarget()
                    return StrategyResult.Inconclusive(targetEar, targetFreq, activeBracket.inconclusiveReason!!, nextTarget)
                }

                currentLevelDb = nextLevel.coerceAtLeast(config.minLevelDb)
                return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
            }

            TrialOutcome.NOT_HEARD, TrialOutcome.UNANSWERED_TIMEOUT -> {
                // User did not hear at current level -> establishes or refines lower inaudible anchor
                val prevInaudible = activeBracket.lowerInaudibleDb
                activeBracket.lowerInaudibleDb = if (prevInaudible == null) currentLevelDb else maxOf(prevInaudible, currentLevelDb)

                if (activeBracket.upperAudibleDb != null) {
                    // Both bounds now established!
                    if (activeBracket.lowerInaudibleDb!! < activeBracket.upperAudibleDb!!) {
                        activeBracket.isBracketEstablished = true
                        return checkRefinementOrNextStep(validTrialCount)
                    }
                }

                // Need to find upper audible bound: step up
                val nextLevel = currentLevelDb + config.bracketStepDb
                if (currentLevelDb >= config.maxLevelDb || nextLevel > config.maxLevelDb) {
                    // Cannot establish audible level at or above maxLevelDb
                    activeBracket.isInconclusive = true
                    activeBracket.inconclusiveReason = "Non-response at or above ceiling level (${config.maxLevelDb} dBFS). Audible bound cannot be bracketed."
                    val targetEar = currentEar
                    val targetFreq = currentFrequencyHz
                    val nextTarget = advanceToNextTarget()
                    return StrategyResult.Inconclusive(targetEar, targetFreq, activeBracket.inconclusiveReason!!, nextTarget)
                }

                currentLevelDb = nextLevel.coerceAtMost(config.maxLevelDb)
                return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
            }

            else -> {
                return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
            }
        }
    }

    /**
     * Phase 2: Binary interval halving once bracket is established.
     */
    private fun processBinaryRefinementPhase(outcome: TrialOutcome, validTrialCount: Int): StrategyResult {
        when (outcome) {
            TrialOutcome.HEARD -> {
                // Heard at midpoint -> tighten upper bound
                activeBracket.upperAudibleDb = currentLevelDb
            }
            TrialOutcome.NOT_HEARD, TrialOutcome.UNANSWERED_TIMEOUT -> {
                // Not heard at midpoint -> tighten lower bound
                activeBracket.lowerInaudibleDb = currentLevelDb
            }
            else -> {}
        }

        return checkRefinementOrNextStep(validTrialCount)
    }

    /**
     * Checks if current bracket satisfies resolution requirement or calculates next midpoint.
     */
    private fun checkRefinementOrNextStep(validTrialCount: Int): StrategyResult {
        val lower = activeBracket.lowerInaudibleDb ?: return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
        val upper = activeBracket.upperAudibleDb ?: return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)

        val span = upper - lower
        if (span <= config.resolutionDb) {
            // Threshold is the lowest level heard (upper bound of resolved bracket)
            val threshold = ThresholdResult(
                ear = currentEar,
                frequencyHz = currentFrequencyHz,
                thresholdDb = upper,
                validAscendingResponses = 1,
                totalTrialsForTarget = validTrialCount,
                method = "BINARY_SEARCH_REFINEMENT",
                confidence = "EXPERIMENTAL_BINARY_REFINED",
                strategyVersion = strategyVersion,
                bracketLowerDb = lower,
                bracketUpperDb = upper
            )
            _thresholdResults.add(threshold)
            activeBracket.isResolved = true

            val next = advanceToNextTarget()
            return if (next != null) {
                StrategyResult.ThresholdFound(threshold, next)
            } else {
                StrategyResult.AllTargetsCompleted
            }
        }

        // Calculate deterministic midpoint
        val mid = calculateMidpoint(lower, upper, config.midpointRounding, config.gridStepDb)

        // Edge case: if midpoint equals one of the bounds, interval cannot be halved further
        if (mid <= lower || mid >= upper) {
            val threshold = ThresholdResult(
                ear = currentEar,
                frequencyHz = currentFrequencyHz,
                thresholdDb = upper,
                validAscendingResponses = 1,
                totalTrialsForTarget = validTrialCount,
                method = "BINARY_SEARCH_REFINEMENT",
                confidence = "EXPERIMENTAL_BINARY_REFINED",
                strategyVersion = strategyVersion,
                bracketLowerDb = lower,
                bracketUpperDb = upper
            )
            _thresholdResults.add(threshold)
            activeBracket.isResolved = true

            val next = advanceToNextTarget()
            return if (next != null) {
                StrategyResult.ThresholdFound(threshold, next)
            } else {
                StrategyResult.AllTargetsCompleted
            }
        }

        currentLevelDb = mid
        return StrategyResult.NextTrial(currentEar, currentFrequencyHz, currentLevelDb)
    }

    /**
     * Deterministic midpoint computation with explicit rounding / grid policies.
     */
    fun calculateMidpoint(
        lower: Int,
        upper: Int,
        policy: MidpointRoundingPolicy,
        gridStepDb: Int = 5
    ): Int {
        val rawMid = (lower + upper) / 2.0
        return when (policy) {
            MidpointRoundingPolicy.ROUND_UP -> ceil(rawMid).toInt()
            MidpointRoundingPolicy.ROUND_DOWN -> floor(rawMid).toInt()
            MidpointRoundingPolicy.SNAP_GRID_UP -> {
                val step = gridStepDb.toDouble()
                (ceil(rawMid / step) * step).toInt()
            }
            MidpointRoundingPolicy.SNAP_GRID_DOWN -> {
                val step = gridStepDb.toDouble()
                (floor(rawMid / step) * step).toInt()
            }
        }
    }

    private fun advanceToNextTarget(): TargetPair? {
        frequencyIndex++
        if (frequencyIndex < config.frequencies.size) {
            initTargetBracket()
            return TargetPair(currentEar, currentFrequencyHz)
        }

        frequencyIndex = 0
        earIndex++
        if (earIndex < config.ears.size) {
            initTargetBracket()
            return TargetPair(currentEar, currentFrequencyHz)
        }

        return null
    }

    private fun initTargetBracket() {
        if (!isComplete()) {
            activeBracket = TargetBracketState(
                ear = currentEar,
                frequencyHz = currentFrequencyHz
            )
            currentLevelDb = config.startingLevelDb
        }
    }

    override fun isComplete(): Boolean {
        return earIndex >= config.ears.size
    }

    override fun reset() {
        earIndex = 0
        frequencyIndex = 0
        currentLevelDb = config.startingLevelDb
        _allTrials.clear()
        _thresholdResults.clear()
        initTargetBracket()
    }

    /** Inspection helper: exposes active target bracket */
    fun getActiveBracket(): TargetBracketState = activeBracket
}
