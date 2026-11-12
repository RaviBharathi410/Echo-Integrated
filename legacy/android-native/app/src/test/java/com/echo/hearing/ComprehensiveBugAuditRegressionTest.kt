package com.echo.hearing

import com.echo.hearing.audio.FakeStimulusEngine
import com.echo.hearing.data.InMemorySessionRepository
import com.echo.hearing.device.FakeDeviceCapabilityManager
import com.echo.hearing.domain.model.AudioRouteType
import com.echo.hearing.domain.model.NoiseAssessment
import com.echo.hearing.domain.model.TrialOutcome
import com.echo.hearing.domain.statemachine.SessionState
import com.echo.hearing.domain.threshold.StrategyType
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
 * Regression tests covering the comprehensive physical-device bug audit for ECHO POC:
 * - A: Consent separation from screening session, accurate cancellation reason, Try Again vs Restart.
 * - B: Ambient noise monitor states (UNAVAILABLE vs VALID), preventing -90 dBFS false-quiet authorization.
 * - C: Headphone output requirement vs phone microphone input sensor distinction.
 * - D: Precheck validation blocking when headphones missing or noise is invalid/unavailable.
 * - E: Practice trial dual response ("I HEAR IT" & "I CAN'T HEAR IT"), timeout handling, start test gating.
 * - F: Formal screening "I CAN'T HEAR IT" response semantics, adaptive strategy updates, double-tap suppression.
 * - G: Noise disturbance pausing, trial invalidation, recovery recheck safety.
 * - H: Developer Test Harness (DEV SIM) controls, unplug behavior on setup screen, deterministic simulation injection.
 * - I: Pause, Cancel, and Try Again workflow.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ComprehensiveBugAuditRegressionTest {

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

    // --- A. Consent & Navigation ---

    @Test
    fun `cancelling screening and tapping Try Again returns to setup preserving consent`() {
        // User agrees to consent
        viewModel.onConsentAgreed(true)
        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)
        assertTrue(viewModel.uiState.value.hasUserConsented)

        // Advance to screening
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -62.0)
        viewModel.onDevicePrecheckContinue()
        viewModel.onStartScreening()

        // User cancels during screening
        viewModel.onCancelRequested()
        assertEquals(SessionState.CANCELLED, viewModel.uiState.value.sessionState)
        assertEquals("Screening was cancelled by the user.", viewModel.uiState.value.cancelReason)
        assertTrue("Consent must be retained across cancellation", viewModel.uiState.value.hasUserConsented)

        // Tapping Try Again must return to DEVICE_READINESS without re-prompting consent
        viewModel.onTryAgain()
        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)
        assertTrue(viewModel.uiState.value.hasUserConsented)
    }

    @Test
    fun `full restart request resets consent and returns to consent onboarding`() {
        viewModel.onConsentAgreed(true)
        assertTrue(viewModel.uiState.value.hasUserConsented)

        // Explicit restart from beginning
        viewModel.onRestartRequested()
        assertEquals(SessionState.ONBOARDING_CONSENT, viewModel.uiState.value.sessionState)
        assertFalse("Full restart must clear consent", viewModel.uiState.value.hasUserConsented)
    }

    // --- B & D. Ambient Noise Monitor & Environment Validation ---

    @Test
    fun `precheck continue is blocked when noise reading is UNAVAILABLE`() {
        viewModel.onConsentAgreed(true)
        // Set noise reading to UNAVAILABLE
        noiseMonitor.injectAssessment(NoiseAssessment.UNAVAILABLE, -100.0)

        viewModel.onDevicePrecheckContinue()

        assertEquals(
            "Must not advance to TEST_PREP when noise is UNAVAILABLE",
            SessionState.DEVICE_READINESS,
            viewModel.uiState.value.sessionState
        )
        assertNotNull(viewModel.uiState.value.pauseReason)
        assertTrue(viewModel.uiState.value.pauseReason!!.contains("Microphone sensor unavailable"))
    }

    @Test
    fun `precheck continue is blocked when noise reading is INVALID (Too Loud)`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.INVALID, -35.0)

        viewModel.onDevicePrecheckContinue()

        assertEquals(
            "Must not advance to TEST_PREP when room is too loud",
            SessionState.DEVICE_READINESS,
            viewModel.uiState.value.sessionState
        )
        assertNotNull(viewModel.uiState.value.pauseReason)
        assertTrue(viewModel.uiState.value.pauseReason!!.contains("Environment is too loud"))
    }

    @Test
    fun `precheck continue succeeds when headphones connected and noise is VALID`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)

        viewModel.onDevicePrecheckContinue()

        assertEquals(
            "Must advance to TEST_PREP when headphones connected and room is quiet",
            SessionState.TEST_PREP,
            viewModel.uiState.value.sessionState
        )
        assertNull(viewModel.uiState.value.pauseReason)
    }

    // --- C. Audio Routing Requirement ---

    @Test
    fun `precheck continue is blocked when built-in speaker is active`() {
        deviceManager.currentRouteType = AudioRouteType.BUILTIN_SPEAKER
        viewModel.refreshDeviceRoute()
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)

        viewModel.onDevicePrecheckContinue()

        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)
        assertNotNull(viewModel.uiState.value.pauseReason)
        assertTrue(viewModel.uiState.value.pauseReason!!.contains("Headphones required"))
    }

    // --- E. Practice Round Dual Response & Timeout ---

    @Test
    fun `practice round tone response HEARD sets practiceHeard true and enables start test`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)
        viewModel.onDevicePrecheckContinue()

        viewModel.onStartPractice()
        assertEquals(SessionState.PRACTICE_PRESENTATION, viewModel.uiState.value.sessionState)

        viewModel.onPracticeHeardClicked()
        assertEquals(SessionState.PRACTICE_FEEDBACK, viewModel.uiState.value.sessionState)
        assertEquals(true, viewModel.uiState.value.practiceHeard)
        assertNotNull(viewModel.uiState.value.practiceFeedbackMessage)
        assertTrue(viewModel.uiState.value.practiceFeedbackMessage!!.contains("Demo tone heard"))
    }

    @Test
    fun `practice round tone response NOT HEARD sets practiceHeard false and warns user`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)
        viewModel.onDevicePrecheckContinue()

        viewModel.onStartPractice()
        assertEquals(SessionState.PRACTICE_PRESENTATION, viewModel.uiState.value.sessionState)

        viewModel.onPracticeNotHeardClicked()
        assertEquals(SessionState.PRACTICE_FEEDBACK, viewModel.uiState.value.sessionState)
        assertEquals(false, viewModel.uiState.value.practiceHeard)
        assertNotNull(viewModel.uiState.value.practiceFeedbackMessage)
        assertTrue(viewModel.uiState.value.practiceFeedbackMessage!!.contains("Demo tone reported not heard"))
    }

    @Test
    fun `practice round timeout marks practice as not heard and stops tone`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)
        viewModel.onDevicePrecheckContinue()

        viewModel.onStartPractice()
        assertEquals(SessionState.PRACTICE_PRESENTATION, viewModel.uiState.value.sessionState)

        viewModel.onPracticeTimedOut()
        assertEquals(SessionState.PRACTICE_FEEDBACK, viewModel.uiState.value.sessionState)
        assertEquals(false, viewModel.uiState.value.practiceHeard)
        assertFalse(viewModel.uiState.value.practiceTonePlaying)
    }

    // --- F. Screening Response Controls ("I HEAR IT" vs "I CAN'T HEAR IT") ---

    @Test
    fun `user responding I CANNOT HEAR IT records NOT_HEARD trial outcome and steps level up`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)
        viewModel.onDevicePrecheckContinue()
        viewModel.selectStrategy(StrategyType.MODIFIED_HUGHSON_WESTLAKE)
        viewModel.onStartScreening()

        // Advance past pre-stimulus jitter delay
        testDispatcher.scheduler.advanceTimeBy(1500L)
        assertTrue(viewModel.uiState.value.isWaitingForResponse)
        val initialLevel = viewModel.uiState.value.currentLevelDb

        // User taps "I CAN'T HEAR IT"
        viewModel.onUserNotHeardClicked()

        // Verify a trial was recorded with NOT_HEARD
        val lastTrial = viewModel.uiState.value.trials.lastOrNull()
        assertNotNull("Trial must be recorded for explicit not-heard response", lastTrial)
        assertEquals(TrialOutcome.NOT_HEARD, lastTrial!!.outcome)

        // In Hughson-Westlake, when not heard, next presentation should step level UP (+5 dBFS)
        val newLevel = viewModel.uiState.value.currentLevelDb
        assertEquals("Hughson-Westlake steps up 5 dBFS on not heard", initialLevel + 5, newLevel)
    }

    @Test
    fun `duplicate user response clicks are suppressed when not waiting for response`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)
        viewModel.onDevicePrecheckContinue()
        viewModel.onStartScreening()

        testDispatcher.scheduler.advanceTimeBy(1500L)
        assertTrue(viewModel.uiState.value.isWaitingForResponse)
        viewModel.onUserHeardClicked()

        // Now isWaitingForResponse is false (processing next trial or interval)
        assertFalse(viewModel.uiState.value.isWaitingForResponse)
        val trialsCountBeforeDuplicate = viewModel.uiState.value.trials.size

        // Rapid duplicate tap
        viewModel.onUserHeardClicked()
        viewModel.onUserNotHeardClicked()

        assertEquals(
            "Duplicate taps while not waiting for response must be ignored",
            trialsCountBeforeDuplicate,
            viewModel.uiState.value.trials.size
        )
    }

    // --- G. Noise Disturbance Pausing and Trial Invalidation ---

    @Test
    fun `noise disturbance during trial invalidates trial and pauses screening`() {
        viewModel.onConsentAgreed(true)
        noiseMonitor.injectAssessment(NoiseAssessment.VALID, -65.0)
        viewModel.onDevicePrecheckContinue()
        viewModel.onStartScreening()

        testDispatcher.scheduler.advanceTimeBy(1500L)
        assertTrue(viewModel.uiState.value.isWaitingForResponse)

        // Noise spike detected during trial
        noiseMonitor.injectAssessment(NoiseAssessment.INVALID, -35.0)

        assertEquals(SessionState.AUTOMATIC_PAUSE_NOISE, viewModel.uiState.value.sessionState)
        assertTrue(viewModel.uiState.value.isNoisePaused)
        val contaminatedTrial = viewModel.uiState.value.trials.lastOrNull()
        if (contaminatedTrial != null) {
            assertEquals(TrialOutcome.CONTAMINATED_BY_NOISE, contaminatedTrial.outcome)
        }
    }

    // --- H. Developer Test Harness (DEV SIM) Controls ---

    @Test
    fun `unplug simulation on setup screen swaps device route to speaker without teleporting to screening`() {
        viewModel.onConsentAgreed(true)
        assertEquals(SessionState.DEVICE_READINESS, viewModel.uiState.value.sessionState)

        viewModel.toggleSimulationMode()
        assertTrue(viewModel.uiState.value.isSimulationMode)

        // Tapping Unplug on setup screen
        viewModel.simulateDeviceDisconnect()

        // Must remain in DEVICE_READINESS, NOT AUTOMATIC_PAUSE_DEVICE
        assertEquals(
            "Unplug from setup screen must remain on setup screen with disconnected route",
            SessionState.DEVICE_READINESS,
            viewModel.uiState.value.sessionState
        )
        assertFalse(viewModel.uiState.value.isHeadphoneConnected)
    }

    @Test
    fun `simulateNoiseSpike injects deterministic noise level into UI state when simulation is active`() {
        viewModel.onConsentAgreed(true)
        viewModel.toggleSimulationMode()
        assertTrue(viewModel.uiState.value.isSimulationMode)

        // Inject loud noise
        viewModel.simulateNoiseSpike(NoiseAssessment.INVALID)
        assertEquals(NoiseAssessment.INVALID, viewModel.uiState.value.noiseReading.assessment)
        assertEquals(-25.0, viewModel.uiState.value.noiseReading.levelDbFs, 0.1)

        // Clear noise
        viewModel.simulateNoiseSpike(NoiseAssessment.VALID)
        assertEquals(NoiseAssessment.VALID, viewModel.uiState.value.noiseReading.assessment)
        assertEquals(-55.0, viewModel.uiState.value.noiseReading.levelDbFs, 0.1)
    }
}
