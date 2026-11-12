package com.echo.hearing

import com.echo.hearing.data.InMemorySessionRepository
import com.echo.hearing.domain.model.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class SessionRepositoryAndPrivacyTest {

    @Test
    fun `in memory repository stores and retrieves sessions without loss`() {
        val repo = InMemorySessionRepository()

        val route = AudioRouteInfo(
            routeType = AudioRouteType.WIRED_HEADPHONES,
            deviceName = "Sony WH-1000XM4 (3.5mm)",
            isStereoCapable = true,
            sampleRateHz = 44100,
            calibrationInfo = CalibrationInfo("Pixel 8", AudioRouteType.WIRED_HEADPHONES, CalibrationProvenance.FIXTURE_DEFAULT, true)
        )

        val session = HearingSessionRecord(
            sessionId = UUID.randomUUID().toString(),
            startedAt = System.currentTimeMillis(),
            completedAt = System.currentTimeMillis() + 60000,
            deviceModel = "Pixel 8",
            androidVersion = 34,
            audioRoute = route,
            isCompleted = true,
            qualityFlags = setOf(QualityFlag.UNCALIBRATED_HARDWARE),
            trials = listOf(
                TrialRecord(1, Ear.LEFT, 1000, 40, TrialOutcome.HEARD, latencyMs = 450),
                TrialRecord(2, Ear.LEFT, 1000, 30, TrialOutcome.NOT_HEARD)
            ),
            thresholdResults = listOf(
                ThresholdResult(Ear.LEFT, 1000, 35, 2, 2)
            ),
            noisePauseCount = 0,
            devicePauseCount = 0
        )

        val saved = repo.saveSession(session)
        assertTrue(saved)

        val retrieved = repo.getSession(session.sessionId)
        assertNotNull(retrieved)
        assertEquals(session.sessionId, retrieved?.sessionId)
        assertEquals(2, retrieved?.trials?.size)
        assertEquals(1, retrieved?.thresholdResults?.size)
        assertTrue(retrieved?.qualityFlags?.contains(QualityFlag.UNCALIBRATED_HARDWARE) == true)
    }

    @Test
    fun `privacy guarantee - zero raw audio stored in session model`() {
        val trial = TrialRecord(
            trialNumber = 1,
            ear = Ear.LEFT,
            frequencyHz = 1000,
            levelDb = 40,
            outcome = TrialOutcome.HEARD,
            latencyMs = 380,
            ambientNoiseLevelDbFs = -52.4
        )

        // Reflection check: Verify no fields in TrialRecord or HearingSessionRecord hold raw PCM byte/short arrays
        val trialFields = TrialRecord::class.java.declaredFields.map { it.type.simpleName }
        assertFalse("TrialRecord must never contain byte array for raw audio", trialFields.contains("byte[]"))
        assertFalse("TrialRecord must never contain short array for raw audio", trialFields.contains("short[]"))

        val sessionFields = HearingSessionRecord::class.java.declaredFields.map { it.type.simpleName }
        assertFalse("HearingSessionRecord must never contain byte array", sessionFields.contains("byte[]"))
    }

    @Test
    fun `simulated sessions carry simulation flag explicitly`() {
        val session = HearingSessionRecord(
            sessionId = "sim-123",
            startedAt = System.currentTimeMillis(),
            deviceModel = "Simulation Emulator",
            androidVersion = 34,
            audioRoute = AudioRouteInfo(
                AudioRouteType.WIRED_HEADPHONES,
                "Virtual Route",
                true,
                44100,
                CalibrationInfo("Virtual", AudioRouteType.WIRED_HEADPHONES, CalibrationProvenance.SIMULATED_PROFILE, true)
            ),
            qualityFlags = setOf(QualityFlag.SIMULATION_ONLY, QualityFlag.UNCALIBRATED_HARDWARE)
        )

        assertTrue(session.qualityFlags.contains(QualityFlag.SIMULATION_ONLY))
        assertTrue(session.qualityFlags.contains(QualityFlag.UNCALIBRATED_HARDWARE))
    }
}
