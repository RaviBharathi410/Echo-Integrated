package com.echo.hearing

import com.echo.hearing.domain.model.AudiometricFrequencies
import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.TrialOutcome
import com.echo.hearing.domain.threshold.*
import org.junit.Assert.*
import org.junit.Test

class BinarySearchStrategyTest {

    @Test
    fun `initial bracket established when user hears at 40 dB and steps down to inaudible at 20 dB`() {
        val config = BinarySearchConfig(
            startingLevelDb = 40,
            bracketStepDb = 20,
            resolutionDb = 5,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val strategy = BinarySearchStrategy(config)

        // Trial 1: 40 dB -> HEARD (establishes upperAudible = 40)
        assertEquals(40, strategy.currentLevelDb)
        val r1 = strategy.evaluateTrial(TrialOutcome.HEARD)
        assertTrue(r1 is StrategyResult.NextTrial)
        // Steps down by 20 to 20 dB
        assertEquals(20, strategy.currentLevelDb)
        assertFalse(strategy.getActiveBracket().isBracketEstablished)
        assertEquals(40, strategy.getActiveBracket().upperAudibleDb)
        assertNull(strategy.getActiveBracket().lowerInaudibleDb)

        // Trial 2: 20 dB -> NOT_HEARD (establishes lowerInaudible = 20)
        val r2 = strategy.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertTrue(strategy.getActiveBracket().isBracketEstablished)
        assertEquals(20, strategy.getActiveBracket().lowerInaudibleDb)
        assertEquals(40, strategy.getActiveBracket().upperAudibleDb)

        // With bracket [20, 40], span is 20 > 5, midpoint is (20 + 40)/2 = 30
        assertTrue(r2 is StrategyResult.NextTrial)
        assertEquals(30, strategy.currentLevelDb)
    }

    @Test
    fun `initial bracket established when user does not hear at 40 dB and steps up to audible at 60 dB`() {
        val config = BinarySearchConfig(
            startingLevelDb = 40,
            bracketStepDb = 20,
            resolutionDb = 5,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val strategy = BinarySearchStrategy(config)

        // Trial 1: 40 dB -> NOT_HEARD (establishes lowerInaudible = 40)
        assertEquals(40, strategy.currentLevelDb)
        val r1 = strategy.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertTrue(r1 is StrategyResult.NextTrial)
        // Steps up by 20 to 60 dB
        assertEquals(60, strategy.currentLevelDb)
        assertFalse(strategy.getActiveBracket().isBracketEstablished)
        assertEquals(40, strategy.getActiveBracket().lowerInaudibleDb)
        assertNull(strategy.getActiveBracket().upperAudibleDb)

        // Trial 2: 60 dB -> HEARD (establishes upperAudible = 60)
        val r2 = strategy.evaluateTrial(TrialOutcome.HEARD)
        assertTrue(strategy.getActiveBracket().isBracketEstablished)
        assertEquals(40, strategy.getActiveBracket().lowerInaudibleDb)
        assertEquals(60, strategy.getActiveBracket().upperAudibleDb)

        // With bracket [40, 60], span is 20 > 5, midpoint is (40 + 60)/2 = 50
        assertTrue(r2 is StrategyResult.NextTrial)
        assertEquals(50, strategy.currentLevelDb)
    }

    @Test
    fun `contaminated and invalid trials never alter bracket bounds or presentation level`() {
        val config = BinarySearchConfig(
            startingLevelDb = 40,
            bracketStepDb = 20,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val strategy = BinarySearchStrategy(config)

        // Trial 1: contaminated by noise at 40 dB
        val r1 = strategy.evaluateTrial(TrialOutcome.CONTAMINATED_BY_NOISE, ambientNoiseDbFs = -25.0)
        assertTrue(r1 is StrategyResult.NextTrial)
        assertEquals(40, strategy.currentLevelDb)
        assertNull(strategy.getActiveBracket().lowerInaudibleDb)
        assertNull(strategy.getActiveBracket().upperAudibleDb)

        // Trial 2: valid heard -> sets upperAudible = 40, next = 20
        strategy.evaluateTrial(TrialOutcome.HEARD)
        assertEquals(20, strategy.currentLevelDb)
        assertEquals(40, strategy.getActiveBracket().upperAudibleDb)

        // Trial 3: interrupted invalid at 20 dB
        val r3 = strategy.evaluateTrial(TrialOutcome.INVALID_INTERRUPTED)
        assertTrue(r3 is StrategyResult.NextTrial)
        // Must stay at 20 dB and NOT update lower bound
        assertEquals(20, strategy.currentLevelDb)
        assertNull(strategy.getActiveBracket().lowerInaudibleDb)
        assertEquals(40, strategy.getActiveBracket().upperAudibleDb)
    }

    @Test
    fun `floor limit reached without inaudible response produces Inconclusive`() {
        val config = BinarySearchConfig(
            startingLevelDb = 20,
            bracketStepDb = 20,
            minLevelDb = 0,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val strategy = BinarySearchStrategy(config)

        // Trial 1 at 20 dB -> HEARD -> next is 0 dB
        strategy.evaluateTrial(TrialOutcome.HEARD)
        assertEquals(0, strategy.currentLevelDb)

        // Trial 2 at 0 dB -> HEARD -> cannot step below minLevelDb (0 dB)
        val r2 = strategy.evaluateTrial(TrialOutcome.HEARD)
        assertTrue(r2 is StrategyResult.Inconclusive)
        val inc = r2 as StrategyResult.Inconclusive
        assertEquals(Ear.LEFT, inc.ear)
        assertEquals(1000, inc.frequencyHz)
        assertTrue(inc.reason.contains("floor level"))
    }

    @Test
    fun `ceiling limit reached without audible response produces Inconclusive`() {
        val config = BinarySearchConfig(
            startingLevelDb = 60,
            bracketStepDb = 20,
            maxLevelDb = 80,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val strategy = BinarySearchStrategy(config)

        // Trial 1 at 60 dB -> NOT_HEARD -> next is 80 dB
        strategy.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(80, strategy.currentLevelDb)

        // Trial 2 at 80 dB -> NOT_HEARD -> cannot step above maxLevelDb (80 dB)
        val r2 = strategy.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertTrue(r2 is StrategyResult.Inconclusive)
        val inc = r2 as StrategyResult.Inconclusive
        assertEquals(Ear.LEFT, inc.ear)
        assertEquals(1000, inc.frequencyHz)
        assertTrue(inc.reason.contains("ceiling level"))
    }

    // --- Deterministic Midpoint Tests for Clarification 4 (60–65 dB case) ---

    @Test
    fun `midpoint rounding deterministic test - 60 to 65 bracket with ROUND_UP policy`() {
        // Lower = 60 (inaudible), Upper = 65 (audible)
        // Midpoint calculation: (60 + 65) / 2.0 = 62.5
        // Under ROUND_UP: ceil(62.5) = 63
        // Under ROUND_DOWN: floor(62.5) = 62
        val configRoundUp = BinarySearchConfig(
            startingLevelDb = 65,
            bracketStepDb = 5,
            resolutionDb = 2, // resolution smaller than 5 to force midpoint testing
            midpointRounding = MidpointRoundingPolicy.ROUND_UP,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )

        // Outcome A: User hears at midpoint (63 dB)
        val strategyA = BinarySearchStrategy(configRoundUp)
        // 1. Establish bracket [60, 65]
        strategyA.evaluateTrial(TrialOutcome.HEARD) // Heard at 65 -> upperAudible = 65, next = 60
        strategyA.evaluateTrial(TrialOutcome.NOT_HEARD) // Not heard at 60 -> lowerInaudible = 60
        assertTrue(strategyA.getActiveBracket().isBracketEstablished)
        assertEquals(60, strategyA.getActiveBracket().lowerInaudibleDb)
        assertEquals(65, strategyA.getActiveBracket().upperAudibleDb)

        // Next level must be exactly 63 dB (ceil of 62.5)
        assertEquals(63, strategyA.currentLevelDb)

        // Outcome A: User HEARD at 63 dB -> narrows bracket to [60, 63]
        val resA = strategyA.evaluateTrial(TrialOutcome.HEARD)
        assertEquals(60, strategyA.getActiveBracket().lowerInaudibleDb)
        assertEquals(63, strategyA.getActiveBracket().upperAudibleDb)

        // Outcome B: User does NOT hear at midpoint (63 dB)
        val strategyB = BinarySearchStrategy(configRoundUp)
        strategyB.evaluateTrial(TrialOutcome.HEARD) // Heard at 65
        strategyB.evaluateTrial(TrialOutcome.NOT_HEARD) // Not heard at 60
        assertEquals(63, strategyB.currentLevelDb)

        // User NOT_HEARD at 63 dB -> narrows bracket to [63, 65]
        val resB = strategyB.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(63, strategyB.getActiveBracket().lowerInaudibleDb)
        assertEquals(65, strategyB.getActiveBracket().upperAudibleDb)
    }

    @Test
    fun `midpoint rounding deterministic test - 60 to 65 bracket with ROUND_DOWN policy`() {
        val configRoundDown = BinarySearchConfig(
            startingLevelDb = 65,
            bracketStepDb = 5,
            resolutionDb = 2,
            midpointRounding = MidpointRoundingPolicy.ROUND_DOWN,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )

        val strategy = BinarySearchStrategy(configRoundDown)
        strategy.evaluateTrial(TrialOutcome.HEARD) // Heard at 65
        strategy.evaluateTrial(TrialOutcome.NOT_HEARD) // Not heard at 60

        // With ROUND_DOWN, midpoint of 62.5 is exactly 62
        assertEquals(62, strategy.currentLevelDb)

        // User HEARD at 62 -> bracket becomes [60, 62]
        strategy.evaluateTrial(TrialOutcome.HEARD)
        assertEquals(60, strategy.getActiveBracket().lowerInaudibleDb)
        assertEquals(62, strategy.getActiveBracket().upperAudibleDb)
    }

    @Test
    fun `midpoint calculation helper direct verification`() {
        val strategy = BinarySearchStrategy()
        // 60 and 65: raw midpoint 62.5
        assertEquals(63, strategy.calculateMidpoint(60, 65, MidpointRoundingPolicy.ROUND_UP))
        assertEquals(62, strategy.calculateMidpoint(60, 65, MidpointRoundingPolicy.ROUND_DOWN))
        assertEquals(65, strategy.calculateMidpoint(60, 65, MidpointRoundingPolicy.SNAP_GRID_UP, gridStepDb = 5))
        assertEquals(60, strategy.calculateMidpoint(60, 65, MidpointRoundingPolicy.SNAP_GRID_DOWN, gridStepDb = 5))
    }

    @Test
    fun `converges to threshold when span is less than or equal to resolution`() {
        val config = BinarySearchConfig(
            startingLevelDb = 40,
            bracketStepDb = 20,
            resolutionDb = 5,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val strategy = BinarySearchStrategy(config)

        // Trial 1: 40 HEARD -> next = 20
        strategy.evaluateTrial(TrialOutcome.HEARD)
        // Trial 2: 20 NOT_HEARD -> bracket [20, 40], next = 30
        strategy.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(30, strategy.currentLevelDb)

        // Trial 3: 30 NOT_HEARD -> bracket [30, 40], next = 35
        strategy.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(35, strategy.currentLevelDb)

        // Trial 4: 35 HEARD -> bracket [30, 35]. Span is 5 <= resolution (5)!
        val res = strategy.evaluateTrial(TrialOutcome.HEARD)
        assertTrue(res is StrategyResult.AllTargetsCompleted)
        assertEquals(1, strategy.thresholdResults.size)
        val threshold = strategy.thresholdResults.first()
        assertEquals(35, threshold.thresholdDb)
        assertEquals(30, threshold.bracketLowerDb)
        assertEquals(35, threshold.bracketUpperDb)
        assertEquals("BINARY_SEARCH_REFINEMENT", threshold.method)
    }
}
