package com.echo.hearing

import com.echo.hearing.domain.model.AudiometricFrequencies
import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.TrialOutcome
import com.echo.hearing.domain.threshold.ModifiedHughsonWestlakeEngine
import com.echo.hearing.domain.threshold.ProtocolConfig
import com.echo.hearing.domain.threshold.StaircaseStepResult
import com.echo.hearing.domain.threshold.StrategyResult
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class HughsonWestlakeProtocolTest {

    private lateinit var engine: ModifiedHughsonWestlakeEngine

    @Before
    fun setUp() {
        val config = ProtocolConfig(
            startingLevelDb = 40,
            downStepDb = 10,
            upStepDb = 5,
            minLevelDb = 0,
            maxLevelDb = 80,
            requiredAscendingResponses = 2,
            frequencies = listOf(AudiometricFrequencies.FREQ_1000_HZ, AudiometricFrequencies.FREQ_2000_HZ),
            ears = listOf(Ear.LEFT, Ear.RIGHT)
        )
        engine = ModifiedHughsonWestlakeEngine(config)
    }

    @Test
    fun `starts at configured starting level and first target`() {
        assertEquals(40, engine.currentLevelDb)
        assertEquals(Ear.LEFT, engine.currentEar)
        assertEquals(AudiometricFrequencies.FREQ_1000_HZ, engine.currentFrequencyHz)
    }

    @Test
    fun `moves down 10 dB on heard and up 5 dB on not heard`() {
        // Heard at 40 -> down 10 to 30
        val r1 = engine.evaluateTrial(TrialOutcome.HEARD)
        assertTrue(r1 is StrategyResult.NextTrial)
        assertEquals(30, engine.currentLevelDb)

        // Not heard at 30 -> up 5 to 35
        val r2 = engine.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertTrue(r2 is StrategyResult.NextTrial)
        assertEquals(35, engine.currentLevelDb)

        // Not heard at 35 -> up 5 to 40
        val r3 = engine.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertTrue(r3 is StrategyResult.NextTrial)
        assertEquals(40, engine.currentLevelDb)
    }

    @Test
    fun `contaminated trial by noise does not advance level or count as non-response`() {
        assertEquals(40, engine.currentLevelDb)

        val r = engine.evaluateTrial(TrialOutcome.CONTAMINATED_BY_NOISE, ambientNoiseDbFs = -25.0)
        assertTrue(r is StrategyResult.NextTrial)
        // Level remains 40 dB
        assertEquals(40, engine.currentLevelDb)
        // Outcome recorded as contaminated
        assertEquals(TrialOutcome.CONTAMINATED_BY_NOISE, engine.allTrials.last().outcome)
    }

    @Test
    fun `invalid interrupted trial does not alter threshold search`() {
        val r = engine.evaluateTrial(TrialOutcome.INVALID_INTERRUPTED)
        assertTrue(r is StrategyResult.NextTrial)
        assertEquals(40, engine.currentLevelDb)
    }

    @Test
    fun `Hughson-Westlake threshold accepted after 2 ascending responses at same level`() {
        // Start 40: Heard -> drops to 30
        engine.evaluateTrial(TrialOutcome.HEARD)
        assertEquals(30, engine.currentLevelDb)

        // 30: Not heard -> ascends to 35
        engine.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(35, engine.currentLevelDb)

        // 35: Heard (1st ascending response at 35!) -> drops to 25
        engine.evaluateTrial(TrialOutcome.HEARD)
        assertEquals(25, engine.currentLevelDb)

        // 25: Not heard -> ascends to 30
        engine.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(30, engine.currentLevelDb)

        // 30: Not heard -> ascends to 35
        engine.evaluateTrial(TrialOutcome.NOT_HEARD)
        assertEquals(35, engine.currentLevelDb)

        // 35: Heard (2nd ascending response at 35!) -> Criterion met!
        val result = engine.evaluateTrial(TrialOutcome.HEARD)
        assertTrue("Expected ThresholdFound but got $result", result is StrategyResult.ThresholdFound)

        val thresholdFound = result as StrategyResult.ThresholdFound
        assertEquals(35, thresholdFound.result.thresholdDb)
        assertEquals(Ear.LEFT, thresholdFound.result.ear)
        assertEquals(AudiometricFrequencies.FREQ_1000_HZ, thresholdFound.result.frequencyHz)

        // Next target should be 2000 Hz Left Ear
        assertEquals(Ear.LEFT, thresholdFound.nextTarget?.ear)
        assertEquals(AudiometricFrequencies.FREQ_2000_HZ, thresholdFound.nextTarget?.frequencyHz)
    }

    @Test
    fun `ear and frequency isolation verified across full protocol`() {
        assertEquals(Ear.LEFT, engine.currentEar)
        assertEquals(1000, engine.currentFrequencyHz)

        // Force threshold completion by 2 ascending responses
        engine.evaluateTrial(TrialOutcome.HEARD) // 40 -> 30
        engine.evaluateTrial(TrialOutcome.NOT_HEARD) // 30 -> 35
        engine.evaluateTrial(TrialOutcome.HEARD) // 35 -> 25 (1st ascending at 35)
        engine.evaluateTrial(TrialOutcome.NOT_HEARD) // 25 -> 30
        engine.evaluateTrial(TrialOutcome.NOT_HEARD) // 30 -> 35
        val r1 = engine.evaluateTrial(TrialOutcome.HEARD) // 35 -> Criterion!
        assertTrue(r1 is StrategyResult.ThresholdFound)

        // Now target is 2000 Hz Left ear
        assertEquals(Ear.LEFT, engine.currentEar)
        assertEquals(2000, engine.currentFrequencyHz)
    }

    @Test
    fun `max trials guard prevents infinite search`() {
        val config = ProtocolConfig(
            startingLevelDb = 40,
            maxTrialsPerTarget = 4,
            frequencies = listOf(1000),
            ears = listOf(Ear.LEFT)
        )
        val shortEngine = ModifiedHughsonWestlakeEngine(config)

        shortEngine.evaluateTrial(TrialOutcome.NOT_HEARD)
        shortEngine.evaluateTrial(TrialOutcome.NOT_HEARD)
        shortEngine.evaluateTrial(TrialOutcome.NOT_HEARD)
        val finalStep = shortEngine.evaluateTrial(TrialOutcome.NOT_HEARD)

        assertTrue(
            "Expected AllTargetsCompleted or MaxTrialsExceeded, got $finalStep",
            finalStep is StrategyResult.AllTargetsCompleted || finalStep is StrategyResult.MaxTrialsExceeded
        )
    }

    @Test
    fun `backward compatible evaluateTrialStaircase returns StaircaseStepResult`() {
        val r = engine.evaluateTrialStaircase(TrialOutcome.HEARD)
        assertTrue(r is StaircaseStepResult.NextTrial)
        assertEquals(30, (r as StaircaseStepResult.NextTrial).nextLevelDb)
    }
}
