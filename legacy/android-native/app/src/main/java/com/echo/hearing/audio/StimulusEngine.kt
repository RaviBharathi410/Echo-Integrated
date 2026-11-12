package com.echo.hearing.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import com.echo.hearing.domain.model.Ear
import kotlinx.coroutines.*
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Contract for audiometric stimulus generation.
 * Separates audio playback from domain decision logic.
 */
interface StimulusEngine {
    /**
     * Synthesizes and presents a pure tone.
     * Note: [levelDb] is explicitly a digital attenuation value in dBFS (relative to full scale).
     * It is NOT calibrated dB SPL or dB HL.
     */
    fun playTone(
        frequencyHz: Int,
        levelDb: Int,
        ear: Ear,
        durationMs: Long = 1000L,
        onToneStarted: () -> Unit = {},
        onToneFinished: () -> Unit = {}
    )

    /**
     * Halts playback immediately on interruption or pause.
     */
    fun stopTone()

    fun isPlaying(): Boolean
}

/**
 * Production Android AudioTrack implementation for precise pure-tone synthesis.
 * Uses 16-bit PCM at 44.1 kHz with stereo channel isolation and a raised-cosine
 * envelope to eliminate click/transient artifacts.
 */
class AndroidAudioTrackStimulusEngine(
    private val sampleRateHz: Int = 44100
) : StimulusEngine {

    @Volatile
    private var activeTrack: AudioTrack? = null

    @Volatile
    private var isPlayingState: Boolean = false

    private val engineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var playbackJob: Job? = null

    override fun playTone(
        frequencyHz: Int,
        levelDb: Int,
        ear: Ear,
        durationMs: Long,
        onToneStarted: () -> Unit,
        onToneFinished: () -> Unit
    ) {
        stopTone()

        playbackJob = engineScope.launch {
            try {
                val pcmStereoData = generateTonePcm(
                    frequencyHz = frequencyHz,
                    levelDb = levelDb,
                    ear = ear,
                    durationMs = durationMs,
                    sampleRateHz = sampleRateHz
                )

                val bufferSize = pcmStereoData.size * 2 // 2 bytes per 16-bit short

                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRateHz)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                            .build()
                    )
                    .setBufferSizeInBytes(bufferSize)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                activeTrack = track
                track.write(pcmStereoData, 0, pcmStereoData.size)

                if (!isActive) {
                    track.release()
                    return@launch
                }

                track.play()
                isPlayingState = true
                withContext(Dispatchers.Main) { onToneStarted() }

                delay(durationMs)

                if (isActive) {
                    stopTone()
                    withContext(Dispatchers.Main) { onToneFinished() }
                }
            } catch (e: CancellationException) {
                // Expected when tone is stopped or paused
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                isPlayingState = false
            }
        }
    }

    override fun stopTone() {
        playbackJob?.cancel()
        playbackJob = null

        try {
            activeTrack?.let { track ->
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.stop()
                }
                track.release()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            activeTrack = null
            isPlayingState = false
        }
    }

    override fun isPlaying(): Boolean = isPlayingState

    companion object {
        /**
         * Synthesizes 16-bit stereo PCM samples with smooth Hann/raised-cosine ramps.
         * Pure left/right ear channel isolation.
         */
        fun generateTonePcm(
            frequencyHz: Int,
            levelDb: Int,
            ear: Ear,
            durationMs: Long,
            sampleRateHz: Int = 44100,
            rampDurationMs: Long = 20L
        ): ShortArray {
            val totalSamples = (sampleRateHz * (durationMs / 1000.0)).toInt()
            val rampSamples = (sampleRateHz * (rampDurationMs / 1000.0)).toInt().coerceAtMost(totalSamples / 2)

            // Convert dB (relative provisional scale) to linear amplitude multiplier
            // Using safe range: 0 to 80 dB mapped to -80 dBFS .. 0 dBFS
            // e.g. levelDb = 40 -> attenuation = -40 dBFS -> linear = 10^(-40/20) = 0.01
            val attenuationDb = (levelDb - 80).coerceIn(-80, 0)
            val peakAmplitude = 32767.0 * (10.0.pow(attenuationDb / 20.0))

            // Stereo layout: 2 shorts per sample (L, R, L, R...)
            val pcmData = ShortArray(totalSamples * 2)

            val angularFrequency = 2.0 * PI * frequencyHz / sampleRateHz

            for (i in 0 until totalSamples) {
                // Compute envelope window (raised-cosine)
                val envelope = when {
                    i < rampSamples -> 0.5 * (1.0 - cos(PI * i / rampSamples))
                    i >= totalSamples - rampSamples -> 0.5 * (1.0 - cos(PI * (totalSamples - 1 - i) / rampSamples))
                    else -> 1.0
                }

                val sampleValue = (peakAmplitude * envelope * sin(angularFrequency * i)).toInt().toShort()

                val leftIndex = i * 2
                val rightIndex = i * 2 + 1

                when (ear) {
                    Ear.LEFT -> {
                        pcmData[leftIndex] = sampleValue
                        pcmData[rightIndex] = 0
                    }
                    Ear.RIGHT -> {
                        pcmData[leftIndex] = 0
                        pcmData[rightIndex] = sampleValue
                    }
                }
            }

            return pcmData
        }
    }
}

/**
 * Deterministic fake stimulus engine for fast automated unit tests.
 */
class FakeStimulusEngine : StimulusEngine {
    data class PlayedToneEvent(
        val frequencyHz: Int,
        val levelDb: Int,
        val ear: Ear,
        val durationMs: Long
    )

    val playbackHistory = mutableListOf<PlayedToneEvent>()
    var activeTone: PlayedToneEvent? = null
        private set

    private var playing: Boolean = false

    override fun playTone(
        frequencyHz: Int,
        levelDb: Int,
        ear: Ear,
        durationMs: Long,
        onToneStarted: () -> Unit,
        onToneFinished: () -> Unit
    ) {
        val event = PlayedToneEvent(frequencyHz, levelDb, ear, durationMs)
        playbackHistory.add(event)
        activeTone = event
        playing = true
        onToneStarted()
    }

    override fun stopTone() {
        activeTone = null
        playing = false
    }

    override fun isPlaying(): Boolean = playing

    fun simulateToneFinished(onToneFinished: () -> Unit) {
        activeTone = null
        playing = false
        onToneFinished()
    }
}
