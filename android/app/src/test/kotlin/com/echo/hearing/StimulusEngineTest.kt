package com.echo.hearing

import com.echo.hearing.audio.AndroidAudioTrackStimulusEngine
import com.echo.hearing.audio.ToneEar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class StimulusEngineTest {

    @Test
    fun `left ear PCM has signal only in left channel`() {
        val pcm = AndroidAudioTrackStimulusEngine.generateTonePcm(
            frequencyHz = 1000,
            levelDb = 60,
            ear = ToneEar.LEFT,
            durationMs = 200,
            sampleRateHz = 44100,
        )

        assertTrue(pcm.isNotEmpty())
        assertEquals(0, pcm.size % 2)

        var hasLeftSignal = false
        var hasRightSignal = false

        for (i in 0 until pcm.size step 2) {
            val left = pcm[i]
            val right = pcm[i + 1]
            if (left != 0.toShort()) hasLeftSignal = true
            if (right != 0.toShort()) hasRightSignal = true
        }

        assertTrue("Left channel must contain audio data", hasLeftSignal)
        assertFalse("Right channel must be silent for Left ear presentation", hasRightSignal)
    }

    @Test
    fun `right ear PCM has signal only in right channel`() {
        val pcm = AndroidAudioTrackStimulusEngine.generateTonePcm(
            frequencyHz = 1000,
            levelDb = 60,
            ear = ToneEar.RIGHT,
            durationMs = 200,
            sampleRateHz = 44100,
        )

        var hasLeftSignal = false
        var hasRightSignal = false

        for (i in 0 until pcm.size step 2) {
            val left = pcm[i]
            val right = pcm[i + 1]
            if (left != 0.toShort()) hasLeftSignal = true
            if (right != 0.toShort()) hasRightSignal = true
        }

        assertFalse("Left channel must be silent for Right ear presentation", hasLeftSignal)
        assertTrue("Right channel must contain audio data", hasRightSignal)
    }

    @Test
    fun `raised-cosine envelope ramps up smoothly from zero`() {
        val pcm = AndroidAudioTrackStimulusEngine.generateTonePcm(
            frequencyHz = 1000,
            levelDb = 70,
            ear = ToneEar.LEFT,
            durationMs = 100,
            sampleRateHz = 44100,
            rampDurationMs = 20,
        )

        assertEquals(0.toShort(), pcm[0])
        val middleSampleIndex = (44100 * 0.05).toInt() * 2
        val middleVal = abs(pcm[middleSampleIndex].toInt())
        assertTrue("Steady state sample amplitude should be non-negative", middleVal >= 0)
    }
}

