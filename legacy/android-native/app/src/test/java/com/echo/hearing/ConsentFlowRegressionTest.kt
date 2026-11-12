package com.echo.hearing

import com.echo.hearing.audio.FakeStimulusEngine
import com.echo.hearing.data.InMemorySessionRepository
import com.echo.hearing.device.FakeDeviceCapabilityManager
import com.echo.hearing.domain.model.AudioRouteType
import com.echo.hearing.domain.statemachine.SessionState
import com.echo.hearing.noise.FakeNoiseMonitor
import com.echo.hearing.ui.HearingScreeningViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Regression tests for the first-launch consent crash.
 *
 * Root cause: SessionStateMachine starts in NOT_STARTED, but OnboardingScreen's
 * "Agree & Continue" button fired ConsentAgreed directly. The state machine
 * only accepts ConsentAgreed from ONBOARDING_CONSENT, so it threw an unhandled
 * IllegalStateException, crashing the app.
 *
 * Fix: ViewModel.init now transitions to ONBOARDING_CONSENT immediately,
 * and onConsentAgreed includes a defensive guard to ensure the transition
 * through StartOnboarding if somehow still in NOT_STARTED.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConsentFlowRegressionTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    private lateinit var viewModel: HearingScreeningViewModel
    private lateinit var stimulusEngine: FakeStimulusEngine
    private lateinit var noiseMonitor: FakeNoiseMonitor
    private lateinit var deviceManager: FakeDeviceCapabilityManager
    private lateinit var sessionRepository: InMemorySessionRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)

        stimulusEngine = FakeStimulusEngine()
        noiseMonitor = FakeNoiseMonitor()
        deviceManager = FakeDeviceCapabilityManager(
            initialRoute = AudioRouteType.WIRED_HEADPHONES
        )
        sessionRepository = InMemorySessionRepository()

        viewModel = HearingScreeningViewModel(
            stimulusEngine = stimulusEngine,
            noiseMonitor = noiseMonitor,
            deviceManager = deviceManager,
            sessionRepository = sessionRepository
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `init transitions state to ONBOARDING_CONSENT`() {
        // Before the fix, init did NOT call StartOnboarding,
        // leaving the state machine in NOT_STARTED.
        assertEquals(
            "ViewModel should start in ONBOARDING_CONSENT after init",
            SessionState.ONBOARDING_CONSENT,
            viewModel.uiState.value.sessionState
        )
    }

    @Test
    fun `onConsentAgreed does not throw when called from ONBOARDING_CONSENT`() {
        // This is the exact crash scenario: user taps "Agree & Continue"
        // on the onboarding screen. Before the fix, this threw IllegalStateException.
        try {
            viewModel.onConsentAgreed(true)
        } catch (e: Exception) {
            fail("onConsentAgreed should not throw, but threw: ${e.message}")
        }

        assertEquals(
            "After agreeing, state should be DEVICE_READINESS",
            SessionState.DEVICE_READINESS,
            viewModel.uiState.value.sessionState
        )
    }

    @Test
    fun `declined consent transitions to ABORTED`() {
        viewModel.onConsentAgreed(false)
        assertEquals(
            "Declining consent should abort the session",
            SessionState.ABORTED,
            viewModel.uiState.value.sessionState
        )
    }

    @Test
    fun `onConsentAgreed is safe to call multiple times`() {
        // First call — transitions to DEVICE_READINESS
        viewModel.onConsentAgreed(true)
        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)

        // Second call — should not throw (already past consent state)
        try {
            viewModel.onConsentAgreed(true)
        } catch (e: Exception) {
            fail("Duplicate onConsentAgreed should not throw, but threw: ${e.message}")
        }
    }

    @Test
    fun `restart then re-consent does not crash`() {
        // Complete the initial consent
        viewModel.onConsentAgreed(true)
        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)

        // Restart the session
        viewModel.onRestartRequested()
        assertEquals(
            "After restart, state should be ONBOARDING_CONSENT",
            SessionState.ONBOARDING_CONSENT,
            viewModel.uiState.value.sessionState
        )

        // Re-consent — this would crash without the restart fix
        try {
            viewModel.onConsentAgreed(true)
        } catch (e: Exception) {
            fail("Re-consent after restart should not throw, but threw: ${e.message}")
        }
        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)
    }

    @Test
    fun `onMicrophonePermissionResult granted refreshes device route`() {
        viewModel.onConsentAgreed(true)
        viewModel.onMicrophonePermissionResult(granted = true)
        // Should not throw; audio route should be populated
        assertNotNull(viewModel.uiState.value.audioRoute)
    }

    @Test
    fun `onMicrophonePermissionResult denied sets noise to UNAVAILABLE`() {
        viewModel.onConsentAgreed(true)
        viewModel.onMicrophonePermissionResult(granted = false)
        assertEquals(
            com.echo.hearing.domain.model.NoiseAssessment.UNAVAILABLE,
            viewModel.uiState.value.noiseReading.assessment
        )
    }
}
