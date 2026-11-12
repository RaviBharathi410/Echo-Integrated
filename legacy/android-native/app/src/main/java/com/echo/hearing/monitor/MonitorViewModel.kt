package com.echo.hearing.monitor

import android.app.Application
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.echo.hearing.data.LocalJsonSessionRepository
import com.echo.hearing.domain.model.Ear
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

object MonitorLimits {
    val EQ_CENTERS_HZ = intArrayOf(250, 500, 1000, 2000, 4000, 6000)
    const val INITIAL_MONITOR_LEVEL = 0.15f
    const val MAX_MONITOR_LEVEL = 0.50f
    const val INITIAL_COMPRESSION_RATIO = 2.0f
    const val INITIAL_GATE_THRESHOLD_DB = -54f
    const val MIN_GATE_THRESHOLD_DB = -72f
    const val MAX_GATE_THRESHOLD_DB = -36f
    const val INITIAL_DENOISER_DB = 9f
    const val MAX_DENOISER_DB = 18f
    const val MAX_GAIN_DB = 6f
    const val MIN_HL = -10f
    const val MAX_HL = 120f
    const val MAX_CLARITY_WORDS = 200
    const val MAX_CLARITY_TRIALS = 40
    val ENVIRONMENTS = listOf("Quiet", "Background noise")
}

data class DeviceOption(val id: Int, val label: String)

data class MonitorUiState(
    val running: Boolean = false,
    val status: String = "Stopped",
    val inputs: List<DeviceOption> = emptyList(),
    val outputs: List<DeviceOption> = emptyList(),
    val inputId: Int? = null,
    val outputId: Int? = null,
    val monitorLevel: Float = MonitorLimits.INITIAL_MONITOR_LEVEL,
    val gateEnabled: Boolean = true,
    val gateThresholdDb: Float = MonitorLimits.INITIAL_GATE_THRESHOLD_DB,
    val denoiserEnabled: Boolean = false,
    val denoiserStrengthDb: Float = MonitorLimits.INITIAL_DENOISER_DB,
    val compressionEnabled: Boolean = true,
    val compressionRatio: Float = MonitorLimits.INITIAL_COMPRESSION_RATIO,
    val processed: Boolean = true,
    /** [ear][band] fitting offsets in dB; ear 0 = left, 1 = right. */
    val gains: List<List<Float>> = List(2) { List(MonitorLimits.EQ_CENTERS_HZ.size) { 0f } },
    /** [ear][band] audiogram dB HL entries as typed text (reference only). */
    val thresholds: List<List<String>> = List(2) { List(MonitorLimits.EQ_CENTERS_HZ.size) { "" } },
    val realEarVerified: Boolean = false,
    val realEarNotes: String = "",
    val environment: String = MonitorLimits.ENVIRONMENTS[0],
    val trials: List<String> = emptyList(),
    val trialMessage: String = "",
    val importMessage: String = ""
)

class MonitorViewModel(app: Application) : AndroidViewModel(app) {

    private val audioManager = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val repository = LocalJsonSessionRepository(app)
    private val handler = Handler(Looper.getMainLooper())

    private val _state = MutableStateFlow(MonitorUiState())
    val state: StateFlow<MonitorUiState> = _state.asStateFlow()

    private var inputDevices: List<AudioDeviceInfo> = emptyList()
    private var outputDevices: List<AudioDeviceInfo> = emptyList()
    private var focusRequest: AudioFocusRequest? = null
    private var pollJob: Job? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = refreshDevices()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = refreshDevices()
    }

    init {
        restore()
        applyDsp()
        audioManager.registerAudioDeviceCallback(deviceCallback, handler)
        refreshDevices()
    }

    override fun onCleared() {
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        stop("Stopped")
        super.onCleared()
    }

    // ---- devices -----------------------------------------------------------------------------

    fun refreshDevices() {
        inputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS).sortedBy(::label)
        outputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).sortedBy(::label)
        val s = _state.value
        val inId = s.inputId?.takeIf { id -> inputDevices.any { it.id == id } }
            ?: inputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }?.id
            ?: inputDevices.firstOrNull()?.id
        val outId = s.outputId?.takeIf { id -> outputDevices.any { it.id == id } }
            ?: outputDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }?.id
        val lost = s.running && (inId != s.inputId || outId != s.outputId)
        _state.update {
            it.copy(
                inputs = inputDevices.map { d -> DeviceOption(d.id, label(d)) },
                outputs = outputDevices.map { d -> DeviceOption(d.id, label(d)) },
                inputId = inId,
                outputId = outId
            )
        }
        if (lost) stop("Selected audio device disconnected. Choose devices and start again.")
    }

    fun selectInput(id: Int) = _state.update { it.copy(inputId = id) }
    fun selectOutput(id: Int) = _state.update { it.copy(outputId = id) }

    private fun label(d: AudioDeviceInfo): String {
        val name = d.productName?.toString()?.takeIf { it.isNotBlank() } ?: "Audio device"
        return "$name · ${typeName(d.type)}"
    }

    private fun typeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in mic"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth mic (SCO)"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired headset"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB headset"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Phone earpiece"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth audio"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        AudioDeviceInfo.TYPE_LINE_ANALOG -> "Analog line"
        AudioDeviceInfo.TYPE_DOCK -> "Dock"
        else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            (type == AudioDeviceInfo.TYPE_BLE_HEADSET || type == AudioDeviceInfo.TYPE_BLE_SPEAKER)
        ) "Bluetooth LE" else "Audio device"
    }

    // ---- start / stop ------------------------------------------------------------------------

    fun start() {
        if (_state.value.running) return
        refreshDevices()
        val s = _state.value
        val out = outputDevices.firstOrNull { it.id == s.outputId }
            ?: return setStatus("Choose a playback output device before starting.")
        val inp = inputDevices.firstOrNull { it.id == s.inputId }
            ?: return setStatus("Choose an available microphone before starting.")
        if (!requestFocus()) {
            releaseFocus()
            return setStatus("Could not get audio focus. Pause other audio and try again.")
        }
        NativeAudioEngine.nativeSetMonitorLevel(s.monitorLevel)
        if (!NativeAudioEngine.nativeStart(inp.id, out.id)) {
            releaseFocus()
            return setStatus(NativeAudioEngine.nativeGetStreamInfo())
        }
        _state.update { it.copy(running = true, status = "Starting audio monitor…") }
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (true) {
                if (!NativeAudioEngine.nativeIsRunning()) {
                    val msg = NativeAudioEngine.nativeGetStreamInfo()
                    stop(if (msg == "Audio stream stopped") "Audio monitor stopped" else msg)
                    return@launch
                }
                val peak = NativeAudioEngine.nativeGetInputPeak().coerceIn(0f, 1f)
                setStatus("Monitoring · mic level ${(peak * 100).toInt()}%\n" + NativeAudioEngine.nativeGetStreamInfo())
                delay(STATUS_REFRESH_MS)
            }
        }
    }

    fun stop(message: String = "Stopped") {
        pollJob?.cancel()
        pollJob = null
        if (_state.value.running) {
            NativeAudioEngine.nativeStop()
            releaseFocus()
            _state.update { it.copy(running = false, status = message) }
        }
    }

    private fun setStatus(text: String) = _state.update { it.copy(status = text) }

    private fun requestFocus(): Boolean {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attrs)
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener { change ->
                if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                    handler.post { stop("Stopped because audio focus was lost") }
                }
            }
            .build()
        focusRequest = req
        return audioManager.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun releaseFocus() {
        focusRequest?.let(audioManager::abandonAudioFocusRequest)
        focusRequest = null
    }

    fun onPermissionDenied() = setStatus("Microphone permission is required for live monitoring.")

    // ---- DSP controls ------------------------------------------------------------------------

    fun setMonitorLevel(v: Float) {
        val level = v.coerceIn(0f, MonitorLimits.MAX_MONITOR_LEVEL)
        _state.update { it.copy(monitorLevel = level) }
        NativeAudioEngine.nativeSetMonitorLevel(level)
        prefs.edit().putFloat(K_LEVEL, level).apply()
    }

    fun setGateEnabled(on: Boolean) {
        _state.update { it.copy(gateEnabled = on) }
        NativeAudioEngine.nativeSetNoiseGateEnabled(on)
        prefs.edit().putBoolean(K_GATE_ON, on).apply()
    }

    fun setGateThreshold(db: Float) {
        _state.update { it.copy(gateThresholdDb = db) }
        NativeAudioEngine.nativeSetNoiseGateThresholdDb(db)
        prefs.edit().putFloat(K_GATE_DB, db).apply()
    }

    fun setDenoiserEnabled(on: Boolean) {
        _state.update { it.copy(denoiserEnabled = on) }
        NativeAudioEngine.nativeSetAdaptiveDenoiserEnabled(on)
        prefs.edit().putBoolean(K_DEN_ON, on).apply()
    }

    fun setDenoiserStrength(db: Float) {
        _state.update { it.copy(denoiserStrengthDb = db) }
        NativeAudioEngine.nativeSetAdaptiveDenoiserStrengthDb(db)
        prefs.edit().putFloat(K_DEN_DB, db).apply()
    }

    fun setCompressionEnabled(on: Boolean) {
        _state.update { it.copy(compressionEnabled = on) }
        NativeAudioEngine.nativeSetSpeechCompressionEnabled(on)
        prefs.edit().putBoolean(K_COMP_ON, on).apply()
    }

    fun setCompressionRatio(r: Float) {
        _state.update { it.copy(compressionRatio = r) }
        NativeAudioEngine.nativeSetSpeechCompressionRatio(r)
        prefs.edit().putFloat(K_COMP_RATIO, r).apply()
    }

    fun setProcessed(on: Boolean) {
        _state.update { it.copy(processed = on) }
        NativeAudioEngine.nativeSetDspBypassed(!on)
        prefs.edit().putBoolean(K_PROCESSED, on).apply()
    }

    fun setGain(ear: Int, band: Int, db: Float) {
        val g = db.coerceIn(-MonitorLimits.MAX_GAIN_DB, MonitorLimits.MAX_GAIN_DB)
        _state.update { s ->
            s.copy(gains = s.gains.mapIndexed { e, row -> if (e == ear) row.toMutableList().also { it[band] = g } else row })
        }
        NativeAudioEngine.nativeSetEqualizerBand(ear, band, g)
        prefs.edit().putFloat(gainKey(ear, band), g).apply()
    }

    fun resetDefaults() {
        _state.update {
            it.copy(
                monitorLevel = MonitorLimits.INITIAL_MONITOR_LEVEL,
                compressionEnabled = true,
                compressionRatio = MonitorLimits.INITIAL_COMPRESSION_RATIO,
                gateEnabled = true,
                gateThresholdDb = MonitorLimits.INITIAL_GATE_THRESHOLD_DB,
                denoiserEnabled = false,
                denoiserStrengthDb = MonitorLimits.INITIAL_DENOISER_DB,
                processed = true,
                gains = List(2) { List(MonitorLimits.EQ_CENTERS_HZ.size) { 0f } }
            )
        }
        applyDsp()
        val s = _state.value
        val e = prefs.edit()
            .putFloat(K_LEVEL, s.monitorLevel).putBoolean(K_COMP_ON, true)
            .putFloat(K_COMP_RATIO, s.compressionRatio).putBoolean(K_GATE_ON, true)
            .putFloat(K_GATE_DB, s.gateThresholdDb).putBoolean(K_DEN_ON, false)
            .putFloat(K_DEN_DB, s.denoiserStrengthDb).putBoolean(K_PROCESSED, true)
        for (ear in 0..1) for (b in MonitorLimits.EQ_CENTERS_HZ.indices) e.putFloat(gainKey(ear, b), 0f)
        e.apply()
    }

    private fun applyDsp() {
        val s = _state.value
        NativeAudioEngine.nativeSetMonitorLevel(s.monitorLevel)
        NativeAudioEngine.nativeSetSpeechCompressionEnabled(s.compressionEnabled)
        NativeAudioEngine.nativeSetSpeechCompressionRatio(s.compressionRatio)
        NativeAudioEngine.nativeSetNoiseGateEnabled(s.gateEnabled)
        NativeAudioEngine.nativeSetNoiseGateThresholdDb(s.gateThresholdDb)
        NativeAudioEngine.nativeSetAdaptiveDenoiserEnabled(s.denoiserEnabled)
        NativeAudioEngine.nativeSetAdaptiveDenoiserStrengthDb(s.denoiserStrengthDb)
        NativeAudioEngine.nativeSetDspBypassed(!s.processed)
        for (ear in 0..1) for (b in MonitorLimits.EQ_CENTERS_HZ.indices) {
            NativeAudioEngine.nativeSetEqualizerBand(ear, b, s.gains[ear][b])
        }
    }

    // ---- hearing profile ---------------------------------------------------------------------

    fun setThreshold(ear: Int, band: Int, text: String) {
        _state.update { s ->
            s.copy(thresholds = s.thresholds.mapIndexed { e, row -> if (e == ear) row.toMutableList().also { it[band] = text } else row })
        }
        val v = text.trim().toFloatOrNull()
        if (text.isBlank() || (v != null && v in MonitorLimits.MIN_HL..MonitorLimits.MAX_HL)) {
            prefs.edit().putString(thresholdKey(ear, band), text.trim()).apply()
        }
    }

    /** Copies the latest saved screening's thresholds into the reference audiogram fields. */
    fun importLatestScreening() {
        viewModelScope.launch {
            val latest = runCatching {
                repository.listSessions().filter { it.thresholdResults.isNotEmpty() }.maxByOrNull { it.startedAt }
            }.getOrNull()
            if (latest == null) {
                _state.update { it.copy(importMessage = "No screening results saved yet. Run a screening first.") }
                return@launch
            }
            var count = 0
            for (r in latest.thresholdResults) {
                val band = MonitorLimits.EQ_CENTERS_HZ.indexOf(r.frequencyHz)
                val ear = if (r.ear == Ear.LEFT) 0 else 1
                if (band >= 0 && r.thresholdDb.toFloat() in MonitorLimits.MIN_HL..MonitorLimits.MAX_HL) {
                    setThreshold(ear, band, r.thresholdDb.toString())
                    count++
                }
            }
            val date = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(latest.startedAt))
            _state.update {
                it.copy(
                    importMessage = "Imported $count values from the $date screening. These are uncalibrated " +
                        "screening levels, kept as reference only. They do not change any gain."
                )
            }
        }
    }

    fun setRealEarVerified(v: Boolean) {
        _state.update { it.copy(realEarVerified = v) }
        prefs.edit().putBoolean(K_REAL_EAR, v).apply()
    }

    fun setRealEarNotes(t: String) {
        _state.update { it.copy(realEarNotes = t) }
        prefs.edit().putString(K_REAL_EAR_NOTES, t).apply()
    }

    // ---- speech clarity A/B log --------------------------------------------------------------

    fun setEnvironment(env: String) {
        _state.update { it.copy(environment = env) }
        prefs.edit().putString(K_ENV, env).apply()
    }

    fun saveTrial(correctText: String, totalText: String): Boolean {
        val correct = correctText.toIntOrNull()
        val total = totalText.toIntOrNull()
        if (total == null || total !in 1..MonitorLimits.MAX_CLARITY_WORDS || correct == null || correct !in 0..total) {
            _state.update { it.copy(trialMessage = "Enter a correct count from 0 to the list size (1–${MonitorLimits.MAX_CLARITY_WORDS}).") }
            return false
        }
        val s = _state.value
        val entry = listOf(
            System.currentTimeMillis(), s.environment, if (s.processed) "Processed" else "Baseline", correct, total
        ).joinToString("|")
        val previous = prefs.getString(K_TRIALS, "").orEmpty().lineSequence().filter { it.isNotBlank() }.toList()
        prefs.edit().putString(K_TRIALS, (listOf(entry) + previous).take(MonitorLimits.MAX_CLARITY_TRIALS).joinToString("\n")).apply()
        _state.update { it.copy(trials = loadTrials(), trialMessage = "") }
        return true
    }

    private fun loadTrials(): List<String> =
        prefs.getString(K_TRIALS, "").orEmpty().lineSequence().mapNotNull { line ->
            val f = line.split('|')
            if (f.size != 5) return@mapNotNull null
            val ts = f[0].toLongOrNull() ?: return@mapNotNull null
            val correct = f[3].toIntOrNull() ?: return@mapNotNull null
            val total = f[4].toIntOrNull()?.takeIf { it > 0 } ?: return@mapNotNull null
            if (correct !in 0..total) return@mapNotNull null
            "${f[1]} · ${f[2]} · $correct/$total (${correct * 100 / total}%) · " +
                DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(ts))
        }.take(MonitorLimits.MAX_CLARITY_TRIALS).toList()

    // ---- persistence -------------------------------------------------------------------------

    private fun restore() {
        val gains = List(2) { ear ->
            List(MonitorLimits.EQ_CENTERS_HZ.size) { b ->
                prefs.getFloat(gainKey(ear, b), 0f).coerceIn(-MonitorLimits.MAX_GAIN_DB, MonitorLimits.MAX_GAIN_DB)
            }
        }
        val thresholds = List(2) { ear ->
            List(MonitorLimits.EQ_CENTERS_HZ.size) { b -> prefs.getString(thresholdKey(ear, b), "").orEmpty() }
        }
        _state.value = MonitorUiState(
            monitorLevel = prefs.getFloat(K_LEVEL, MonitorLimits.INITIAL_MONITOR_LEVEL).coerceIn(0f, MonitorLimits.MAX_MONITOR_LEVEL),
            gateEnabled = prefs.getBoolean(K_GATE_ON, true),
            gateThresholdDb = prefs.getFloat(K_GATE_DB, MonitorLimits.INITIAL_GATE_THRESHOLD_DB)
                .coerceIn(MonitorLimits.MIN_GATE_THRESHOLD_DB, MonitorLimits.MAX_GATE_THRESHOLD_DB),
            denoiserEnabled = prefs.getBoolean(K_DEN_ON, false),
            denoiserStrengthDb = prefs.getFloat(K_DEN_DB, MonitorLimits.INITIAL_DENOISER_DB).coerceIn(0f, MonitorLimits.MAX_DENOISER_DB),
            compressionEnabled = prefs.getBoolean(K_COMP_ON, true),
            compressionRatio = prefs.getFloat(K_COMP_RATIO, MonitorLimits.INITIAL_COMPRESSION_RATIO).coerceIn(1f, 3f),
            processed = prefs.getBoolean(K_PROCESSED, true),
            gains = gains,
            thresholds = thresholds,
            realEarVerified = prefs.getBoolean(K_REAL_EAR, false),
            realEarNotes = prefs.getString(K_REAL_EAR_NOTES, "").orEmpty(),
            environment = prefs.getString(K_ENV, null)?.takeIf { it in MonitorLimits.ENVIRONMENTS } ?: MonitorLimits.ENVIRONMENTS[0],
            trials = loadTrials()
        )
    }

    private fun gainKey(ear: Int, band: Int) = "gain_${ear}_$band"
    private fun thresholdKey(ear: Int, band: Int) = "audiogram_${ear}_$band"

    private companion object {
        const val PREFS = "echo_profile"
        const val STATUS_REFRESH_MS = 250L
        const val K_LEVEL = "monitor_level"
        const val K_COMP_ON = "speech_compression_enabled"
        const val K_COMP_RATIO = "speech_compression_ratio"
        const val K_GATE_ON = "noise_gate_enabled"
        const val K_GATE_DB = "noise_gate_threshold_dbfs"
        const val K_DEN_ON = "adaptive_denoiser_enabled"
        const val K_DEN_DB = "adaptive_denoiser_strength_db"
        const val K_PROCESSED = "clarity_processed_audio"
        const val K_ENV = "clarity_environment"
        const val K_TRIALS = "clarity_trials"
        const val K_REAL_EAR = "real_ear_verified"
        const val K_REAL_EAR_NOTES = "real_ear_notes"
    }
}
