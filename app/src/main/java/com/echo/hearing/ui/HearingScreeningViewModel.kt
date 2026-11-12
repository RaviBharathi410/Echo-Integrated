package com.echo.hearing.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.hearing.audio.StimulusEngine
import com.echo.hearing.data.SessionRepository
import com.echo.hearing.device.DeviceCapabilityManager
import com.echo.hearing.domain.model.*
import com.echo.hearing.domain.quality.TrialQualityController
import com.echo.hearing.domain.statemachine.SessionEvent
import com.echo.hearing.domain.statemachine.SessionState
import com.echo.hearing.domain.statemachine.SessionStateMachine
import com.echo.hearing.domain.threshold.*
import com.echo.hearing.noise.NoiseMonitor
import com.echo.hearing.noise.NoiseReading
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * UI State for the Hearing Screening workflow.
 */
data class HearingScreeningUiState(
    val sessionState: SessionState = SessionState.NOT_STARTED,
    val sessionId: String = UUID.randomUUID().toString(),
    val startedAt: Long = System.currentTimeMillis(),
    val strategyType: StrategyType = StrategyType.MODIFIED_HUGHSON_WESTLAKE,
    val hasUserConsented: Boolean = false,
    val consentAgreedAt: Long? = null,
    val cancelReason: String? = null,
    val audioRoute: AudioRouteInfo? = null,
    val isHeadphoneConnected: Boolean = false,
    val calibrationInfo: CalibrationInfo? = null,
    val noiseReading: NoiseReading = NoiseReading(-100.0, NoiseAssessment.UNAVAILABLE, false, 0),
    val currentEar: Ear = Ear.LEFT,
    val currentFrequencyHz: Int = AudiometricFrequencies.FREQ_1000_HZ,
    val currentLevelDb: Int = 40,
    val trialNumber: Int = 0,
    val isTonePlaying: Boolean = false,
    val isWaitingForResponse: Boolean = false,
    val isNoisePaused: Boolean = false,
    val pauseReason: String? = null,
    val recoveryCountdownSeconds: Int = 3,
    val thresholdResults: List<ThresholdResult> = emptyList(),
    val trials: List<TrialRecord> = emptyList(),
    val qualityFlags: Set<QualityFlag> = setOf(QualityFlag.UNCALIBRATED_HARDWARE),
    val noisePauseCount: Int = 0,
    val devicePauseCount: Int = 0,
    val isSimulationMode: Boolean = false,
    val lastResponseLatencyMs: Long? = null,
    val totalTargets: Int = 8, // 2 ears * 4 frequencies
    val completedTargets: Int = 0,
    // Practice round state
    val practiceTonePlaying: Boolean = false,
    val practiceHeard: Boolean? = null,
    val practiceLatencyMs: Long? = null,
    val practiceFeedbackMessage: String? = null,
    // Final outcome
    val screeningOutcome: SessionScreeningOutcome? = null,
    // Ear transition interstitial ("Left Ear Screening Complete")
    val earTransitionPending: Boolean = false,
    // Frequency set toggle (4 default vs 6 full screening frequencies)
    val useSixFrequencies: Boolean = false,
    // Persisted screening history from LocalJsonSessionRepository
    val savedSessions: List<HearingSessionRecord> = emptyList()
)

/**
 * Senior orchestration ViewModel managing state transitions, audio stimuli,
 * environmental disturbance gates, configurable threshold strategies, and audit persistence.
 */
class HearingScreeningViewModel(
    val stimulusEngine: StimulusEngine,
    val noiseMonitor: NoiseMonitor,
    val deviceManager: DeviceCapabilityManager,
    val sessionRepository: SessionRepository,
    val protocolConfig: ProtocolConfig = ProtocolConfig(),
    val binarySearchConfig: BinarySearchConfig = BinarySearchConfig(),
    initialStrategyType: StrategyType = StrategyType.MODIFIED_HUGHSON_WESTLAKE
) : ViewModel() {

    private val stateMachine = SessionStateMachine()
    private val qualityController = TrialQualityController()

    private var currentStrategyType: StrategyType = initialStrategyType
    private var activeFrequencies: List<Int> = protocolConfig.frequencies
    private var pauseOnEarTransition: Boolean = false
    private var thresholdStrategy: ThresholdEstimationStrategy = createStrategy(initialStrategyType)

    private val _uiState = MutableStateFlow(
        HearingScreeningUiState(
            strategyType = initialStrategyType,
            currentEar = thresholdStrategy.currentEar,
            currentFrequencyHz = thresholdStrategy.currentFrequencyHz,
            currentLevelDb = thresholdStrategy.currentLevelDb,
            totalTargets = protocolConfig.ears.size * protocolConfig.frequencies.size
        )
    )
    val uiState: StateFlow<HearingScreeningUiState> = _uiState.asStateFlow()

    private var presentationJob: Job? = null
    private var responseTimeoutJob: Job? = null
    private var practiceTimeoutJob: Job? = null
    private var recoveryJob: Job? = null
    private var toneStartTimeMs: Long = 0L

    init {
        // Transition to ONBOARDING_CONSENT immediately so the consent screen
        // displays and ConsentAgreed is a legal event.
        try {
            stateMachine.transition(SessionEvent.StartOnboarding)
        } catch (e: Exception) {
            // Already in ONBOARDING_CONSENT or later — safe to continue
        }
        _uiState.update { it.copy(sessionState = stateMachine.currentState) }

        // Monitor continuous ambient noise
        viewModelScope.launch {
            noiseMonitor.readingFlow.collect { reading ->
                _uiState.update { it.copy(noiseReading = reading) }

                // Automatic Disturbance Handling:
                // If noise becomes SUSPECT or INVALID during active stimulus or waiting window
                if ((_uiState.value.sessionState == SessionState.STIMULUS_PRESENTATION ||
                            _uiState.value.sessionState == SessionState.WAITING_FOR_RESPONSE) &&
                    reading.assessment != NoiseAssessment.VALID
                ) {
                    handleNoiseDisturbance(reading)
                }

                // If noise becomes SUSPECT or INVALID during recovery recheck, cancel recovery
                if (_uiState.value.sessionState == SessionState.RECOVERY_RECHECK &&
                    reading.assessment != NoiseAssessment.VALID
                ) {
                    recoveryJob?.cancel()
                    recoveryJob = null
                    try {
                        stateMachine.transition(SessionEvent.NoiseDisturbanceDetected(overlapsStimulus = false))
                    } catch (ignored: Exception) {}
                    _uiState.update {
                        it.copy(
                            sessionState = SessionState.AUTOMATIC_PAUSE_NOISE,
                            isNoisePaused = true,
                            pauseReason = "Noise spiked during recovery. Pausing test."
                        )
                    }
                }

                // If paused due to noise, track recovery
                if (_uiState.value.sessionState == SessionState.AUTOMATIC_PAUSE_NOISE) {
                    val remaining = (3 - reading.consecutiveQuietSeconds).coerceAtLeast(0)
                    _uiState.update { it.copy(recoveryCountdownSeconds = remaining) }
                    if (noiseMonitor.checkRecovery(3) && recoveryJob == null) {
                        onNoiseRecoveryPassed()
                    }
                }
            }
        }

        // Initial audio route check & persisted sessions
        refreshDeviceRoute()
        refreshSavedSessions()
    }

    private fun createStrategy(type: StrategyType): ThresholdEstimationStrategy {
        return when (type) {
            StrategyType.MODIFIED_HUGHSON_WESTLAKE -> ModifiedHughsonWestlakeEngine(
                protocolConfig.copy(frequencies = activeFrequencies)
            )
            StrategyType.BINARY_SEARCH_REFINEMENT -> BinarySearchStrategy(
                binarySearchConfig.copy(frequencies = activeFrequencies)
            )
        }
    }

    fun setPauseOnEarTransition(enabled: Boolean) {
        pauseOnEarTransition = enabled
    }

    fun setUseSixFrequencies(enabled: Boolean) {
        if (_uiState.value.sessionState == SessionState.NOT_STARTED ||
            _uiState.value.sessionState == SessionState.TEST_PREP ||
            _uiState.value.sessionState == SessionState.ONBOARDING_CONSENT ||
            _uiState.value.sessionState == SessionState.DEVICE_READINESS ||
            _uiState.value.sessionState == SessionState.ENVIRONMENTAL_NOISE_CHECK
        ) {
            activeFrequencies = if (enabled) {
                listOf(
                    AudiometricFrequencies.FREQ_250_HZ,
                    AudiometricFrequencies.FREQ_500_HZ,
                    AudiometricFrequencies.FREQ_1000_HZ,
                    AudiometricFrequencies.FREQ_2000_HZ,
                    AudiometricFrequencies.FREQ_4000_HZ,
                    AudiometricFrequencies.FREQ_8000_HZ
                )
            } else {
                protocolConfig.frequencies
            }
            thresholdStrategy = createStrategy(currentStrategyType)
            _uiState.update {
                it.copy(
                    useSixFrequencies = enabled,
                    currentEar = thresholdStrategy.currentEar,
                    currentFrequencyHz = thresholdStrategy.currentFrequencyHz,
                    currentLevelDb = thresholdStrategy.currentLevelDb,
                    totalTargets = protocolConfig.ears.size * activeFrequencies.size
                )
            }
        }
    }

    fun refreshSavedSessions() {
        val list = runCatching { sessionRepository.listSessions() }.getOrDefault(emptyList())
        _uiState.update { it.copy(savedSessions = list) }
    }

    fun deleteSession(sessionId: String) {
        runCatching { sessionRepository.deleteSession(sessionId) }
        refreshSavedSessions()
    }

    fun continueToRightEar() {
        if (!_uiState.value.earTransitionPending) return
        _uiState.update { it.copy(earTransitionPending = false) }
        viewModelScope.launch {
            try {
                stateMachine.transition(SessionEvent.NextTrialNeeded)
                _uiState.update { it.copy(sessionState = stateMachine.currentState) }
                startStimulusPresentation()
            } catch (ignored: Exception) {}
        }
    }

    fun selectStrategy(type: StrategyType) {
        if (_uiState.value.sessionState == SessionState.NOT_STARTED ||
            _uiState.value.sessionState == SessionState.TEST_PREP ||
            _uiState.value.sessionState == SessionState.ONBOARDING_CONSENT ||
            _uiState.value.sessionState == SessionState.DEVICE_READINESS ||
            _uiState.value.sessionState == SessionState.ENVIRONMENTAL_NOISE_CHECK
        ) {
            currentStrategyType = type
            thresholdStrategy = createStrategy(type)
            val flags = if (type == StrategyType.BINARY_SEARCH_REFINEMENT) {
                _uiState.value.qualityFlags + QualityFlag.BINARY_SEARCH_EXPERIMENTAL
            } else {
                _uiState.value.qualityFlags - QualityFlag.BINARY_SEARCH_EXPERIMENTAL
            }
            _uiState.update {
                it.copy(
                    strategyType = type,
                    currentEar = thresholdStrategy.currentEar,
                    currentFrequencyHz = thresholdStrategy.currentFrequencyHz,
                    currentLevelDb = thresholdStrategy.currentLevelDb,
                    qualityFlags = flags
                )
            }
        }
    }

    fun refreshDeviceRoute() {
        val route = deviceManager.getCurrentAudioRoute()
        val isHeadphone = deviceManager.isHeadphoneConnected()
        val calibration = deviceManager.getCalibrationStatus(route.routeType)

        _uiState.update {
            it.copy(
                audioRoute = route,
                isHeadphoneConnected = isHeadphone,
                calibrationInfo = calibration
            )
        }
    }

    fun onStartOnboarding() {
        try {
            stateMachine.transition(SessionEvent.StartOnboarding)
        } catch (e: IllegalStateException) {
            // Already past NOT_STARTED — safe to ignore
        }
        _uiState.update { it.copy(sessionState = stateMachine.currentState) }
    }

    fun onConsentAgreed(agreed: Boolean) {
        // Ensure we are in ONBOARDING_CONSENT before attempting ConsentAgreed.
        // If the state machine is still in NOT_STARTED (e.g. init didn't run yet),
        // transition through StartOnboarding first.
        if (stateMachine.currentState == SessionState.NOT_STARTED) {
            try {
                stateMachine.transition(SessionEvent.StartOnboarding)
            } catch (e: IllegalStateException) {
                // Already transitioned — continue
            }
        }

        try {
            stateMachine.transition(SessionEvent.ConsentAgreed(agreed))
            _uiState.update {
                it.copy(
                    sessionState = stateMachine.currentState,
                    hasUserConsented = agreed,
                    consentAgreedAt = if (agreed) System.currentTimeMillis() else null
                )
            }
        } catch (e: IllegalStateException) {
            // Transition was illegal (e.g. already past consent). Log and update UI state.
            _uiState.update { it.copy(sessionState = stateMachine.currentState) }
            return
        }

        if (agreed) {
            refreshDeviceRoute()
            if (noiseMonitor.isSensorAvailable()) {
                noiseMonitor.startMonitoring()
            }
        }
    }

    /**
     * Called after the Android runtime permission result for RECORD_AUDIO is received.
     * Separated from consent logic so that a permission denial does not crash the app.
     */
    fun onMicrophonePermissionResult(granted: Boolean) {
        if (granted) {
            refreshDeviceRoute()
            noiseMonitor.startMonitoring()
        } else {
            // Permission denied — noise monitor will report UNAVAILABLE.
            // Update the UI state so the user sees the correct noise status.
            _uiState.update {
                it.copy(
                    noiseReading = NoiseReading(
                        levelDbFs = -100.0,
                        assessment = NoiseAssessment.UNAVAILABLE,
                        isDisturbance = false,
                        consecutiveQuietSeconds = 0
                    )
                )
            }
        }
    }

    fun onDevicePrecheckContinue() {
        refreshDeviceRoute()
        val route = _uiState.value.audioRoute ?: deviceManager.getCurrentAudioRoute()
        val isSupported = route.routeType.isHeadphone

        if (!isSupported) {
            _uiState.update {
                it.copy(
                    pauseReason = "Headphones required. Built-in speaker cannot isolate left and right ears."
                )
            }
            return
        }

        val currentNoise = _uiState.value.noiseReading
        if (currentNoise.assessment == NoiseAssessment.UNAVAILABLE) {
            _uiState.update {
                it.copy(
                    pauseReason = "Microphone sensor unavailable or permission denied. Please grant microphone permission to monitor ambient noise."
                )
            }
            return
        }

        if (currentNoise.assessment == NoiseAssessment.INVALID) {
            _uiState.update {
                it.copy(
                    pauseReason = "Environment is too loud (${String.format("%.1f", currentNoise.levelDbFs)} dBFS). Please move to a quieter location."
                )
            }
            return
        }

        try {
            stateMachine.transition(SessionEvent.DeviceEvaluated(route, isSupported))
            _uiState.update { it.copy(sessionState = stateMachine.currentState) }

            val calibration = route.calibrationInfo
            stateMachine.transition(SessionEvent.CalibrationEvaluated(calibration))
            _uiState.update { it.copy(sessionState = stateMachine.currentState) }

            stateMachine.transition(SessionEvent.NoiseBaselineChecked(currentNoise.assessment))
            _uiState.update { it.copy(sessionState = stateMachine.currentState, pauseReason = null) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // --- Practice Round Flow ---

    fun onStartPractice() {
        if (stateMachine.currentState == SessionState.TEST_PREP ||
            stateMachine.currentState == SessionState.PRACTICE_FEEDBACK
        ) {
            practiceTimeoutJob?.cancel()
            stimulusEngine.stopTone()

            try {
                stateMachine.transition(SessionEvent.StartPractice)
            } catch (ignored: Exception) {}

            _uiState.update {
                it.copy(
                    sessionState = stateMachine.currentState,
                    practiceTonePlaying = true,
                    practiceHeard = null,
                    practiceLatencyMs = null,
                    practiceFeedbackMessage = "Playing sample 1000 Hz demo tone. Tap 'I HEAR IT' or 'I CAN'T HEAR IT'."
                )
            }

            toneStartTimeMs = System.currentTimeMillis()
            stimulusEngine.playTone(
                frequencyHz = AudiometricFrequencies.FREQ_1000_HZ,
                levelDb = 50, // Clearly audible demonstration level
                ear = Ear.LEFT,
                durationMs = 1500L,
                onToneStarted = { _uiState.update { it.copy(practiceTonePlaying = true) } },
                onToneFinished = { _uiState.update { it.copy(practiceTonePlaying = false) } }
            )

            practiceTimeoutJob = viewModelScope.launch {
                delay(3500L)
                if (_uiState.value.sessionState == SessionState.PRACTICE_PRESENTATION) {
                    onPracticeTimedOut()
                }
            }
        }
    }

    fun onPracticeHeardClicked() {
        if (_uiState.value.sessionState != SessionState.PRACTICE_PRESENTATION) return
        val latencyMs = System.currentTimeMillis() - toneStartTimeMs
        practiceTimeoutJob?.cancel()
        stimulusEngine.stopTone()

        try {
            stateMachine.transition(SessionEvent.PracticeResponseReceived(heard = true, latencyMs = latencyMs))
        } catch (ignored: Exception) {}

        _uiState.update {
            it.copy(
                sessionState = stateMachine.currentState,
                practiceTonePlaying = false,
                practiceHeard = true,
                practiceLatencyMs = latencyMs,
                practiceFeedbackMessage = "Great! Demo tone heard (${latencyMs}ms). You can try again or proceed to formal screening."
            )
        }
    }

    fun onPracticeNotHeardClicked() {
        if (_uiState.value.sessionState != SessionState.PRACTICE_PRESENTATION) return
        val latencyMs = System.currentTimeMillis() - toneStartTimeMs
        practiceTimeoutJob?.cancel()
        stimulusEngine.stopTone()

        try {
            stateMachine.transition(SessionEvent.PracticeResponseReceived(heard = false, latencyMs = latencyMs))
        } catch (ignored: Exception) {}

        _uiState.update {
            it.copy(
                sessionState = stateMachine.currentState,
                practiceTonePlaying = false,
                practiceHeard = false,
                practiceLatencyMs = latencyMs,
                practiceFeedbackMessage = "Demo tone reported not heard. Please increase headphone volume or reposition headphones and tap 'Try Again'."
            )
        }
    }

    internal fun onPracticeTimedOut() {
        stimulusEngine.stopTone()
        try {
            stateMachine.transition(SessionEvent.PracticeResponseReceived(heard = false, latencyMs = 3500L))
        } catch (ignored: Exception) {}

        _uiState.update {
            it.copy(
                sessionState = stateMachine.currentState,
                practiceTonePlaying = false,
                practiceHeard = false,
                practiceLatencyMs = null,
                practiceFeedbackMessage = "Practice tone ended without response. Please adjust headphone volume and tap 'Try Again'."
            )
        }
    }

    fun onFinishPractice() {
        practiceTimeoutJob?.cancel()
        stimulusEngine.stopTone()
        try {
            stateMachine.transition(SessionEvent.FinishPractice)
        } catch (ignored: Exception) {}
        _uiState.update { it.copy(sessionState = stateMachine.currentState) }
    }

    // --- Formal Screening Flow ---

    fun onStartScreening() {
        if (stateMachine.currentState == SessionState.TEST_PREP ||
            stateMachine.currentState == SessionState.PRACTICE_FEEDBACK ||
            stateMachine.currentState == SessionState.ENVIRONMENTAL_NOISE_CHECK
        ) {
            try {
                stateMachine.transition(SessionEvent.StartTest)
            } catch (ignored: Exception) {}

            _uiState.update {
                it.copy(
                    sessionState = stateMachine.currentState,
                    currentEar = thresholdStrategy.currentEar,
                    currentFrequencyHz = thresholdStrategy.currentFrequencyHz,
                    currentLevelDb = thresholdStrategy.currentLevelDb
                )
            }
            startStimulusPresentation()
        }
    }

    private fun startStimulusPresentation() {
        if (_uiState.value.sessionState != SessionState.STIMULUS_PRESENTATION) return

        presentationJob?.cancel()
        responseTimeoutJob?.cancel()

        presentationJob = viewModelScope.launch {
            // Short pre-stimulus jitter delay (500ms - 1200ms) to prevent anticipatory guessing
            val jitterMs = (500L..1200L).random()
            delay(jitterMs)

            if (stateMachine.currentState != SessionState.STIMULUS_PRESENTATION) return@launch

            val ear = thresholdStrategy.currentEar
            val freq = thresholdStrategy.currentFrequencyHz
            val level = thresholdStrategy.currentLevelDb

            toneStartTimeMs = System.currentTimeMillis()
            _uiState.update {
                it.copy(
                    isTonePlaying = true,
                    isWaitingForResponse = true,
                    currentEar = ear,
                    currentFrequencyHz = freq,
                    currentLevelDb = level
                )
            }

            stimulusEngine.playTone(
                frequencyHz = freq,
                levelDb = level,
                ear = ear,
                durationMs = 1200L,
                onToneStarted = {
                    _uiState.update { it.copy(isTonePlaying = true) }
                },
                onToneFinished = {
                    _uiState.update { it.copy(isTonePlaying = false) }
                    if (stateMachine.currentState == SessionState.STIMULUS_PRESENTATION) {
                        try {
                            stateMachine.transition(SessionEvent.StimulusEnded)
                            _uiState.update { it.copy(sessionState = stateMachine.currentState) }
                        } catch (e: Exception) {}
                    }
                }
            )

            // Response window: stimulus duration (1200ms) + 1800ms grace window = 3000ms
            responseTimeoutJob = launch {
                delay(3000L)
                if (_uiState.value.isWaitingForResponse) {
                    handleUserResponse(heard = false, latencyMs = null)
                }
            }
        }
    }

    fun onUserHeardClicked() {
        if (!_uiState.value.isWaitingForResponse) return
        val latencyMs = System.currentTimeMillis() - toneStartTimeMs
        handleUserResponse(heard = true, latencyMs = latencyMs, explicitNotHeard = false)
    }

    fun onUserNotHeardClicked() {
        if (!_uiState.value.isWaitingForResponse) return
        val latencyMs = System.currentTimeMillis() - toneStartTimeMs
        handleUserResponse(heard = false, latencyMs = latencyMs, explicitNotHeard = true)
    }

    private fun handleUserResponse(heard: Boolean, latencyMs: Long?, explicitNotHeard: Boolean = false) {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        stimulusEngine.stopTone()

        _uiState.update {
            it.copy(
                isTonePlaying = false,
                isWaitingForResponse = false,
                lastResponseLatencyMs = latencyMs
            )
        }

        try {
            if (heard) {
                stateMachine.transition(SessionEvent.UserRespondedHeard(latencyMs ?: 0L))
            } else if (explicitNotHeard) {
                stateMachine.transition(SessionEvent.UserRespondedNotHeard(latencyMs ?: 0L))
            } else {
                stateMachine.transition(SessionEvent.ResponseTimedOut)
            }
            _uiState.update { it.copy(sessionState = stateMachine.currentState) }
        } catch (ignored: Exception) {}

        // Quality check via TrialQualityController
        val qualityEval = qualityController.evaluateTrialQuality(
            userTappedHeard = heard,
            latencyMs = latencyMs,
            noiseAssessment = _uiState.value.noiseReading.assessment,
            isNoiseDisturbedDuringTrial = _uiState.value.isNoisePaused,
            routeInfo = _uiState.value.audioRoute,
            explicitNotHeard = explicitNotHeard
        )

        val stepResult = thresholdStrategy.evaluateTrial(
            outcome = qualityEval.outcome,
            latencyMs = qualityEval.latencyMs,
            ambientNoiseDbFs = _uiState.value.noiseReading.levelDbFs
        )

        processStrategyResult(stepResult)
    }

    private fun processStrategyResult(result: StrategyResult) {
        when (result) {
            is StrategyResult.NextTrial -> {
                _uiState.update {
                    it.copy(
                        currentEar = result.ear,
                        currentFrequencyHz = result.frequencyHz,
                        currentLevelDb = result.nextLevelDb,
                        trials = thresholdStrategy.allTrials,
                        trialNumber = thresholdStrategy.allTrials.size
                    )
                }
                viewModelScope.launch {
                    delay(400L) // Brief inter-stimulus interval
                    try {
                        stateMachine.transition(SessionEvent.NextTrialNeeded)
                        _uiState.update { it.copy(sessionState = stateMachine.currentState) }
                        startStimulusPresentation()
                    } catch (e: Exception) {}
                }
            }

            is StrategyResult.ThresholdFound -> {
                val previousEar = _uiState.value.currentEar
                _uiState.update {
                    it.copy(
                        thresholdResults = thresholdStrategy.thresholdResults,
                        trials = thresholdStrategy.allTrials,
                        completedTargets = thresholdStrategy.thresholdResults.size
                    )
                }
                if (result.nextTarget != null) {
                    scheduleNextTarget(previousEar, result.nextTarget)
                } else {
                    finishScreening()
                }
            }

            is StrategyResult.MaxTrialsExceeded -> {
                val previousEar = _uiState.value.currentEar
                if (result.nextTarget != null) {
                    _uiState.update { it.copy(trials = thresholdStrategy.allTrials) }
                    scheduleNextTarget(previousEar, result.nextTarget)
                } else {
                    finishScreening()
                }
            }

            is StrategyResult.Inconclusive -> {
                val previousEar = _uiState.value.currentEar
                if (result.nextTarget != null) {
                    _uiState.update {
                        it.copy(
                            trials = thresholdStrategy.allTrials,
                            qualityFlags = it.qualityFlags + QualityFlag.INCOMPLETE_TARGETS
                        )
                    }
                    scheduleNextTarget(previousEar, result.nextTarget)
                } else {
                    finishScreening()
                }
            }

            is StrategyResult.AllTargetsCompleted -> {
                finishScreening()
            }
        }
    }

    private fun scheduleNextTarget(previousEar: Ear, nextTarget: TargetPair) {
        val switchingToRightEar = pauseOnEarTransition && previousEar == Ear.LEFT && nextTarget.ear == Ear.RIGHT
        _uiState.update {
            it.copy(
                currentEar = nextTarget.ear,
                currentFrequencyHz = nextTarget.frequencyHz,
                currentLevelDb = thresholdStrategy.currentLevelDb,
                earTransitionPending = switchingToRightEar
            )
        }
        if (switchingToRightEar) return
        viewModelScope.launch {
            delay(600L)
            try {
                stateMachine.transition(SessionEvent.NextTrialNeeded)
                _uiState.update { it.copy(sessionState = stateMachine.currentState) }
                startStimulusPresentation()
            } catch (e: Exception) {}
        }
    }

    private fun handleNoiseDisturbance(reading: NoiseReading) {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        stimulusEngine.stopTone()

        // Contaminate overlapping trial
        thresholdStrategy.evaluateTrial(
            outcome = TrialOutcome.CONTAMINATED_BY_NOISE,
            ambientNoiseDbFs = reading.levelDbFs
        )

        try {
            stateMachine.transition(SessionEvent.NoiseDisturbanceDetected(overlapsStimulus = true))
        } catch (ignored: Exception) {}

        _uiState.update {
            it.copy(
                sessionState = SessionState.AUTOMATIC_PAUSE_NOISE,
                isTonePlaying = false,
                isWaitingForResponse = false,
                isNoisePaused = true,
                pauseReason = "Environmental noise detected (${String.format("%.1f", reading.levelDbFs)} dBFS). Pausing test.",
                noisePauseCount = it.noisePauseCount + 1,
                qualityFlags = it.qualityFlags + QualityFlag.ENVIRONMENTAL_NOISE_PAUSES_DETECTED,
                trials = thresholdStrategy.allTrials
            )
        }
    }

    private fun onNoiseRecoveryPassed() {
        if (recoveryJob != null) return // Idempotent guard against multiple triggers
        try {
            stateMachine.transition(SessionEvent.NoiseRecovered(isStable = true))
            _uiState.update {
                it.copy(
                    sessionState = SessionState.RECOVERY_RECHECK,
                    isNoisePaused = false,
                    pauseReason = null
                )
            }
        } catch (ignored: Exception) {}

        recoveryJob = viewModelScope.launch {
            delay(1000L)
            // Re-verify that noise has remained VALID during the 1-second settling window
            if (_uiState.value.noiseReading.assessment == NoiseAssessment.VALID &&
                _uiState.value.sessionState == SessionState.RECOVERY_RECHECK
            ) {
                try {
                    stateMachine.transition(SessionEvent.StartTest)
                    _uiState.update { it.copy(sessionState = stateMachine.currentState) }
                    startStimulusPresentation()
                } catch (ignored: Exception) {}
            } else {
                // Noise spiked again during recheck window
                handleNoiseDisturbance(_uiState.value.noiseReading)
            }
            recoveryJob = null
        }
    }

    fun onPauseRequested() {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        practiceTimeoutJob?.cancel()
        recoveryJob?.cancel()
        recoveryJob = null
        stimulusEngine.stopTone()

        _uiState.update {
            it.copy(
                isTonePlaying = false,
                isWaitingForResponse = false,
                isNoisePaused = true,
                pauseReason = "Testing paused by user."
            )
        }
    }

    fun onResumeRequested() {
        _uiState.update {
            it.copy(isNoisePaused = false, pauseReason = null)
        }
        startStimulusPresentation()
    }

    fun onCancelRequested() {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        practiceTimeoutJob?.cancel()
        recoveryJob?.cancel()
        recoveryJob = null
        stimulusEngine.stopTone()
        noiseMonitor.stopMonitoring()

        try {
            stateMachine.transition(SessionEvent.CancelRequested)
        } catch (ignored: Exception) {}

        _uiState.update {
            it.copy(
                sessionState = SessionState.CANCELLED,
                isTonePlaying = false,
                isWaitingForResponse = false,
                isNoisePaused = false,
                cancelReason = "Screening was cancelled by the user."
            )
        }
        saveSessionToDisk()
    }

    /**
     * Tapping "Try Again" after a cancellation or incomplete precheck.
     * If user has already granted consent during this session, returns directly to setup
     * without forcing them to read and accept consent terms again.
     */
    fun onTryAgain() {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        practiceTimeoutJob?.cancel()
        recoveryJob?.cancel()
        recoveryJob = null
        stimulusEngine.stopTone()

        thresholdStrategy.reset()

        if (_uiState.value.hasUserConsented) {
            try {
                stateMachine.transition(SessionEvent.RetrySession)
            } catch (e: Exception) {}
            if (noiseMonitor.isSensorAvailable()) {
                noiseMonitor.startMonitoring()
            }
            refreshDeviceRoute()

            _uiState.update {
                HearingScreeningUiState(
                    sessionState = SessionState.DEVICE_READINESS,
                    hasUserConsented = true,
                    consentAgreedAt = it.consentAgreedAt,
                    strategyType = currentStrategyType,
                    currentEar = thresholdStrategy.currentEar,
                    currentFrequencyHz = thresholdStrategy.currentFrequencyHz,
                    currentLevelDb = thresholdStrategy.currentLevelDb,
                    totalTargets = protocolConfig.ears.size * activeFrequencies.size,
                    useSixFrequencies = it.useSixFrequencies,
                    savedSessions = it.savedSessions,
                    audioRoute = it.audioRoute,
                    isHeadphoneConnected = it.isHeadphoneConnected,
                    calibrationInfo = it.calibrationInfo,
                    isSimulationMode = it.isSimulationMode
                )
            }
        } else {
            onRestartRequested()
        }
    }

    fun onRestartRequested() {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        practiceTimeoutJob?.cancel()
        recoveryJob?.cancel()
        recoveryJob = null
        stimulusEngine.stopTone()

        stateMachine.transition(SessionEvent.RestartRequested)
        try {
            stateMachine.transition(SessionEvent.StartOnboarding)
        } catch (e: IllegalStateException) {}

        thresholdStrategy.reset()

        _uiState.update {
            HearingScreeningUiState(
                sessionState = stateMachine.currentState,
                strategyType = currentStrategyType,
                hasUserConsented = false,
                currentEar = thresholdStrategy.currentEar,
                currentFrequencyHz = thresholdStrategy.currentFrequencyHz,
                currentLevelDb = thresholdStrategy.currentLevelDb,
                totalTargets = protocolConfig.ears.size * activeFrequencies.size,
                useSixFrequencies = it.useSixFrequencies,
                savedSessions = it.savedSessions,
                isSimulationMode = it.isSimulationMode
            )
        }
    }

    private fun finishScreening() {
        presentationJob?.cancel()
        responseTimeoutJob?.cancel()
        stimulusEngine.stopTone()
        noiseMonitor.stopMonitoring()

        try {
            stateMachine.transition(SessionEvent.AllTargetsCompleted)
        } catch (ignored: Exception) {}

        val outcome = computeScreeningOutcome()

        _uiState.update {
            it.copy(
                sessionState = SessionState.RESULTS,
                isTonePlaying = false,
                isWaitingForResponse = false,
                thresholdResults = thresholdStrategy.thresholdResults,
                completedTargets = thresholdStrategy.thresholdResults.size,
                screeningOutcome = outcome
            )
        }

        saveSessionToDisk()
    }

    /**
     * Synthesizes separate left-ear and right-ear threshold results into
     * clinically responsible preliminary screening outcome classifications.
     */
    fun computeScreeningOutcome(): SessionScreeningOutcome {
        val leftThresholds = thresholdStrategy.thresholdResults.filter { it.ear == Ear.LEFT }
        val rightThresholds = thresholdStrategy.thresholdResults.filter { it.ear == Ear.RIGHT }
        val targetFreqCount = activeFrequencies.size

        val leftSummary = evaluateEarScreening(Ear.LEFT, leftThresholds, targetFreqCount)
        val rightSummary = evaluateEarScreening(Ear.RIGHT, rightThresholds, targetFreqCount)

        val overallClassification = when {
            leftSummary.classification == ScreeningOutcomeClassification.REFER ||
                    rightSummary.classification == ScreeningOutcomeClassification.REFER -> ScreeningOutcomeClassification.REFER
            leftSummary.classification == ScreeningOutcomeClassification.INCONCLUSIVE ||
                    rightSummary.classification == ScreeningOutcomeClassification.INCONCLUSIVE -> ScreeningOutcomeClassification.INCONCLUSIVE
            else -> ScreeningOutcomeClassification.PASS
        }

        val totalTrials = thresholdStrategy.allTrials.size
        val contaminated = thresholdStrategy.allTrials.count {
            it.outcome == TrialOutcome.CONTAMINATED_BY_NOISE || it.outcome == TrialOutcome.INVALID_INTERRUPTED
        }

        val advisoryNotes = listOf(
            "Values represent uncalibrated digital attenuation (dBFS) on consumer hardware.",
            "This is a preliminary screening protocol, not a diagnostic clinical audiogram.",
            "If hearing difficulties are experienced, a formal clinical audiometry evaluation with an audiologist is recommended."
        )

        return SessionScreeningOutcome(
            overallClassification = overallClassification,
            leftEarSummary = leftSummary,
            rightEarSummary = rightSummary,
            totalTrials = totalTrials,
            contaminatedTrials = contaminated,
            isCalibrated = false,
            advisoryNotes = advisoryNotes
        )
    }

    private fun evaluateEarScreening(
        ear: Ear,
        thresholds: List<ThresholdResult>,
        targetCount: Int
    ): EarScreeningSummary {
        val isComplete = thresholds.size >= targetCount
        val avgDb = if (thresholds.isNotEmpty()) thresholds.map { it.thresholdDb }.average() else null

        // Screening pass cutoff: provisional 25 dBFS baseline
        val screeningBaselineDb = 25
        val hasElevated = thresholds.any { it.thresholdDb > screeningBaselineDb }

        val classification = when {
            !isComplete -> ScreeningOutcomeClassification.INCONCLUSIVE
            hasElevated -> ScreeningOutcomeClassification.REFER
            else -> ScreeningOutcomeClassification.PASS
        }

        val notes = when (classification) {
            ScreeningOutcomeClassification.PASS -> "All tested thresholds at or below ${screeningBaselineDb} dBFS provisional screening level."
            ScreeningOutcomeClassification.REFER -> "Thresholds above ${screeningBaselineDb} dBFS detected. Professional hearing assessment recommended."
            ScreeningOutcomeClassification.INCONCLUSIVE -> "Incomplete target coverage (${thresholds.size}/$targetCount completed)."
        }

        return EarScreeningSummary(
            ear = ear,
            classification = classification,
            thresholds = thresholds,
            averageLevelDb = avgDb,
            isComplete = isComplete,
            summaryNotes = notes
        )
    }

    private fun saveSessionToDisk() {
        val current = _uiState.value
        val route = current.audioRoute ?: deviceManager.getCurrentAudioRoute()

        val record = HearingSessionRecord(
            sessionId = current.sessionId,
            startedAt = current.startedAt,
            completedAt = System.currentTimeMillis(),
            strategyType = currentStrategyType.name,
            deviceModel = route.calibrationInfo.deviceModel,
            androidVersion = android.os.Build.VERSION.SDK_INT,
            audioRoute = route,
            isCompleted = current.sessionState == SessionState.RESULTS,
            qualityFlags = current.qualityFlags,
            trials = thresholdStrategy.allTrials,
            thresholdResults = thresholdStrategy.thresholdResults,
            noisePauseCount = current.noisePauseCount,
            devicePauseCount = current.devicePauseCount,
            screeningOutcome = current.screeningOutcome
        )

        sessionRepository.saveSession(record)
        refreshSavedSessions()
    }

    // --- Developer Simulation Panel Controls ---

    fun toggleSimulationMode() {
        _uiState.update {
            val next = !it.isSimulationMode
            it.copy(
                isSimulationMode = next,
                qualityFlags = if (next) it.qualityFlags + QualityFlag.SIMULATION_ONLY else it.qualityFlags
            )
        }
    }

    fun simulateNoiseSpike(assessment: NoiseAssessment) {
        val levelDbFs = when (assessment) {
            NoiseAssessment.VALID -> -55.0
            NoiseAssessment.SUSPECT -> -38.0
            NoiseAssessment.INVALID -> -25.0
            NoiseAssessment.UNAVAILABLE -> -100.0
        }
        val simulatedReading = NoiseReading(
            levelDbFs = levelDbFs,
            assessment = assessment,
            isDisturbance = assessment != NoiseAssessment.VALID,
            consecutiveQuietSeconds = if (assessment == NoiseAssessment.VALID) 5 else 0
        )

        if (noiseMonitor is com.echo.hearing.noise.FakeNoiseMonitor) {
            noiseMonitor.injectAssessment(assessment, levelDbFs)
        }

        _uiState.update { it.copy(noiseReading = simulatedReading) }

        // If actively testing and noise is injected, trigger disturbance
        if ((_uiState.value.sessionState == SessionState.STIMULUS_PRESENTATION ||
                    _uiState.value.sessionState == SessionState.WAITING_FOR_RESPONSE) &&
            assessment != NoiseAssessment.VALID
        ) {
            handleNoiseDisturbance(simulatedReading)
        } else if (_uiState.value.sessionState == SessionState.AUTOMATIC_PAUSE_NOISE &&
            assessment == NoiseAssessment.VALID
        ) {
            onNoiseRecoveryPassed()
        }
    }

    fun simulateDeviceDisconnect() {
        presentationJob?.cancel()
        stimulusEngine.stopTone()

        if (_uiState.value.sessionState == SessionState.DEVICE_READINESS ||
            _uiState.value.sessionState == SessionState.TEST_PREP
        ) {
            // On setup screen: simply simulate unplugging headphones without jumping to screening screen
            val speakerRoute = AudioRouteInfo(
                routeType = AudioRouteType.BUILTIN_SPEAKER,
                deviceName = "Internal Phone Speaker (Simulated)",
                isStereoCapable = false,
                sampleRateHz = 44100,
                calibrationInfo = CalibrationInfo(
                    deviceModel = "Simulated Device",
                    routeType = AudioRouteType.BUILTIN_SPEAKER,
                    provenance = CalibrationProvenance.UNCALIBRATED,
                    isOfficiallySupported = false,
                    notes = "Speaker output cannot provide acoustic isolation."
                )
            )
            _uiState.update {
                it.copy(
                    audioRoute = speakerRoute,
                    isHeadphoneConnected = false
                )
            }
        } else if (_uiState.value.sessionState == SessionState.STIMULUS_PRESENTATION ||
            _uiState.value.sessionState == SessionState.WAITING_FOR_RESPONSE ||
            _uiState.value.sessionState == SessionState.PRACTICE_PRESENTATION
        ) {
            // During active test: trigger automatic pause for device disconnect
            try {
                stateMachine.transition(SessionEvent.DeviceDisconnected)
            } catch (ignored: Exception) {}
            _uiState.update {
                it.copy(
                    sessionState = SessionState.AUTOMATIC_PAUSE_DEVICE,
                    isHeadphoneConnected = false,
                    isTonePlaying = false,
                    isWaitingForResponse = false,
                    pauseReason = "Audio device disconnected. Please reconnect headphones.",
                    devicePauseCount = it.devicePauseCount + 1,
                    qualityFlags = it.qualityFlags + QualityFlag.AUDIO_ROUTE_CHANGED_DURING_TEST
                )
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        stimulusEngine.stopTone()
        noiseMonitor.stopMonitoring()
    }
}
