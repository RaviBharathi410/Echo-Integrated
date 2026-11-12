package com.echo.hearing

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import com.echo.hearing.audio.AndroidAudioTrackStimulusEngine
import com.echo.hearing.audio.ToneEar
import com.echo.hearing.device.AndroidDeviceCapabilityManager
import com.echo.hearing.monitor.NativeAudioEngine
import com.echo.hearing.noise.AndroidMicrophoneNoiseMonitor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class AudioCoordinatorState {
    IDLE,
    SCREENING_NOISE_ONLY,
    SCREENING_TONE_ACTIVE,
    MONITOR_ACTIVE
}

/**
 * Single authoritative coordinator guaranteeing at most one active microphone consumer
 * and one active audio output consumer across screening tones, ambient noise analysis,
 * and the C++ Oboe full-duplex monitor.
 */
class AudioSessionCoordinator(
    private val context: Context,
    private val onEvent: (Map<String, Any?>) -> Unit
) {
    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    val deviceManager = AndroidDeviceCapabilityManager(context)
    private val stimulusEngine = AndroidAudioTrackStimulusEngine()
    private val noiseMonitor = AndroidMicrophoneNoiseMonitor(context)

    @Volatile
    private var state: AudioCoordinatorState = AudioCoordinatorState.IDLE

    private var activeMonitorInputId: Int? = null
    private var activeMonitorOutputId: Int? = null
    private var activeToneToken: String? = null
    private var toneSeq: Long = 0

    private var focusRequest: AudioFocusRequest? = null
    private var monitorPollJob: Job? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = handleDevicesChanged()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = handleDevicesChanged()
    }

    init {
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
    }

    fun dispose() {
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        releaseAllAudio("disposed")
        scope.cancel()
    }

    fun getMonitorDevicesMap(): Map<String, Any> {
        val inputs = deviceManager.getMonitorInputDevices()
        val outputs = deviceManager.getMonitorOutputDevices()
        val defaultInputId = inputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }?.id
            ?: inputs.firstOrNull()?.id
        val defaultOutputId = outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }?.id
            ?: outputs.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_USB_DEVICE
            }?.id
            ?: outputs.firstOrNull()?.id
        return mapOf(
            "inputs" to inputs.map { mapOf("id" to it.id, "label" to it.label, "type" to it.type) },
            "outputs" to outputs.map { mapOf("id" to it.id, "label" to it.label, "type" to it.type) },
            "defaultInputId" to (defaultInputId ?: -1),
            "defaultOutputId" to (defaultOutputId ?: -1)
        )
    }

    // ---- Noise monitor (Screening precheck & active disturbance guard) ----------------------

    fun startNoiseMonitor(): Boolean = synchronized(lock) {
        if (state == AudioCoordinatorState.MONITOR_ACTIVE) {
            stopMonitorLocked("switchedToScreening", "Live monitor stopped for hearing screening.")
        }
        val started = noiseMonitor.startMonitoring { reading ->
            emit(
                mapOf(
                    "type" to "noiseReading",
                    "levelDbFs" to reading.levelDbFs,
                    "assessment" to reading.assessment,
                    "isDisturbance" to reading.isDisturbance,
                    "consecutiveQuietSeconds" to reading.consecutiveQuietSeconds,
                    "timestampMs" to reading.timestampMs
                )
            )
        }
        state = if (stimulusEngine.isPlaying()) {
            AudioCoordinatorState.SCREENING_TONE_ACTIVE
        } else if (started) {
            AudioCoordinatorState.SCREENING_NOISE_ONLY
        } else {
            AudioCoordinatorState.IDLE
        }
        started
    }

    fun stopNoiseMonitor() = synchronized(lock) {
        noiseMonitor.stopMonitoring()
        state = if (stimulusEngine.isPlaying()) {
            AudioCoordinatorState.SCREENING_TONE_ACTIVE
        } else if (NativeAudioEngine.nativeIsRunning()) {
            AudioCoordinatorState.MONITOR_ACTIVE
        } else {
            AudioCoordinatorState.IDLE
        }
    }

    fun isNoiseSensorAvailable(): Boolean = noiseMonitor.isSensorAvailable()

    // ---- Screening pure-tone playback (AudioTrack + AudioFocusRequest) -----------------------

    fun playTone(
        frequencyHz: Int,
        levelDb: Int,
        ear: String,
        durationMs: Long
    ): String = synchronized(lock) {
        if (state == AudioCoordinatorState.MONITOR_ACTIVE) {
            stopMonitorLocked("switchedToScreening", "Live monitor stopped for tone playback.")
        }
        val previousToken = activeToneToken
        if (stimulusEngine.isPlaying() && previousToken != null) {
            stimulusEngine.stopTone()
            emit(mapOf("type" to "toneState", "token" to previousToken, "state" to "interrupted"))
        }

        val token = "tone_${++toneSeq}_${System.currentTimeMillis()}"
        activeToneToken = token

        if (!requestAudioFocusLocked(forMonitor = false)) {
            abandonAudioFocusLocked()
            emit(mapOf("type" to "toneState", "token" to token, "state" to "focusLost"))
            return token
        }

        val toneEar = if (ear.equals("RIGHT", ignoreCase = true)) ToneEar.RIGHT else ToneEar.LEFT
        state = AudioCoordinatorState.SCREENING_TONE_ACTIVE

        stimulusEngine.playTone(
            frequencyHz = frequencyHz,
            levelDb = levelDb,
            ear = toneEar,
            durationMs = durationMs,
            onToneStarted = {
                emit(mapOf("type" to "toneState", "token" to token, "state" to "started"))
            },
            onToneFinished = {
                synchronized(lock) {
                    if (activeToneToken == token) {
                        activeToneToken = null
                        abandonAudioFocusLocked()
                        state = if (state == AudioCoordinatorState.SCREENING_TONE_ACTIVE) {
                            AudioCoordinatorState.SCREENING_NOISE_ONLY
                        } else {
                            AudioCoordinatorState.IDLE
                        }
                        emit(mapOf("type" to "toneState", "token" to token, "state" to "finished"))
                    }
                }
            }
        )
        token
    }

    fun stopTone(reason: String = "interrupted") = synchronized(lock) {
        val token = activeToneToken
        val wasPlaying = stimulusEngine.isPlaying()
        stimulusEngine.stopTone()
        activeToneToken = null
        if (state == AudioCoordinatorState.SCREENING_TONE_ACTIVE) {
            abandonAudioFocusLocked()
            state = AudioCoordinatorState.SCREENING_NOISE_ONLY
        }
        if (wasPlaying && token != null) {
            emit(mapOf("type" to "toneState", "token" to token, "state" to reason))
        }
    }

    fun isTonePlaying(): Boolean = stimulusEngine.isPlaying()

    // ---- Oboe full-duplex Live Monitor -------------------------------------------------------

    fun startMonitor(inputId: Int, outputId: Int, level: Float): Map<String, Any> = synchronized(lock) {
        // Release any active screening audio before claiming full-duplex mic + output.
        stopTone("interrupted")
        noiseMonitor.stopMonitoring()
        abandonAudioFocusLocked()

        if (!deviceManager.hasInputDeviceId(inputId)) {
            return mapOf("started" to false, "message" to "Choose an available microphone before starting.")
        }
        if (!deviceManager.isAllowedMonitorOutputId(outputId)) {
            return mapOf(
                "started" to false,
                "message" to "Built-in speaker output is blocked for safety. Connect wired, USB, or Bluetooth headphones."
            )
        }
        if (!requestAudioFocusLocked(forMonitor = true)) {
            abandonAudioFocusLocked()
            return mapOf("started" to false, "message" to "Could not get audio focus. Pause other audio and try again.")
        }

        NativeAudioEngine.nativeSetMonitorLevel(level.coerceIn(0f, 0.5f))
        if (!NativeAudioEngine.nativeStart(inputId, outputId)) {
            abandonAudioFocusLocked()
            return mapOf("started" to false, "message" to NativeAudioEngine.nativeGetStreamInfo())
        }

        activeMonitorInputId = inputId
        activeMonitorOutputId = outputId
        state = AudioCoordinatorState.MONITOR_ACTIVE
        startMonitorPollLoop()
        return mapOf("started" to true, "message" to "Starting audio monitor...")
    }

    fun stopMonitor(reason: String = "user", message: String = "Stopped") = synchronized(lock) {
        stopMonitorLocked(reason, message)
    }

    private fun stopMonitorLocked(reason: String, message: String) {
        monitorPollJob?.cancel()
        monitorPollJob = null
        val wasActive = state == AudioCoordinatorState.MONITOR_ACTIVE || NativeAudioEngine.nativeIsRunning()
        if (wasActive) {
            NativeAudioEngine.nativeStop()
            abandonAudioFocusLocked()
            activeMonitorInputId = null
            activeMonitorOutputId = null
            state = AudioCoordinatorState.IDLE
            emit(
                mapOf(
                    "type" to "monitorStopped",
                    "reason" to reason,
                    "message" to message
                )
            )
        }
    }

    fun releaseAllAudio(reason: String = "backgrounded") = synchronized(lock) {
        val toneToken = activeToneToken
        val toneWasPlaying = stimulusEngine.isPlaying()
        stimulusEngine.stopTone()
        activeToneToken = null
        if (toneWasPlaying && toneToken != null) {
            emit(mapOf("type" to "toneState", "token" to toneToken, "state" to "interrupted"))
        }

        noiseMonitor.stopMonitoring()
        stopMonitorLocked(reason, "Stopped because app moved to background.")
        abandonAudioFocusLocked()
        state = AudioCoordinatorState.IDLE
    }

    private fun startMonitorPollLoop() {
        monitorPollJob?.cancel()
        monitorPollJob = scope.launch {
            while (isActive) {
                val running = synchronized(lock) { state == AudioCoordinatorState.MONITOR_ACTIVE }
                if (!running) return@launch
                if (!NativeAudioEngine.nativeIsRunning()) {
                    val info = NativeAudioEngine.nativeGetStreamInfo()
                    val msg = if (info == "Audio stream stopped") "Audio monitor stopped" else info
                    synchronized(lock) { stopMonitorLocked("disconnected", msg) }
                    return@launch
                }
                val peak = NativeAudioEngine.nativeGetInputPeak().coerceIn(0f, 1f).toDouble()
                val info = NativeAudioEngine.nativeGetStreamInfo()
                emit(
                    mapOf(
                        "type" to "monitorPeak",
                        "peak" to peak,
                        "streamInfo" to info,
                        "timestampMs" to System.currentTimeMillis()
                    )
                )
                delay(250L)
            }
        }
    }

    private fun handleDevicesChanged() {
        val screeningRoute = deviceManager.getCurrentScreeningRouteMap()
        val monitorDevices = getMonitorDevicesMap()
        synchronized(lock) {
            if (state == AudioCoordinatorState.MONITOR_ACTIVE) {
                val inId = activeMonitorInputId
                val outId = activeMonitorOutputId
                val inputMissing = inId == null || !deviceManager.hasInputDeviceId(inId)
                val outputBlockedOrMissing = outId == null || !deviceManager.isAllowedMonitorOutputId(outId)
                if (inputMissing || outputBlockedOrMissing) {
                    val msg = if (outputBlockedOrMissing) {
                        "Headphone output disconnected or switched to blocked speaker. Live monitor stopped."
                    } else {
                        "Selected microphone disconnected. Choose devices and start again."
                    }
                    stopMonitorLocked("deviceLost", msg)
                }
            }
        }
        emit(
            mapOf(
                "type" to "devicesChanged",
                "screeningRoute" to screeningRoute,
                "monitorDevices" to monitorDevices
            )
        )
    }

    private fun requestAudioFocusLocked(forMonitor: Boolean): Boolean {
        abandonAudioFocusLocked()
        val attrs = if (forMonitor) {
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        } else {
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
        }
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attrs)
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS ||
                    change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
                ) {
                    mainHandler.post { handleAudioFocusLoss() }
                }
            }
            .build()
        focusRequest = req
        return audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonAudioFocusLocked() {
        focusRequest?.let(audioManager::abandonAudioFocusRequest)
        focusRequest = null
    }

    private fun handleAudioFocusLoss() = synchronized(lock) {
        if (state == AudioCoordinatorState.MONITOR_ACTIVE) {
            stopMonitorLocked("focusLost", "Stopped because audio focus was lost")
        }
        if (stimulusEngine.isPlaying() || activeToneToken != null) {
            stopTone("focusLost")
        }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { onEvent(event) }
    }
}

