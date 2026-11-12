package com.echo.hearing

import com.echo.hearing.domain.model.*
import com.echo.hearing.domain.quality.TrialQualityController
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class TrialQualityControllerTest {

    private lateinit var controller: TrialQualityController

    private val validRoute = AudioRouteInfo(
        routeType = AudioRouteType.WIRED_HEADPHONES,
        deviceName = "Standard 3.5mm Headset",
        isStereoCapable = true,
        sampleRateHz = 44100,
        calibrationInfo = CalibrationInfo("Test", AudioRouteType.WIRED_HEADPHONES, CalibrationProvenance.FIXTURE_DEFAULT, true)
    )

    private val speakerRoute = AudioRouteInfo(
        routeType = AudioRouteType.BUILTIN_SPEAKER,
        deviceName = "Phone Speaker",
        isStereoCapable = true,
        sampleRateHz = 44100,
        calibrationInfo = CalibrationInfo("Test", AudioRouteType.BUILTIN_SPEAKER, CalibrationProvenance.UNCALIBRATED, false)
    )

    @Before
    fun setUp() {
        controller = TrialQualityController(minPlausibleLatencyMs = 150L, maxPlausibleLatencyMs = 3000L)
    }

    @Test
    fun `valid response with plausible latency produces HEARD outcome`() {
        val eval = controller.evaluateTrialQuality(
            userTappedHeard = true,
            latencyMs = 450L,
            noiseAssessment = NoiseAssessment.VALID,
            isNoiseDisturbedDuringTrial = false,
            routeInfo = validRoute
        )

        assertTrue(eval.isTrialValid)
        assertEquals(TrialOutcome.HEARD, eval.outcome)
        assertEquals(450L, eval.latencyMs)
        assertTrue(eval.isPlausibleLatency)
    }

    @Test
    fun `anticipatory false alarm tap is rejected as INVALID_INTERRUPTED`() {
        val eval = controller.evaluateTrialQuality(
            userTappedHeard = true,
            latencyMs = 80L, // < 150ms physiological auditory reaction time
            noiseAssessment = NoiseAssessment.VALID,
            isNoiseDisturbedDuringTrial = false,
            routeInfo = validRoute
        )

        assertFalse(eval.isTrialValid)
        assertEquals(TrialOutcome.INVALID_INTERRUPTED, eval.outcome)
        assertFalse(eval.isPlausibleLatency)
        assertTrue(eval.qualityFlags.contains(QualityFlag.EXCESSIVE_REVERSALS))
    }

    @Test
    fun `noise disturbance automatically invalidates trial as CONTAMINATED_BY_NOISE`() {
        val eval = controller.evaluateTrialQuality(
            userTappedHeard = true,
            latencyMs = 500L,
            noiseAssessment = NoiseAssessment.INVALID,
            isNoiseDisturbedDuringTrial = true,
            routeInfo = validRoute
        )

        assertFalse(eval.isTrialValid)
        assertEquals(TrialOutcome.CONTAMINATED_BY_NOISE, eval.outcome)
        assertTrue(eval.qualityFlags.contains(QualityFlag.ENVIRONMENTAL_NOISE_PAUSES_DETECTED))
    }

    @Test
    fun `speaker route or missing headphones invalidates trial as INVALID_INTERRUPTED`() {
        val eval = controller.evaluateTrialQuality(
            userTappedHeard = true,
            latencyMs = 500L,
            noiseAssessment = NoiseAssessment.VALID,
            isNoiseDisturbedDuringTrial = false,
            routeInfo = speakerRoute
        )

        assertFalse(eval.isTrialValid)
        assertEquals(TrialOutcome.INVALID_INTERRUPTED, eval.outcome)
        assertTrue(eval.qualityFlags.contains(QualityFlag.AUDIO_ROUTE_CHANGED_DURING_TEST))
    }

    @Test
    fun `explicit not-heard response produces NOT_HEARD outcome`() {
        val eval = controller.evaluateTrialQuality(
            userTappedHeard = false,
            latencyMs = 800L,
            noiseAssessment = NoiseAssessment.VALID,
            isNoiseDisturbedDuringTrial = false,
            routeInfo = validRoute,
            explicitNotHeard = true
        )

        assertTrue(eval.isTrialValid)
        assertEquals(TrialOutcome.NOT_HEARD, eval.outcome)
        assertEquals(800L, eval.latencyMs)
    }

    @Test
    fun `missing response on timeout produces UNANSWERED_TIMEOUT and is not treated as not-heard`() {
        val eval = controller.evaluateTrialQuality(
            userTappedHeard = false,
            latencyMs = null,
            noiseAssessment = NoiseAssessment.VALID,
            isNoiseDisturbedDuringTrial = false,
            routeInfo = validRoute,
            explicitNotHeard = false
        )

        assertFalse(eval.isTrialValid)
        assertEquals(TrialOutcome.UNANSWERED_TIMEOUT, eval.outcome)
        assertNull(eval.latencyMs)
    }
}
