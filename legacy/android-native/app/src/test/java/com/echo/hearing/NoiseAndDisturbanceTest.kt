package com.echo.hearing

import com.echo.hearing.domain.model.NoiseAssessment
import com.echo.hearing.noise.FakeNoiseMonitor
import org.junit.Assert.*
import org.junit.Test

class NoiseAndDisturbanceTest {

    @Test
    fun `fake noise monitor injects states accurately`() {
        val monitor = FakeNoiseMonitor(NoiseAssessment.VALID, -60.0)

        assertEquals(NoiseAssessment.VALID, monitor.readingFlow.value.assessment)
        assertFalse(monitor.readingFlow.value.isDisturbance)

        // Inject loud disturbance
        monitor.injectAssessment(NoiseAssessment.INVALID, -20.0, quietSeconds = 0)
        assertEquals(NoiseAssessment.INVALID, monitor.readingFlow.value.assessment)
        assertTrue(monitor.readingFlow.value.isDisturbance)
        assertEquals(-20.0, monitor.readingFlow.value.levelDbFs, 0.01)
    }

    @Test
    fun `recovery check fails when noise is invalid or quiet window is insufficient`() {
        val monitor = FakeNoiseMonitor()

        // 1. Noise is INVALID
        monitor.injectAssessment(NoiseAssessment.INVALID, -25.0, quietSeconds = 0)
        assertFalse(monitor.checkRecovery(requiredQuietSeconds = 3))

        // 2. Noise is VALID but has only been quiet for 1 second (< 3 required)
        monitor.injectAssessment(NoiseAssessment.VALID, -55.0, quietSeconds = 1)
        assertFalse(monitor.checkRecovery(requiredQuietSeconds = 3))

        // 3. Noise is VALID and has been quiet for 4 seconds (>= 3 required)
        monitor.injectAssessment(NoiseAssessment.VALID, -55.0, quietSeconds = 4)
        assertTrue(monitor.checkRecovery(requiredQuietSeconds = 3))
    }

    @Test
    fun `unavailable sensor reported when microphone permission missing`() {
        val monitor = FakeNoiseMonitor()
        monitor.sensorAvailable = false
        monitor.startMonitoring()

        assertEquals(NoiseAssessment.UNAVAILABLE, monitor.readingFlow.value.assessment)
        assertTrue(monitor.readingFlow.value.isDisturbance)
    }
}
