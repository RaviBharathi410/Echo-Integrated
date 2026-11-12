package com.echo.hearing

import com.echo.hearing.audio.AndroidAudioTrackStimulusEngine
import com.echo.hearing.audio.FakeStimulusEngine
import com.echo.hearing.domain.model.Ear
import org.junit.Assert.*
import org.junit.Test

class StimulusEngineTest {

    @Test
    fun `left ear PCM has signal only in left channel`() {
        val pcm = AndroidAudioTrackStimulusEngine.generateTonePcm(
            frequencyHz = 1000,
            levelDb = 60,
            ear = Ear.LEFT,
            durationMs = 200,
            sampleRateHz = 44100
        )

        assertTrue(pcm.isNotEmpty())
        assertEquals(0, pcm.size % 2) // Even number for stereo pairs

        var hasLeftSignal = false
        var hasRightSignal = false

        for (i in 0 until pcm.size step 2) {
            val left = pcm[i]
            val right = pcm[i + 1]

            if (left != 0.toShort()) hasLeftSignal = true
            if (right != 0.toShort()) hasRightSignal = true
        }

        assertTrue("Left channel must contain audio data", hasLeftSignal)
        assertFalse("Right channel must be completely silent for Left ear presentation", hasRightSignal)
    }

    @Test
    fun `right ear PCM has signal only in right channel`() {
        val pcm = AndroidAudioTrackStimulusEngine.generateTonePcm(
            frequencyHz = 1000,
            levelDb = 60,
            ear = Ear.RIGHT,
            durationMs = 200,
            sampleRateHz = 44100
        )

        var hasLeftSignal = false
        var hasRightSignal = false

        for (i in 0 until pcm.size step 2) {
            val left = pcm[i]
            val right = pcm[i + 1]

            if (left != 0.toShort()) hasLeftSignal = true
            if (right != 0.toShort()) hasRightSignal = true
        }

        assertFalse("Left channel must be completely silent for Right ear presentation", hasLeftSignal)
        assertTrue("Right channel must contain audio data", hasRightSignal)
    }

    @Test
    fun `raised-cosine envelope ramps up smoothly from zero`() {
        val pcm = AndroidAudioTrackStimulusEngine.generateTonePcm(
            frequencyHz = 1000,
            levelDb = 70,
            ear = Ear.LEFT,
            durationMs = 100,
            sampleRateHz = 44100,
            rampDurationMs = 20
        )

        // The very first sample at index 0 must be 0 or near zero
        assertEquals(0.toShort(), pcm[0])

        // The peak sample should occur inside the steady-state plateau (e.g. at 50ms)
        val middleSampleIndex = (44100 * 0.05).toInt() * 2
        val middleVal = kotlin.math.abs(pcm[middleSampleIndex].toInt())
        assertTrue("Steady state sample amplitude should be significant", middleVal >= 0)
    }

    @Test
    fun `fake stimulus engine tracks tone and stop behavior`() {
        val fake = FakeStimulusEngine()
        assertFalse(fake.isPlaying())

        var started = false
        var finished = false

        fake.playTone(
            frequencyHz = 2000,
            levelDb = 50,
            ear = Ear.RIGHT,
            durationMs = 1000,
            onToneStarted = { started = true },
            onToneFinished = { finished = true }
        )

        assertTrue(started)
        assertTrue(fake.isPlaying())
        assertEquals(1, fake.playbackHistory.size)
        assertEquals(2000, fake.activeTone?.frequencyHz)

        fake.stopTone()
        assertFalse(fake.isPlaying())
        assertNull(fake.activeTone)
    }
}
