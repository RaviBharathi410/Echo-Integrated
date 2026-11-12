package com.echo.hearing.noise

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.log10
import kotlin.math.sqrt

data class NativeNoiseReading(
    val levelDbFs: Double,
    val assessment: String, // VALID | SUSPECT | INVALID | UNAVAILABLE
    val isDisturbance: Boolean,
    val consecutiveQuietSeconds: Int,
    val timestampMs: Long = System.currentTimeMillis()
)

/**
 * Real-time microphone RMS analyzer (16 kHz mono 16-bit PCM, 100ms chunks).
 * Audio buffers remain in transient memory only and are never saved or sent.
 */
class AndroidMicrophoneNoiseMonitor(
    private val context: Context,
    private val quietThresholdDbFs: Double = -45.0,
    private val loudDisturbanceDbFs: Double = -32.0
) {
    private val _readingFlow = MutableStateFlow(
        NativeNoiseReading(
            levelDbFs = -100.0,
            assessment = "UNAVAILABLE",
            isDisturbance = false,
            consecutiveQuietSeconds = 0
        )
    )
    val readingFlow: StateFlow<NativeNoiseReading> = _readingFlow.asStateFlow()

    private val monitorScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var recordingJob: Job? = null

    @Volatile
    private var isRecording: Boolean = false
    private var quietFramesCount: Int = 0

    fun isSensorAvailable(): Boolean {
        val hasPermission = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        val hasMicFeature = context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
        return hasPermission && hasMicFeature
    }

    @SuppressLint("MissingPermission")
    fun startMonitoring(onReading: (NativeNoiseReading) -> Unit): Boolean {
        if (!isSensorAvailable()) {
            val unavailable = NativeNoiseReading(
                levelDbFs = -100.0,
                assessment = "UNAVAILABLE",
                isDisturbance = true,
                consecutiveQuietSeconds = 0
            )
            _readingFlow.value = unavailable
            onReading(unavailable)
            return false
        }

        if (isRecording) return true
        isRecording = true
        quietFramesCount = 0

        recordingJob = monitorScope.launch {
            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
            val bufferSize = minBufferSize.coerceAtLeast(sampleRate / 10)

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
                    val unavailable = NativeNoiseReading(
                        levelDbFs = -100.0,
                        assessment = "UNAVAILABLE",
                        isDisturbance = true,
                        consecutiveQuietSeconds = 0
                    )
                    _readingFlow.value = unavailable
                    onReading(unavailable)
                    return@launch
                }

                audioRecord.startRecording()
                val buffer = ShortArray(bufferSize)

                while (isActive && isRecording) {
                    val readSamples = audioRecord.read(buffer, 0, buffer.size)
                    if (readSamples > 0) {
                        var sumSquares = 0.0
                        for (i in 0 until readSamples) {
                            val s = buffer[i].toDouble()
                            sumSquares += s * s
                        }
                        val rms = sqrt(sumSquares / readSamples)
                        val dbFs = if (rms > 0.0) {
                            (20.0 * log10(rms / 32768.0)).coerceIn(-100.0, 0.0)
                        } else {
                            -100.0
                        }
                        val assessment = when {
                            dbFs > loudDisturbanceDbFs -> "INVALID"
                            dbFs > quietThresholdDbFs -> "SUSPECT"
                            else -> "VALID"
                        }
                        if (assessment == "VALID") {
                            quietFramesCount++
                        } else {
                            quietFramesCount = 0
                        }
                        val reading = NativeNoiseReading(
                            levelDbFs = dbFs,
                            assessment = assessment,
                            isDisturbance = assessment != "VALID",
                            consecutiveQuietSeconds = quietFramesCount / 10
                        )
                        _readingFlow.value = reading
                        onReading(reading)
                    }
                    delay(100L)
                }
            } catch (_: Exception) {
                val unavailable = NativeNoiseReading(
                    levelDbFs = -100.0,
                    assessment = "UNAVAILABLE",
                    isDisturbance = true,
                    consecutiveQuietSeconds = 0
                )
                _readingFlow.value = unavailable
                onReading(unavailable)
            } finally {
                isRecording = false
                try {
                    audioRecord?.stop()
                    audioRecord?.release()
                } catch (_: Exception) {}
            }
        }
        return true
    }

    fun stopMonitoring() {
        isRecording = false
        recordingJob?.cancel()
        recordingJob = null
        quietFramesCount = 0
    }
}

