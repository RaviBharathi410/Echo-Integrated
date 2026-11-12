package com.echo.hearing.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

enum class ToneEar { LEFT, RIGHT }

/**
 * Android AudioTrack pure-tone stimulus generator (44.1 kHz, 16-bit stereo PCM, MODE_STATIC)
 * with raised-cosine ramps and strict left/right channel zero isolation.
 */
class AndroidAudioTrackStimulusEngine(
    private val sampleRateHz: Int = 44100
) {
    @Volatile
    private var activeTrack: AudioTrack? = null

    @Volatile
    private var isPlayingState: Boolean = false

    private val engineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var playbackJob: Job? = null

    fun playTone(
        frequencyHz: Int,
        levelDb: Int,
        ear: ToneEar,
        durationMs: Long = 1000L,
        onToneStarted: () -> Unit = {},
        onToneFinished: () -> Unit = {}
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
                val bufferSize = pcmStereoData.size * 2

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
            } catch (_: CancellationException) {
                // Expected on stop, interruption, or focus loss.
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                isPlayingState = false
            }
        }
    }

    fun stopTone() {
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

    fun isPlaying(): Boolean = isPlayingState

    companion object {
        fun generateTonePcm(
            frequencyHz: Int,
            levelDb: Int,
            ear: ToneEar,
            durationMs: Long,
            sampleRateHz: Int = 44100,
            rampDurationMs: Long = 20L
        ): ShortArray {
            val totalSamples = (sampleRateHz * (durationMs / 1000.0)).toInt()
            val rampSamples = (sampleRateHz * (rampDurationMs / 1000.0)).toInt()
                .coerceAtMost(totalSamples / 2)

            val attenuationDb = (levelDb - 80).coerceIn(-80, 0)
            val peakAmplitude = 32767.0 * (10.0.pow(attenuationDb / 20.0))
            val pcmData = ShortArray(totalSamples * 2)
            val angularFrequency = 2.0 * PI * frequencyHz / sampleRateHz

            for (i in 0 until totalSamples) {
                val envelope = when {
                    i < rampSamples -> 0.5 * (1.0 - cos(PI * i / rampSamples))
                    i >= totalSamples - rampSamples ->
                        0.5 * (1.0 - cos(PI * (totalSamples - 1 - i) / rampSamples))
                    else -> 1.0
                }
                val sampleValue = (peakAmplitude * envelope * sin(angularFrequency * i))
                    .toInt()
                    .toShort()
                val leftIndex = i * 2
                val rightIndex = i * 2 + 1
                when (ear) {
                    ToneEar.LEFT -> {
                        pcmData[leftIndex] = sampleValue
                        pcmData[rightIndex] = 0
                    }
                    ToneEar.RIGHT -> {
                        pcmData[leftIndex] = 0
                        pcmData[rightIndex] = sampleValue
                    }
                }
            }
            return pcmData
        }
    }
}

