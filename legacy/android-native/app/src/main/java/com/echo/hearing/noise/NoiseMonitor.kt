package com.echo.hearing.noise

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import com.echo.hearing.domain.model.NoiseAssessment
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Continuous environmental acoustic reading.
 * Note: [levelDbFs] is digital amplitude dB relative to full-scale input;
 * it is NOT a calibrated SPL dBA meter without physical acoustic calibration.
 */
data class NoiseReading(
    val levelDbFs: Double,
    val assessment: NoiseAssessment,
    val isDisturbance: Boolean,
    val consecutiveQuietSeconds: Int,
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Interface decoupling noise sensing from screening logic.
 */
interface NoiseMonitor {
    val readingFlow: StateFlow<NoiseReading>

    fun startMonitoring()
    fun stopMonitoring()
    fun isSensorAvailable(): Boolean
    fun checkRecovery(requiredQuietSeconds: Int = 3): Boolean
}

/**
 * Real-time Android microphone noise monitor using AudioRecord.
 * Computes RMS (Root Mean Square) power in 100ms analysis frames.
 * PRIVACY GUARANTEE: Audio samples are analyzed in transient memory only;
 * raw audio buffers are never stored, written to disk, or transmitted over network.
 */
class AndroidMicrophoneNoiseMonitor(
    private val context: Context,
    private val quietThresholdDbFs: Double = -45.0, // Ambient below -45 dBFS is considered quiet
    private val loudDisturbanceDbFs: Double = -32.0 // Ambient above -32 dBFS is marked INVALID
) : NoiseMonitor {

    private val _readingFlow = MutableStateFlow(
        NoiseReading(
            levelDbFs = -100.0,
            assessment = NoiseAssessment.UNAVAILABLE,
            isDisturbance = false,
            consecutiveQuietSeconds = 0
        )
    )
    override val readingFlow: StateFlow<NoiseReading> = _readingFlow.asStateFlow()

    private val monitorScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var recordingJob: Job? = null

    @Volatile
    private var isRecording: Boolean = false
    private var quietFramesCount: Int = 0

    override fun isSensorAvailable(): Boolean {
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        val hasMicFeature = context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
        return hasPermission && hasMicFeature
    }

    @SuppressLint("MissingPermission")
    override fun startMonitoring() {
        if (!isSensorAvailable()) {
            _readingFlow.value = NoiseReading(
                levelDbFs = -100.0,
                assessment = NoiseAssessment.UNAVAILABLE,
                isDisturbance = true,
                consecutiveQuietSeconds = 0
            )
            return
        }

        if (isRecording) return
        isRecording = true

        recordingJob = monitorScope.launch {
            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            val bufferSize = minBufferSize.coerceAtLeast(sampleRate / 10) // ~100ms chunk

            var audioRecord: AudioRecord? = null
            try {
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )

                if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
                    _readingFlow.value = NoiseReading(
                        levelDbFs = -100.0,
                        assessment = NoiseAssessment.UNAVAILABLE,
                        isDisturbance = true,
                        consecutiveQuietSeconds = 0
                    )
                    return@launch
                }

                audioRecord.startRecording()
                val buffer = ShortArray(bufferSize)

                while (isActive && isRecording) {
                    val readSamples = audioRecord.read(buffer, 0, buffer.size)
                    if (readSamples > 0) {
                        var sumSquares = 0.0
                        for (i in 0 until readSamples) {
                            val sample = buffer[i].toDouble()
                            sumSquares += sample * sample
                        }
                        val rms = sqrt(sumSquares / readSamples)
                        // Map 16-bit max amplitude (32768) to dBFS
                        val dbFs = if (rms > 0.0) {
                            (20.0 * log10(rms / 32768.0)).coerceIn(-100.0, 0.0)
                        } else {
                            -100.0
                        }

                        val assessment = when {
                            dbFs > loudDisturbanceDbFs -> NoiseAssessment.INVALID
                            dbFs > quietThresholdDbFs -> NoiseAssessment.SUSPECT
                            else -> NoiseAssessment.VALID
                        }

                        if (assessment == NoiseAssessment.VALID) {
                            quietFramesCount++
                        } else {
                            quietFramesCount = 0
                        }

                        // ~10 frames per second
                        val quietSeconds = quietFramesCount / 10

                        _readingFlow.value = NoiseReading(
                            levelDbFs = dbFs,
                            assessment = assessment,
                            isDisturbance = assessment != NoiseAssessment.VALID,
                            consecutiveQuietSeconds = quietSeconds
                        )
                    }
                    delay(100L)
                }
            } catch (e: Exception) {
                _readingFlow.value = NoiseReading(
                    levelDbFs = -100.0,
                    assessment = NoiseAssessment.UNAVAILABLE,
                    isDisturbance = true,
                    consecutiveQuietSeconds = 0
                )
            } finally {
                try {
                    audioRecord?.stop()
                    audioRecord?.release()
                } catch (ignored: Exception) {}
            }
        }
    }

    override fun stopMonitoring() {
        isRecording = false
        recordingJob?.cancel()
        recordingJob = null
        quietFramesCount = 0
    }

    override fun checkRecovery(requiredQuietSeconds: Int): Boolean {
        return _readingFlow.value.consecutiveQuietSeconds >= requiredQuietSeconds &&
                _readingFlow.value.assessment == NoiseAssessment.VALID
    }
}

/**
 * Deterministic fake noise monitor for automated testing and developer simulation panel.
 */
class FakeNoiseMonitor(
    initialAssessment: NoiseAssessment = NoiseAssessment.VALID,
    initialLevelDbFs: Double = -55.0
) : NoiseMonitor {

    private val _readingFlow = MutableStateFlow(
        NoiseReading(
            levelDbFs = initialLevelDbFs,
            assessment = initialAssessment,
            isDisturbance = initialAssessment != NoiseAssessment.VALID,
            consecutiveQuietSeconds = if (initialAssessment == NoiseAssessment.VALID) 5 else 0
        )
    )
    override val readingFlow: StateFlow<NoiseReading> = _readingFlow.asStateFlow()

    var sensorAvailable: Boolean = true

    override fun startMonitoring() {
        if (!sensorAvailable) {
            injectAssessment(NoiseAssessment.UNAVAILABLE, -100.0)
        }
    }

    override fun stopMonitoring() {}

    override fun isSensorAvailable(): Boolean = sensorAvailable

    override fun checkRecovery(requiredQuietSeconds: Int): Boolean {
        return _readingFlow.value.assessment == NoiseAssessment.VALID &&
                _readingFlow.value.consecutiveQuietSeconds >= requiredQuietSeconds
    }

    fun injectAssessment(
        assessment: NoiseAssessment,
        levelDbFs: Double = when (assessment) {
            NoiseAssessment.VALID -> -55.0
            NoiseAssessment.SUSPECT -> -38.0
            NoiseAssessment.INVALID -> -25.0
            NoiseAssessment.UNAVAILABLE -> -100.0
        },
        quietSeconds: Int = if (assessment == NoiseAssessment.VALID) 5 else 0
    ) {
        _readingFlow.value = NoiseReading(
            levelDbFs = levelDbFs,
            assessment = assessment,
            isDisturbance = assessment != NoiseAssessment.VALID,
            consecutiveQuietSeconds = quietSeconds
        )
    }
}
