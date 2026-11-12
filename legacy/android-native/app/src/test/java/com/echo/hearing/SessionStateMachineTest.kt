package com.echo.hearing

import com.echo.hearing.domain.model.AudioRouteInfo
import com.echo.hearing.domain.model.AudioRouteType
import com.echo.hearing.domain.model.CalibrationInfo
import com.echo.hearing.domain.model.CalibrationProvenance
import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.NoiseAssessment
import com.echo.hearing.domain.statemachine.SessionEvent
import com.echo.hearing.domain.statemachine.SessionState
import com.echo.hearing.domain.statemachine.SessionStateMachine
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class SessionStateMachineTest {

    private lateinit var sm: SessionStateMachine

    private val supportedRoute = AudioRouteInfo(
        routeType = AudioRouteType.WIRED_HEADPHONES,
        deviceName = "Test Headphones",
        isStereoCapable = true,
        sampleRateHz = 44100,
        calibrationInfo = CalibrationInfo("Test", AudioRouteType.WIRED_HEADPHONES, CalibrationProvenance.FIXTURE_DEFAULT, true)
    )

    private val unsupportedRoute = AudioRouteInfo(
        routeType = AudioRouteType.BUILTIN_SPEAKER,
        deviceName = "Phone Speaker",
        isStereoCapable = true,
        sampleRateHz = 44100,
        calibrationInfo = CalibrationInfo("Test", AudioRouteType.BUILTIN_SPEAKER, CalibrationProvenance.UNCALIBRATED, false)
    )

    @Before
    fun setUp() {
        sm = SessionStateMachine()
    }

    @Test
    fun `starts in NOT_STARTED state`() {
        assertEquals(SessionState.NOT_STARTED, sm.currentState)
    }

    @Test
    fun `valid onboarding and consent transitions`() {
        sm.transition(SessionEvent.StartOnboarding)
        assertEquals(SessionState.ONBOARDING_CONSENT, sm.currentState)

        sm.transition(SessionEvent.ConsentAgreed(true))
        assertEquals(SessionState.DEVICE_READINESS, sm.currentState)
    }

    @Test
    fun `declined consent aborts session`() {
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.ConsentAgreed(false))
        assertEquals(SessionState.ABORTED, sm.currentState)
    }

    @Test
    fun `unsupported audio route aborts session`() {
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.ConsentAgreed(true))
        sm.transition(SessionEvent.DeviceEvaluated(unsupportedRoute, isSupported = false))
        assertEquals(SessionState.ABORTED, sm.currentState)
    }

    @Test
    fun `supported route proceeds through calibration and noise precheck`() {
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.ConsentAgreed(true))
        sm.transition(SessionEvent.DeviceEvaluated(supportedRoute, isSupported = true))
        assertEquals(SessionState.CALIBRATION_GATE, sm.currentState)

        sm.transition(SessionEvent.CalibrationEvaluated(supportedRoute.calibrationInfo))
        assertEquals(SessionState.ENVIRONMENTAL_NOISE_CHECK, sm.currentState)

        sm.transition(SessionEvent.NoiseBaselineChecked(NoiseAssessment.VALID))
        assertEquals(SessionState.TEST_PREP, sm.currentState)
    }

    @Test
    fun `noisy environment causes automatic pause during precheck`() {
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.ConsentAgreed(true))
        sm.transition(SessionEvent.DeviceEvaluated(supportedRoute, isSupported = true))
        sm.transition(SessionEvent.CalibrationEvaluated(supportedRoute.calibrationInfo))
        sm.transition(SessionEvent.NoiseBaselineChecked(NoiseAssessment.INVALID))
        assertEquals(SessionState.AUTOMATIC_PAUSE_NOISE, sm.currentState)
    }

    @Test
    fun `illegal transitions are rejected with IllegalStateException`() {
        // Cannot jump directly from NOT_STARTED to STIMULUS_PRESENTATION
        assertThrows(IllegalStateException::class.java) {
            sm.transition(SessionEvent.StartTest)
        }
    }

    @Test
    fun `cancellation is allowed from any active state`() {
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.CancelRequested)
        assertEquals(SessionState.CANCELLED, sm.currentState)
    }

    @Test
    fun `restart resets state to NOT_STARTED`() {
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.RestartRequested)
        assertEquals(SessionState.NOT_STARTED, sm.currentState)
    }

    @Test
    fun `practice round flow transitions correctly`() {
        // Navigate to TEST_PREP
        sm.transition(SessionEvent.StartOnboarding)
        sm.transition(SessionEvent.ConsentAgreed(true))
        sm.transition(SessionEvent.DeviceEvaluated(supportedRoute, isSupported = true))
        sm.transition(SessionEvent.CalibrationEvaluated(supportedRoute.calibrationInfo))
        sm.transition(SessionEvent.NoiseBaselineChecked(NoiseAssessment.VALID))
        assertEquals(SessionState.TEST_PREP, sm.currentState)

        // Start Practice
        sm.transition(SessionEvent.StartPractice)
        assertEquals(SessionState.PRACTICE_PRESENTATION, sm.currentState)

        // Practice response
        sm.transition(SessionEvent.PracticeResponseReceived(heard = true, latencyMs = 400L))
        assertEquals(SessionState.PRACTICE_FEEDBACK, sm.currentState)

        // Finish practice and proceed to formal screening
        sm.transition(SessionEvent.StartTest)
        assertEquals(SessionState.STIMULUS_PRESENTATION, sm.currentState)
    }
}
