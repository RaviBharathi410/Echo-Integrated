package com.echo.hearing.domain.model

/**
 * Standard audiometric test ear.
 */
enum class Ear(val displayName: String, val clinicalCode: String) {
    LEFT("Left Ear", "AS"),
    RIGHT("Right Ear", "AD")
}

/**
 * Standard pure tone audiometric test frequencies in Hz.
 */
object AudiometricFrequencies {
    const val FREQ_250_HZ = 250
    const val FREQ_500_HZ = 500
    const val FREQ_1000_HZ = 1000
    const val FREQ_2000_HZ = 2000
    const val FREQ_4000_HZ = 4000
    const val FREQ_8000_HZ = 8000

    // Standard screening protocol: 500, 1000, 2000, 4000 Hz
    val DEFAULT_SCREENING_FREQUENCIES = listOf(FREQ_500_HZ, FREQ_1000_HZ, FREQ_2000_HZ, FREQ_4000_HZ)
}

/**
 * Environmental noise assessment categories.
 * Strict conservative policy: SUSPECT and INVALID both suspend active trials.
 */
enum class NoiseAssessment {
    VALID,          // Ambient sound is below threshold (quiet)
    SUSPECT,        // Marginal ambient noise or transient detected
    INVALID,        // Loud disturbance or speech detected; invalidates trial
    UNAVAILABLE     // Microphone sensor permission denied or hardware unavailable
}

/**
 * Android physical audio output route types.
 */
enum class AudioRouteType(val displayName: String, val isHeadphone: Boolean) {
    WIRED_HEADPHONES("Wired Headphones (3.5mm)", true),
    WIRED_HEADSET("Wired Headset w/ Mic", true),
    BLUETOOTH_A2DP("Bluetooth Audio (A2DP)", true),
    USB_HEADSET("USB-C Audio / Headset", true),
    BUILTIN_SPEAKER("Built-in Device Speaker", false),
    OTHER_UNSUPPORTED("Unsupported / Unknown Audio Output", false)
}

/**
 * Provenance of acoustic calibration.
 * Clearly isolates clinical calibration from provisional software fixtures.
 */
enum class CalibrationProvenance {
    UNCALIBRATED,       // Arbitrary hardware, uncalibrated output
    FIXTURE_DEFAULT,    // Software fixture for testing, not lab validated
    SIMULATED_PROFILE,  // Developer mock profile for algorithmic tests
    LAB_CALIBRATED      // Validated against artificial ear (IEC 60318-1/4)
}

/**
 * Details regarding hardware calibration state.
 */
data class CalibrationInfo(
    val deviceModel: String,
    val routeType: AudioRouteType,
    val provenance: CalibrationProvenance,
    val isOfficiallySupported: Boolean,
    val profileVersion: String = "v0.1-provisional",
    val notes: String = "No laboratory acoustic calibration has been performed. Outputs are digital dBFS only."
)

/**
 * Active audio route runtime descriptor.
 */
data class AudioRouteInfo(
    val routeType: AudioRouteType,
    val deviceName: String,
    val isStereoCapable: Boolean,
    val sampleRateHz: Int,
    val calibrationInfo: CalibrationInfo
)

/**
 * Individual stimulus trial outcome.
 */
enum class TrialOutcome {
    HEARD,
    NOT_HEARD,
    CONTAMINATED_BY_NOISE,
    INVALID_INTERRUPTED,
    UNANSWERED_TIMEOUT
}

/**
 * Immutable audit record of an individual presentation trial.
 */
data class TrialRecord(
    val trialNumber: Int,
    val ear: Ear,
    val frequencyHz: Int,
    val levelDb: Int,
    val outcome: TrialOutcome,
    val latencyMs: Long? = null,
    val ambientNoiseLevelDbFs: Double? = null,
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Estimated threshold for a specific ear and frequency.
 */
data class ThresholdResult(
    val ear: Ear,
    val frequencyHz: Int,
    val thresholdDb: Int,
    val validAscendingResponses: Int,
    val totalTrialsForTarget: Int,
    val method: String = "MODIFIED_HUGHSON_WESTLAKE_PROVISIONAL",
    val confidence: String = "UNVALIDATED_POC_ESTIMATE",
    val strategyVersion: String? = null,
    val bracketLowerDb: Int? = null,
    val bracketUpperDb: Int? = null,
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Quality audit flags attached to a screening session.
 */
enum class QualityFlag {
    SIMULATION_ONLY,
    UNCALIBRATED_HARDWARE,
    NO_TRUSTED_NOISE_SENSOR,
    ENVIRONMENTAL_NOISE_PAUSES_DETECTED,
    AUDIO_ROUTE_CHANGED_DURING_TEST,
    INCOMPLETE_TARGETS,
    EXCESSIVE_REVERSALS,
    BINARY_SEARCH_EXPERIMENTAL
}

/**
 * Provisional screening outcome classification per ear / overall.
 *
 * IMPORTANT: Because consumer devices lack clinical calibration (dBFS is digital attenuation,
 * not calibrated dB HL), any outcome is an unvalidated preliminary screening result.
 */
enum class ScreeningOutcomeClassification(val displayName: String, val clinicalDescription: String) {
    PASS("Pass (Preliminary)", "Responses detected within screening baseline levels across tested frequencies."),
    REFER("Referral Recommended", "Elevated response levels or non-responses detected at one or more frequencies. Formal audiometry advised."),
    INCONCLUSIVE("Inconclusive / Incomplete", "Testing was interrupted, noise limits were exceeded, or a valid threshold bracket could not be established.")
}

/**
 * Ear-specific screening summary.
 */
data class EarScreeningSummary(
    val ear: Ear,
    val classification: ScreeningOutcomeClassification,
    val thresholds: List<ThresholdResult>,
    val averageLevelDb: Double?,
    val isComplete: Boolean,
    val summaryNotes: String
)

/**
 * Comprehensive session-level screening outcome combining both ears.
 */
data class SessionScreeningOutcome(
    val overallClassification: ScreeningOutcomeClassification,
    val leftEarSummary: EarScreeningSummary,
    val rightEarSummary: EarScreeningSummary,
    val totalTrials: Int,
    val contaminatedTrials: Int,
    val isCalibrated: Boolean = false,
    val advisoryNotes: List<String> = emptyList()
)

/**
 * Comprehensive hearing screening session record for local audit and persistence.
 */
data class HearingSessionRecord(
    val sessionId: String,
    val startedAt: Long,
    val completedAt: Long? = null,
    val appVersion: String = "1.0.0-poc",
    val protocolVersion: String = "HW-2026-v1",
    val strategyType: String = "MODIFIED_HUGHSON_WESTLAKE",
    val deviceModel: String,
    val androidVersion: Int,
    val audioRoute: AudioRouteInfo,
    val isCompleted: Boolean = false,
    val qualityFlags: Set<QualityFlag> = emptySet(),
    val trials: List<TrialRecord> = emptyList(),
    val thresholdResults: List<ThresholdResult> = emptyList(),
    val noisePauseCount: Int = 0,
    val devicePauseCount: Int = 0,
    val screeningOutcome: SessionScreeningOutcome? = null
)
