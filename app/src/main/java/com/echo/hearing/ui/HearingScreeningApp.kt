package com.echo.hearing.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.automirrored.filled.CompareArrows
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.echo.hearing.data.UserProfile
import com.echo.hearing.domain.model.*
import com.echo.hearing.domain.statemachine.SessionState
import com.echo.hearing.domain.threshold.StrategyType
import com.echo.hearing.ui.components.*
import com.echo.hearing.ui.theme.*
import java.text.DateFormat
import java.util.Date
import java.util.Locale

private enum class TestSubScreen {
    MAIN,
    BRIEFING,
    HISTORY,
    COMPARE,
    REMINDERS,
    RECORD_DETAIL
}

@Composable
fun HearingScreeningApp(
    viewModel: HearingScreeningViewModel,
    profile: UserProfile = UserProfile(),
    initialTestPending: Boolean = false,
    launchInitialScreeningSignal: Int = 0,
    onUpdateProfile: (UserProfile) -> Unit = {},
    onRequestMicrophonePermission: () -> Unit = {},
    onImportToMonitor: () -> Unit = {},
    onSkipInitialTest: () -> Unit = {},
    onNavigateToHome: () -> Unit = {},
    openHistorySignal: Int = 0
) {
    val uiState by viewModel.uiState.collectAsState()
    var showSimPanel by remember { mutableStateOf(false) }
    var subScreen by remember {
        mutableStateOf(
            if (initialTestPending || launchInitialScreeningSignal > 0) TestSubScreen.BRIEFING
            else TestSubScreen.MAIN
        )
    }
    var selectedRecord by remember { mutableStateOf<HearingSessionRecord?>(null) }

    LaunchedEffect(Unit) {
        viewModel.setPauseOnEarTransition(true)
        viewModel.refreshSavedSessions()
    }

    LaunchedEffect(launchInitialScreeningSignal) {
        if (launchInitialScreeningSignal > 0) {
            if (uiState.sessionState == SessionState.NOT_STARTED || uiState.sessionState == SessionState.ONBOARDING_CONSENT) {
                viewModel.onConsentAgreed(true)
            }
            subScreen = TestSubScreen.BRIEFING
        }
    }

    LaunchedEffect(openHistorySignal) {
        if (openHistorySignal > 0) {
            viewModel.refreshSavedSessions()
            subScreen = TestSubScreen.HISTORY
        }
    }

    // Ensure consent is synced if user already completed onboarding
    LaunchedEffect(uiState.sessionState, profile.onboardingCompleted) {
        if (profile.onboardingCompleted &&
            (uiState.sessionState == SessionState.NOT_STARTED || uiState.sessionState == SessionState.ONBOARDING_CONSENT)
        ) {
            viewModel.onConsentAgreed(true)
        }
        if (uiState.sessionState == SessionState.DEVICE_READINESS) {
            onRequestMicrophonePermission()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(EchoBg)
    ) {
        when (subScreen) {
            TestSubScreen.HISTORY -> ScreeningHistoryScreen(
                sessions = uiState.savedSessions,
                onBack = { subScreen = TestSubScreen.MAIN },
                onCompare = { subScreen = TestSubScreen.COMPARE },
                onReminders = { subScreen = TestSubScreen.REMINDERS },
                onViewLatest = {
                    selectedRecord = uiState.savedSessions.firstOrNull()
                    subScreen = TestSubScreen.RECORD_DETAIL
                },
                onOpenRecord = {
                    selectedRecord = it
                    subScreen = TestSubScreen.RECORD_DETAIL
                },
                onDeleteRecord = { viewModel.deleteSession(it) }
            )

            TestSubScreen.COMPARE -> CompareScreeningsScreen(
                sessions = uiState.savedSessions,
                onBack = { subScreen = TestSubScreen.HISTORY }
            )

            TestSubScreen.REMINDERS -> ScreeningRemindersScreen(
                profile = profile,
                onUpdateProfile = onUpdateProfile,
                onBack = { subScreen = TestSubScreen.HISTORY }
            )

            TestSubScreen.RECORD_DETAIL -> RecordDetailScreen(
                record = selectedRecord ?: uiState.savedSessions.firstOrNull(),
                onBack = { subScreen = TestSubScreen.HISTORY }
            )

            TestSubScreen.BRIEFING -> ScreeningBriefingScreen(
                uiState = uiState,
                preferredName = profile.preferredName,
                isInitialBaseline = initialTestPending || (!profile.initialScreeningCompleted && uiState.savedSessions.isEmpty()),
                showSimPanel = showSimPanel,
                onToggleSimPanel = { showSimPanel = !showSimPanel },
                onBack = { subScreen = TestSubScreen.MAIN },
                onToggleSixFreq = { viewModel.setUseSixFrequencies(it) },
                onStartPractice = {
                    if (viewModel.uiState.value.sessionState != SessionState.TEST_PREP) {
                        viewModel.onDevicePrecheckContinue()
                    }
                    if (viewModel.uiState.value.sessionState == SessionState.TEST_PREP) {
                        subScreen = TestSubScreen.MAIN
                        viewModel.onStartPractice()
                    } else {
                        subScreen = TestSubScreen.MAIN
                    }
                },
                onSkipInitial = onSkipInitialTest,
                onBeginScreening = {
                    if (viewModel.uiState.value.sessionState == SessionState.NOT_STARTED ||
                        viewModel.uiState.value.sessionState == SessionState.ONBOARDING_CONSENT
                    ) {
                        viewModel.onConsentAgreed(true)
                    }
                    if (viewModel.uiState.value.sessionState != SessionState.TEST_PREP) {
                        viewModel.onDevicePrecheckContinue()
                    }
                    subScreen = TestSubScreen.MAIN
                    if (viewModel.uiState.value.sessionState == SessionState.TEST_PREP) {
                        viewModel.onStartScreening()
                    }
                }
            )

            TestSubScreen.MAIN -> {
                when (uiState.sessionState) {
                    SessionState.NOT_STARTED, SessionState.ONBOARDING_CONSENT -> {
                        OnboardingInlineNotice(
                            onAccept = { viewModel.onConsentAgreed(true) }
                        )
                    }

                    SessionState.DEVICE_READINESS,
                    SessionState.CALIBRATION_GATE,
                    SessionState.ENVIRONMENTAL_NOISE_CHECK,
                    SessionState.TEST_PREP -> {
                        DeviceSetupScreen(
                            uiState = uiState,
                            initialTestPending = initialTestPending,
                            showSimPanel = showSimPanel,
                            onToggleSimPanel = { showSimPanel = !showSimPanel },
                            onOpenHistory = {
                                viewModel.refreshSavedSessions()
                                subScreen = TestSubScreen.HISTORY
                            },
                            onRefreshDevice = { viewModel.refreshDeviceRoute() },
                            onSelectStrategy = { viewModel.selectStrategy(it) },
                            onToggleSixFreq = { viewModel.setUseSixFrequencies(it) },
                            onStartPractice = { viewModel.onStartPractice() },
                            onContinueToBriefing = {
                                if (uiState.sessionState != SessionState.TEST_PREP) {
                                    viewModel.onDevicePrecheckContinue()
                                }
                                if (viewModel.uiState.value.sessionState == SessionState.TEST_PREP ||
                                    (viewModel.uiState.value.isHeadphoneConnected &&
                                        viewModel.uiState.value.noiseReading.assessment == NoiseAssessment.VALID)
                                ) {
                                    subScreen = TestSubScreen.BRIEFING
                                }
                            }
                        )
                    }

                    SessionState.PRACTICE_PRESENTATION,
                    SessionState.PRACTICE_FEEDBACK -> {
                        PracticeScreen(
                            uiState = uiState,
                            onBack = { viewModel.onFinishPractice() },
                            onPracticeHeardClicked = { viewModel.onPracticeHeardClicked() },
                            onPracticeNotHeardClicked = { viewModel.onPracticeNotHeardClicked() },
                            onTryAgain = { viewModel.onStartPractice() },
                            onContinueToScreening = { viewModel.onStartScreening() }
                        )
                    }

                    SessionState.STIMULUS_PRESENTATION,
                    SessionState.WAITING_FOR_RESPONSE,
                    SessionState.TRIAL_VALIDATION,
                    SessionState.AUTOMATIC_PAUSE_NOISE,
                    SessionState.AUTOMATIC_PAUSE_DEVICE,
                    SessionState.RECOVERY_RECHECK,
                    SessionState.THRESHOLD_ESTIMATION -> {
                        if (uiState.earTransitionPending) {
                            LeftEarCompleteScreen(
                                onPauseClicked = { viewModel.onPauseRequested() },
                                onContinueToRightEar = { viewModel.continueToRightEar() }
                            )
                        } else {
                            ScreeningActiveScreen(
                                uiState = uiState,
                                showSimPanel = showSimPanel,
                                onToggleSimPanel = { showSimPanel = !showSimPanel },
                                onUserHeardClicked = { viewModel.onUserHeardClicked() },
                                onUserNotHeardClicked = { viewModel.onUserNotHeardClicked() },
                                onPauseClicked = { viewModel.onPauseRequested() },
                                onResumeClicked = { viewModel.onResumeRequested() },
                                onCancelClicked = { viewModel.onCancelRequested() }
                            )
                        }
                    }

                    SessionState.RESULTS, SessionState.COMPLETED -> {
                        ResultsScreen(
                            uiState = uiState,
                            isBaselineResult = profile.initialScreeningCompleted && uiState.savedSessions.size <= 1,
                            onImportToMonitor = onImportToMonitor,
                            onDoneHome = onNavigateToHome,
                            onOpenHistory = {
                                viewModel.refreshSavedSessions()
                                subScreen = TestSubScreen.HISTORY
                            },
                            onRestartClicked = { viewModel.onTryAgain() }
                        )
                    }

                    SessionState.CANCELLED, SessionState.ABORTED -> {
                        AbortedScreen(
                            uiState = uiState,
                            onTryAgain = { viewModel.onTryAgain() },
                            onResetConsent = { viewModel.onRestartRequested() }
                        )
                    }
                }
            }
        }

        if (showSimPanel) {
            SimulationDrawer(
                modifier = Modifier.align(Alignment.BottomCenter),
                isSimulationActive = uiState.isSimulationMode,
                onToggleSimulationMode = { viewModel.toggleSimulationMode() },
                onClose = { showSimPanel = false },
                onInjectNoise = { assessment -> viewModel.simulateNoiseSpike(assessment) },
                onDisconnectDevice = { viewModel.simulateDeviceDisconnect() }
            )
        }
    }
}

@Composable
private fun OnboardingInlineNotice(onAccept: () -> Unit) {
    var checked by remember { mutableStateOf(false) }
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Health Notice")
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            EchoCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.Info, contentDescription = null, tint = EchoPrimary)
                    Text("Important Health Notice", color = EchoNavy, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    "ECHO provides a preliminary screening using uncalibrated digital dBFS steps, not a substitute for professional audiological assessment.",
                    color = EchoTextMuted,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = checked, onCheckedChange = { checked = it })
                Text(
                    "I understand that ECHO provides a preliminary screening, not clinical audiometry.",
                    color = EchoNavy,
                    fontSize = 13.sp
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            EchoPrimaryButton(text = "Accept & Continue", icon = Icons.Default.Check, enabled = checked, onClick = onAccept)
        }
    }
}

@Composable
private fun DeviceSetupScreen(
    uiState: HearingScreeningUiState,
    initialTestPending: Boolean = false,
    showSimPanel: Boolean,
    onToggleSimPanel: () -> Unit,
    onOpenHistory: () -> Unit,
    onRefreshDevice: () -> Unit,
    onSelectStrategy: (StrategyType) -> Unit,
    onToggleSixFreq: (Boolean) -> Unit,
    onStartPractice: () -> Unit,
    onContinueToBriefing: () -> Unit
) {
    val route = uiState.audioRoute
    val isHeadphone = uiState.isHeadphoneConnected
    val noise = uiState.noiseReading
    val isNoiseDenied = noise.assessment == NoiseAssessment.UNAVAILABLE

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Device Setup",
            actions = {
                EchoStatusPill(
                    label = if (uiState.isSimulationMode) "SIM ACTIVE" else "DEV SIM",
                    icon = Icons.Outlined.Science,
                    containerColor = if (showSimPanel || uiState.isSimulationMode) AmberSoft else EchoSurfaceAlt,
                    borderColor = if (showSimPanel || uiState.isSimulationMode) Amber500 else EchoPillBorder,
                    contentColor = if (showSimPanel || uiState.isSimulationMode) Amber500 else EchoPrimary,
                    onClick = onToggleSimPanel
                )
                EchoStatusPill(
                    label = "History",
                    icon = Icons.Outlined.History,
                    onClick = onOpenHistory
                )
            }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = "Headphone Check",
                    color = EchoNavy,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Verify your headphones and ambient noise level before proceeding to preliminary screening.",
                    color = EchoTextMuted,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                )
            }

            if (initialTestPending) {
                EchoCard(borderColor = EchoPillBorder, containerColor = EchoSurfaceAlt) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.Hearing, contentDescription = null, tint = EchoPrimary)
                        Column {
                            Text("Initial Hearing Test Pending", color = EchoNavy, fontSize = 14.5.sp, fontWeight = FontWeight.Bold)
                            Text(
                                "Connect headphones in a quiet space to begin your post-login initial hearing input check.",
                                color = EchoTextMuted,
                                fontSize = 12.5.sp,
                                lineHeight = 18.sp
                            )
                        }
                    }
                }
            }

            // Status chips row matching Image 13
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                EchoChoiceChip(
                    label = "Connected",
                    selected = isHeadphone,
                    leadingIcon = if (isHeadphone) Icons.Default.Check else null,
                    onClick = onRefreshDevice
                )
                EchoChoiceChip(
                    label = "Disconnected",
                    selected = !isHeadphone,
                    onClick = onRefreshDevice
                )
                if (isNoiseDenied) {
                    EchoChoiceChip(
                        label = "Permission Denied",
                        selected = true,
                        onClick = onRefreshDevice
                    )
                }
            }

            // Warning banner if validation blocked
            uiState.pauseReason?.let { reason ->
                EchoCard(borderColor = Rose500, containerColor = RoseSoft) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.Warning, contentDescription = null, tint = Rose500)
                        Text(reason, color = EchoNavy, fontSize = 13.sp, lineHeight = 18.sp)
                    }
                }
            }

            // Connected Headphones Card (Image 13)
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(
                            imageVector = when {
                                !isHeadphone -> Icons.AutoMirrored.Filled.VolumeUp
                                route?.routeType == AudioRouteType.BLUETOOTH_A2DP -> Icons.Default.Bluetooth
                                else -> Icons.Outlined.Headphones
                            },
                            contentDescription = null,
                            tint = if (isHeadphone) EchoPrimary else Rose500,
                            modifier = Modifier.size(28.dp)
                        )
                        Column {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = if (isHeadphone) "Headphones Connected" else "Speaker Active",
                                    color = EchoNavy,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                EchoStatusPill(
                                    label = if (uiState.isSimulationMode) "Simulated" else "Live route",
                                    icon = Icons.Outlined.Info
                                )
                            }
                            Spacer(modifier = Modifier.height(2.dp))
                            Text(
                                text = route?.deviceName ?: "Checking audio route...",
                                color = if (isHeadphone) EchoTextMuted else Rose500,
                                fontSize = 13.sp
                            )
                            Text(
                                text = "Digital dBFS (uncalibrated consumer hardware)",
                                color = EchoTextLight,
                                fontSize = 11.5.sp
                            )
                        }
                    }
                    IconButton(onClick = onRefreshDevice) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh route", tint = EchoPrimary)
                    }
                }
            }

            // Live Ambient Noise Card (Current repo real feature)
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Ambient Noise Monitor", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                    val (badgeColor, badgeBg, badgeLabel) = when (noise.assessment) {
                        NoiseAssessment.VALID -> Triple(Emerald500, EmeraldSoft, "Quiet · Ready")
                        NoiseAssessment.SUSPECT -> Triple(Amber500, AmberSoft, "Moderate Noise")
                        NoiseAssessment.INVALID -> Triple(Rose500, RoseSoft, "Too Loud")
                        NoiseAssessment.UNAVAILABLE -> Triple(EchoTextMuted, EchoSurfaceAlt, "Mic Unavailable")
                    }
                    EchoStatusPill(
                        label = badgeLabel,
                        icon = null,
                        containerColor = badgeBg,
                        borderColor = badgeColor.copy(alpha = 0.5f),
                        contentColor = badgeColor
                    )
                }
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = if (noise.assessment == NoiseAssessment.UNAVAILABLE) {
                        "Noise Level: Unavailable (microphone permission required)"
                    } else {
                        String.format(Locale.US, "Noise Level: %.1f dBFS (RMS) · Built-in microphone", noise.levelDbFs)
                    },
                    color = EchoTextMuted,
                    fontSize = 13.sp
                )
            }

            // Algorithm & Frequency Strategy Card (Current repo feature)
            EchoCard {
                Text("Threshold Estimation Algorithm", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(10.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EchoChoiceChip(
                        label = "Hughson–Westlake",
                        selected = uiState.strategyType == StrategyType.MODIFIED_HUGHSON_WESTLAKE,
                        onClick = { onSelectStrategy(StrategyType.MODIFIED_HUGHSON_WESTLAKE) },
                        modifier = Modifier.weight(1f)
                    )
                    EchoChoiceChip(
                        label = "Binary Search (Exp)",
                        selected = uiState.strategyType == StrategyType.BINARY_SEARCH_REFINEMENT,
                        onClick = { onSelectStrategy(StrategyType.BINARY_SEARCH_REFINEMENT) },
                        modifier = Modifier.weight(1f)
                    )
                }
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = if (uiState.strategyType == StrategyType.MODIFIED_HUGHSON_WESTLAKE) {
                        "Clinical staircase: Down-10 / Up-5 dBFS requiring 2 ascending responses."
                    } else {
                        "Experimental bracket interval halving with discrete grid snapping."
                    },
                    color = EchoTextMuted,
                    fontSize = 12.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Extended 6-Frequency Protocol", color = EchoNavy, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                        Text(
                            if (uiState.useSixFrequencies) "250, 500, 1000, 2000, 4000, 8000 Hz"
                            else "Standard 500, 1000, 2000, 4000 Hz",
                            color = EchoTextMuted,
                            fontSize = 12.sp
                        )
                    }
                    Switch(
                        checked = uiState.useSixFrequencies,
                        onCheckedChange = onToggleSixFreq,
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = EchoPrimary)
                    )
                }
            }

            // Screening Checklist Card (Image 13)
            EchoCard {
                Text("Screening Checklist", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(12.dp))
                ChecklistItem("1", "Secure Fit", "Ensure both left and right earcups fit comfortably.")
                Spacer(modifier = Modifier.height(10.dp))
                ChecklistItem("2", "Quiet Environment", "Minimize background noise and conversations around you.")
                Spacer(modifier = Modifier.height(10.dp))
                ChecklistItem("3", "Moderate Volume", "Set your device volume to a comfortable, moderate level.")
            }

            if (uiState.sessionState == SessionState.TEST_PREP) {
                EchoOutlinedPillButton(
                    text = "Try Practice Tone (1000 Hz)",
                    icon = Icons.Default.PlayArrow,
                    onClick = onStartPractice
                )
            }

            EchoPrimaryButton(
                text = "Continue to Screening Briefing",
                icon = Icons.AutoMirrored.Filled.ArrowForward,
                onClick = onContinueToBriefing
            )
        }
    }
}

@Composable
private fun ChecklistItem(num: String, title: String, desc: String) {
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(EchoPrimarySoft),
            contentAlignment = Alignment.Center
        ) {
            Text(num, color = EchoPrimary, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = EchoNavy, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            Text(desc, color = EchoTextMuted, fontSize = 12.5.sp, lineHeight = 17.sp)
        }
    }
}

@Composable
private fun ScreeningBriefingScreen(
    uiState: HearingScreeningUiState,
    preferredName: String,
    isInitialBaseline: Boolean,
    showSimPanel: Boolean,
    onToggleSimPanel: () -> Unit,
    onBack: () -> Unit,
    onToggleSixFreq: (Boolean) -> Unit,
    onStartPractice: () -> Unit,
    onSkipInitial: () -> Unit,
    onBeginScreening: () -> Unit
) {
    val freqsText = if (uiState.useSixFrequencies) "6 test frequencies (250, 500, 1000, 2000, 4000, 8000 Hz)"
    else "4 core speech frequencies (500, 1000, 2000, 4000 Hz)"
    val readyForStart = uiState.isHeadphoneConnected && uiState.noiseReading.assessment == NoiseAssessment.VALID

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Initial Screening Briefing",
            onBack = onBack,
            actions = {
                EchoStatusPill(
                    label = if (uiState.isSimulationMode) "SIM ACTIVE" else "DEV SIM",
                    icon = Icons.Outlined.Science,
                    containerColor = if (showSimPanel || uiState.isSimulationMode) AmberSoft else EchoSurfaceAlt,
                    borderColor = if (showSimPanel || uiState.isSimulationMode) Amber500 else EchoPillBorder,
                    contentColor = if (showSimPanel || uiState.isSimulationMode) Amber500 else EchoPrimary,
                    onClick = onToggleSimPanel
                )
                EchoStatusPill(
                    label = if (isInitialBaseline) "Initial Input" else if (uiState.strategyType == StrategyType.MODIFIED_HUGHSON_WESTLAKE) "H-W" else "Binary"
                )
            }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (isInitialBaseline) {
                EchoCard(borderColor = EchoPillBorder, containerColor = EchoSurfaceAlt) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Outlined.PersonOutline, contentDescription = null, tint = EchoPrimary)
                        Text("Welcome, $preferredName", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    }
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "Complete this initial tone test to identify your baseline hearing input and automatically calibrate ECHO's Sound Monitor & EQ.",
                        color = EchoTextMuted,
                        fontSize = 13.5.sp,
                        lineHeight = 19.sp
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        EchoStatusPill(
                            label = if (uiState.isHeadphoneConnected) "Headphones Ready" else "Headphones Needed",
                            containerColor = if (uiState.isHeadphoneConnected) EmeraldSoft else RoseSoft,
                            borderColor = if (uiState.isHeadphoneConnected) Emerald500 else Rose500,
                            contentColor = if (uiState.isHeadphoneConnected) Emerald500 else Rose500
                        )
                        EchoStatusPill(
                            label = if (uiState.noiseReading.assessment == NoiseAssessment.VALID) "Room Quiet" else "Check Noise",
                            containerColor = if (uiState.noiseReading.assessment == NoiseAssessment.VALID) EmeraldSoft else AmberSoft,
                            borderColor = if (uiState.noiseReading.assessment == NoiseAssessment.VALID) Emerald500 else Amber500,
                            contentColor = if (uiState.noiseReading.assessment == NoiseAssessment.VALID) Emerald500 else Amber500
                        )
                    }
                }
            }

            EchoCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Outlined.Hearing, contentDescription = null, tint = EchoPrimary, modifier = Modifier.size(26.dp))
                    Text("Preliminary Tone Screening", color = EchoNavy, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "This sound check presents a sequence of $freqsText, beginning at reference 1000 Hz, to evaluate relative auditory response using ${uiState.strategyType.displayName}.",
                    color = EchoNavy,
                    fontSize = 14.5.sp,
                    lineHeight = 21.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    "Whenever you hear a tone pulse, tap \"I Hear It\". If you do not hear it after several pulses, tap \"Can't Hear It\" to test the next relative level.",
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 20.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Use full 6 frequencies (250–8000 Hz)", color = EchoNavy, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                    Switch(
                        checked = uiState.useSixFrequencies,
                        onCheckedChange = onToggleSixFreq,
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = EchoPrimary)
                    )
                }
            }

            EchoCard {
                Text("Screening Protocol", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(10.dp))
                val bullets = listOf(
                    "Left Ear tested first across all test frequencies.",
                    "Button-driven interstitial transition before Right Ear.",
                    "Right Ear tested second.",
                    "Continuous ambient noise gating pauses automatically on disturbance.",
                    "Initial audiogram & Monitor DSP reference saved upon completion."
                )
                bullets.forEach { bullet ->
                    Text("• $bullet", color = EchoNavy, fontSize = 13.5.sp, lineHeight = 21.sp)
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            if (readyForStart) {
                EchoOutlinedPillButton(
                    text = "Try Practice Tone (1000 Hz)",
                    icon = Icons.Default.PlayArrow,
                    onClick = onStartPractice
                )
            }

            EchoPrimaryButton(
                text = if (readyForStart) "Begin Initial Screening" else "Check Headphones & Noise Setup",
                icon = Icons.Default.PlayArrow,
                onClick = onBeginScreening
            )

            if (isInitialBaseline) {
                TextButton(
                    onClick = onSkipInitial,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                ) {
                    Text("Skip baseline for now", color = EchoTextMuted, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
private fun PracticeScreen(
    uiState: HearingScreeningUiState,
    onBack: () -> Unit,
    onPracticeHeardClicked: () -> Unit,
    onPracticeNotHeardClicked: () -> Unit,
    onTryAgain: () -> Unit,
    onContinueToScreening: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Practice Trial", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            EchoCard {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    EchoIconBadge(
                        icon = Icons.Filled.GraphicEq,
                        sizeDp = 76,
                        iconSizeDp = 36,
                        isCircle = true,
                        containerColor = if (uiState.practiceTonePlaying) EchoPrimarySoft else EchoSurfaceMuted,
                        tint = if (uiState.practiceTonePlaying) EchoPrimary else EchoTextMuted
                    )
                    Text("1000 Hz Demo Tone (Left Ear)", color = EchoNavy, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Text(
                        uiState.practiceFeedbackMessage ?: "Tap 'I Hear It' when you hear the tone.",
                        color = EchoTextMuted,
                        fontSize = 13.5.sp,
                        textAlign = TextAlign.Center
                    )

                    if (uiState.sessionState == SessionState.PRACTICE_PRESENTATION) {
                        EchoPrimaryButton(
                            text = "I Hear It",
                            icon = Icons.AutoMirrored.Filled.VolumeUp,
                            onClick = onPracticeHeardClicked
                        )
                        EchoOutlinedPillButton(
                            text = "Can't Hear It",
                            icon = Icons.AutoMirrored.Filled.VolumeOff,
                            onClick = onPracticeNotHeardClicked
                        )
                    } else {
                        EchoOutlinedPillButton(text = "Try Again", onClick = onTryAgain)
                        EchoPrimaryButton(
                            text = "Start Formal Screening",
                            enabled = uiState.practiceHeard == true,
                            onClick = onContinueToScreening
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ScreeningActiveScreen(
    uiState: HearingScreeningUiState,
    showSimPanel: Boolean,
    onToggleSimPanel: () -> Unit,
    onUserHeardClicked: () -> Unit,
    onUserNotHeardClicked: () -> Unit,
    onPauseClicked: () -> Unit,
    onResumeClicked: () -> Unit,
    onCancelClicked: () -> Unit
) {
    val progress = (uiState.completedTargets.toFloat() / uiState.totalTargets.coerceAtLeast(1)).coerceIn(0f, 1f)
    val progressPct = (progress * 100).toInt()
    val pulseTransition = rememberInfiniteTransition(label = "tonePulse")
    val pulseScale by pulseTransition.animateFloat(
        initialValue = 1f,
        targetValue = if (uiState.isTonePlaying) 1.08f else 1f,
        animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
        label = "scale"
    )

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Hearing Screening",
            actions = {
                TextButton(onClick = if (uiState.isNoisePaused) onResumeClicked else onPauseClicked) {
                    Icon(
                        imageVector = if (uiState.isNoisePaused) Icons.Default.PlayArrow else Icons.Default.Pause,
                        contentDescription = null,
                        tint = EchoPrimary,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        if (uiState.isNoisePaused) "Resume" else "Pause test",
                        color = EchoPrimary,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Ear + Algorithm + Mode chips row (Image 11)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                EchoStatusPill(
                    label = uiState.currentEar.displayName,
                    icon = Icons.Outlined.Hearing
                )
                EchoStatusPill(
                    label = if (uiState.strategyType == StrategyType.MODIFIED_HUGHSON_WESTLAKE) "Hughson–Westlake" else "Binary Search",
                    icon = Icons.Outlined.Info
                )
                Spacer(modifier = Modifier.weight(1f))
                EchoStatusPill(
                    label = "DEV SIM",
                    icon = Icons.Outlined.Science,
                    containerColor = if (showSimPanel || uiState.isSimulationMode) AmberSoft else EchoSurfaceAlt,
                    borderColor = if (showSimPanel || uiState.isSimulationMode) Amber500 else EchoPillBorder,
                    contentColor = if (showSimPanel || uiState.isSimulationMode) Amber500 else EchoPrimary,
                    onClick = onToggleSimPanel
                )
            }

            // Progress bar + label (Image 11)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(6.dp)
                        .clip(RoundedCornerShape(3.dp)),
                    color = EchoPrimary,
                    trackColor = EchoPrimarySoft
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        "Target ${uiState.completedTargets + 1} of ${uiState.totalTargets}",
                        color = EchoTextMuted,
                        fontSize = 12.sp
                    )
                    Text(
                        "Progress: $progressPct%",
                        color = EchoTextMuted,
                        fontSize = 12.sp
                    )
                }
            }

            if (uiState.isNoisePaused || uiState.sessionState == SessionState.AUTOMATIC_PAUSE_DEVICE) {
                EchoCard(borderColor = Amber500, containerColor = AmberSoft) {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Icon(Icons.Default.MicOff, contentDescription = null, tint = Amber500, modifier = Modifier.size(44.dp))
                        Text("Screening Paused", color = EchoNavy, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        Text(
                            uiState.pauseReason ?: "Disturbance detected. Waiting for quiet environment...",
                            color = EchoTextMuted,
                            fontSize = 14.sp,
                            textAlign = TextAlign.Center
                        )
                        if (uiState.sessionState == SessionState.AUTOMATIC_PAUSE_NOISE) {
                            Text(
                                "Auto-resuming in ${uiState.recoveryCountdownSeconds}s of quiet...",
                                color = Amber500,
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        } else {
                            EchoPrimaryButton(text = "Resume Test", onClick = onResumeClicked)
                        }
                    }
                }
            } else {
                // Center Frequency & Level Card (Image 11)
                EchoCard {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 18.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(86.dp)
                                .scale(pulseScale)
                                .clip(CircleShape)
                                .background(if (uiState.isTonePlaying) EchoPrimarySoft else EchoSurfaceMuted)
                                .border(2.dp, if (uiState.isTonePlaying) EchoPrimary else EchoBorder, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Filled.GraphicEq,
                                contentDescription = null,
                                tint = EchoPrimary,
                                modifier = Modifier.size(38.dp)
                            )
                        }
                        Text(
                            text = "${uiState.currentFrequencyHz} Hz",
                            color = EchoNavy,
                            fontSize = 30.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                        Text(
                            text = "Digital Level ${uiState.currentLevelDb} dBFS · Trial ${uiState.trialNumber + 1}",
                            color = EchoTextMuted,
                            fontSize = 15.sp
                        )
                        Text(
                            text = when {
                                uiState.isTonePlaying -> "Presenting tone stimulus..."
                                uiState.isWaitingForResponse -> "Did you hear the tone?"
                                else -> "Preparing next presentation..."
                            },
                            color = if (uiState.isTonePlaying || uiState.isWaitingForResponse) EchoPrimary else EchoTextLight,
                            fontSize = 12.5.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                // Response Buttons matching Image 11
                EchoPrimaryButton(
                    text = "I Hear It",
                    icon = Icons.AutoMirrored.Filled.VolumeUp,
                    enabled = uiState.isWaitingForResponse,
                    onClick = onUserHeardClicked
                )
                EchoOutlinedPillButton(
                    text = "Can't Hear It",
                    icon = Icons.AutoMirrored.Filled.VolumeOff,
                    enabled = uiState.isWaitingForResponse,
                    onClick = onUserNotHeardClicked
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            // Ambient Noise Status Strip + Cancel
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val color = when (uiState.noiseReading.assessment) {
                            NoiseAssessment.VALID -> Emerald500
                            NoiseAssessment.SUSPECT -> Amber500
                            NoiseAssessment.INVALID -> Rose500
                            NoiseAssessment.UNAVAILABLE -> EchoTextMuted
                        }
                        Box(modifier = Modifier.size(10.dp).clip(CircleShape).background(color))
                        Text(
                            String.format(Locale.US, "Ambient: %.1f dBFS (%s)", uiState.noiseReading.levelDbFs, uiState.noiseReading.assessment.name),
                            color = EchoTextMuted,
                            fontSize = 12.5.sp
                        )
                    }
                    TextButton(onClick = onCancelClicked) {
                        Text("Cancel", color = Rose500, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun LeftEarCompleteScreen(
    onPauseClicked: () -> Unit,
    onContinueToRightEar: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Hearing Screening",
            actions = {
                TextButton(onClick = onPauseClicked) {
                    Icon(Icons.Default.Pause, contentDescription = null, tint = EchoPrimary, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Pause test", color = EchoPrimary, fontWeight = FontWeight.Medium)
                }
            }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Headphones,
                contentDescription = null,
                tint = EchoPrimary,
                modifier = Modifier.size(56.dp)
            )
            Spacer(modifier = Modifier.height(20.dp))
            Text(
                text = "Left Ear Screening Complete",
                color = EchoNavy,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = "Please reposition your headphones or adjust fit to ensure a comfortable seal for your right ear.",
                color = EchoTextMuted,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
                lineHeight = 22.sp
            )
            Spacer(modifier = Modifier.height(28.dp))
            EchoPrimaryButton(
                text = "Continue to Right Ear",
                icon = Icons.AutoMirrored.Filled.ArrowForward,
                onClick = onContinueToRightEar
            )
        }
    }
}

@Composable
private fun ResultsScreen(
    uiState: HearingScreeningUiState,
    isBaselineResult: Boolean = false,
    onImportToMonitor: () -> Unit,
    onDoneHome: () -> Unit = {},
    onOpenHistory: () -> Unit,
    onRestartClicked: () -> Unit
) {
    val outcome = uiState.screeningOutcome
    val (bannerColor, bannerBg, bannerTitle, bannerDesc) = when (outcome?.overallClassification) {
        ScreeningOutcomeClassification.PASS -> Quad(
            Emerald500, EmeraldSoft, "PRELIMINARY SCREENING PASS",
            "Responses recorded within provisional screening levels across tested frequencies in both ears."
        )
        ScreeningOutcomeClassification.REFER -> Quad(
            Amber500, AmberSoft, "REFERRAL RECOMMENDED",
            "Elevated response levels or non-responses detected. Formal diagnostic audiometry recommended."
        )
        else -> Quad(
            EchoTextMuted, EchoSurfaceAlt, "SCREENING INCONCLUSIVE",
            "Incomplete target completion or test interruptions occurred during screening."
        )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Screening Results",
            actions = {
                EchoStatusPill(label = "History", icon = Icons.Outlined.History, onClick = onOpenHistory)
            }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard(borderColor = bannerColor, containerColor = bannerBg) {
                Text(bannerTitle, color = bannerColor, fontSize = 15.sp, fontWeight = FontWeight.ExtraBold)
                Spacer(modifier = Modifier.height(4.dp))
                Text(bannerDesc, color = EchoNavy, fontSize = 13.5.sp, lineHeight = 19.sp)
                Spacer(modifier = Modifier.height(6.dp))
                Text("Algorithm: ${uiState.strategyType.displayName}", color = EchoTextMuted, fontSize = 12.sp)
            }

            if (isBaselineResult) {
                EchoCard(borderColor = EchoPillBorder, containerColor = EchoSurfaceAlt) {
                    Text("Initial Hearing Input Captured", color = EchoPrimary, fontSize = 14.5.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Your post-login baseline thresholds have been saved and automatically applied to Live Monitor's Audiogram Reference.",
                        color = EchoNavy,
                        fontSize = 13.sp,
                        lineHeight = 18.sp
                    )
                }
            }

            AudiogramView(thresholdResults = uiState.thresholdResults)

            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                EarSummaryCard(
                    title = "LEFT EAR (AS)",
                    accent = EchoPrimary,
                    summary = outcome?.leftEarSummary?.classification?.displayName ?: "Complete",
                    results = uiState.thresholdResults.filter { it.ear == Ear.LEFT },
                    modifier = Modifier.weight(1f)
                )
                EarSummaryCard(
                    title = "RIGHT EAR (AD)",
                    accent = Rose500,
                    summary = outcome?.rightEarSummary?.classification?.displayName ?: "Complete",
                    results = uiState.thresholdResults.filter { it.ear == Ear.RIGHT },
                    modifier = Modifier.weight(1f)
                )
            }

            EchoCard {
                Text("Quality & Reliability Metrics", color = EchoNavy, fontSize = 14.5.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    "Total trials presented: ${uiState.trials.size}\n" +
                        "Contaminated trials retried: ${uiState.trials.count { it.outcome == TrialOutcome.CONTAMINATED_BY_NOISE }}\n" +
                        "Environmental pauses triggered: ${uiState.noisePauseCount}\n" +
                        "Quality flags: ${uiState.qualityFlags.joinToString { it.name }}",
                    color = EchoTextMuted,
                    fontSize = 12.5.sp,
                    lineHeight = 19.sp
                )
            }

            EchoCard(borderColor = Amber500.copy(alpha = 0.5f), containerColor = AmberSoft) {
                Text("Clinical Limitations", color = Amber500, fontSize = 14.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Values are uncalibrated software attenuation (dBFS), not clinical dB HL. Consult an audiologist for diagnostic evaluation.",
                    color = EchoNavy,
                    fontSize = 12.5.sp,
                    lineHeight = 18.sp
                )
            }

            EchoOutlinedPillButton(
                text = "Import to Monitor Reference",
                icon = Icons.Outlined.Download,
                onClick = onImportToMonitor
            )
            EchoPrimaryButton(
                text = if (isBaselineResult) "Done · Open Home Dashboard" else "Restart Screening",
                icon = if (isBaselineResult) Icons.Default.Check else Icons.Default.Refresh,
                onClick = if (isBaselineResult) onDoneHome else onRestartClicked
            )
            if (isBaselineResult) {
                EchoOutlinedPillButton(
                    text = "Retake Screening",
                    icon = Icons.Default.Refresh,
                    onClick = onRestartClicked
                )
            }
        }
    }
}

@Composable
private fun EarSummaryCard(
    title: String,
    accent: Color,
    summary: String,
    results: List<ThresholdResult>,
    modifier: Modifier = Modifier
) {
    EchoCard(modifier = modifier) {
        Text(title, color = accent, fontSize = 12.5.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(3.dp))
        Text(summary, color = EchoNavy, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(6.dp))
        results.forEach { t ->
            Text("${t.frequencyHz}Hz: ${t.thresholdDb} dBFS", color = EchoTextMuted, fontSize = 11.5.sp)
        }
    }
}

@Composable
private fun AbortedScreen(
    uiState: HearingScreeningUiState,
    onTryAgain: () -> Unit,
    onResetConsent: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Hearing Screening")
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(Icons.Default.Cancel, contentDescription = null, tint = Rose500, modifier = Modifier.size(60.dp))
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = if (uiState.sessionState == SessionState.CANCELLED) "Screening Cancelled" else "Precheck Incomplete",
                color = EchoNavy,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = uiState.cancelReason ?: uiState.pauseReason
                    ?: "The screening session could not proceed because device or noise requirements were not met.",
                color = EchoTextMuted,
                fontSize = 14.sp,
                textAlign = TextAlign.Center,
                lineHeight = 20.sp
            )
            Spacer(modifier = Modifier.height(24.dp))
            EchoPrimaryButton(text = "Try Again (Return to Setup)", onClick = onTryAgain)
            Spacer(modifier = Modifier.height(10.dp))
            TextButton(onClick = onResetConsent) {
                Text("Restart from Beginning (Re-read Terms)", color = EchoTextMuted, fontSize = 13.sp)
            }
        }
    }
}

// ---- Screening History & Sub-Screens (Image 2) ----

@Composable
private fun ScreeningHistoryScreen(
    sessions: List<HearingSessionRecord>,
    onBack: () -> Unit,
    onCompare: () -> Unit,
    onReminders: () -> Unit,
    onViewLatest: () -> Unit,
    onOpenRecord: (HearingSessionRecord) -> Unit,
    onDeleteRecord: (String) -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Screening History",
            onBack = onBack,
            actions = {
                EchoStatusPill(label = if (sessions.isEmpty()) "Sample data" else "${sessions.size} saved")
            }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Previous Screenings", color = EchoNavy, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    EchoStatusPill(label = if (sessions.isEmpty()) "Sample data" else "Local JSON")
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Track preliminary tone response estimates over time.",
                    color = EchoTextMuted,
                    fontSize = 14.sp
                )
            }

            EchoOutlinedPillButton(
                text = "Compare Screenings",
                icon = Icons.AutoMirrored.Filled.CompareArrows,
                onClick = onCompare
            )
            EchoOutlinedPillButton(
                text = "Screening Reminders",
                icon = Icons.Outlined.Alarm,
                onClick = onReminders
            )
            EchoOutlinedPillButton(
                text = if (sessions.isNotEmpty()) "View Latest Record" else "View Latest Record (Sample #1)",
                icon = Icons.Outlined.Description,
                onClick = onViewLatest
            )

            if (sessions.isNotEmpty()) {
                Text("Saved Screening Sessions", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 6.dp))
                sessions.forEach { rec ->
                    val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(rec.startedAt))
                    val label = rec.screeningOutcome?.overallClassification?.displayName ?: if (rec.isCompleted) "Completed" else "Cancelled"
                    EchoCard(modifier = Modifier.clickable { onOpenRecord(rec) }) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(label, color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                                Text("$date · ${rec.strategyType.replace('_', ' ')}", color = EchoTextMuted, fontSize = 12.sp)
                                Text("${rec.thresholdResults.size} thresholds · ${rec.trials.size} trials", color = EchoTextLight, fontSize = 12.sp)
                            }
                            IconButton(onClick = { onDeleteRecord(rec.sessionId) }) {
                                Icon(Icons.Outlined.Delete, contentDescription = "Delete", tint = EchoTextMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CompareScreeningsScreen(
    sessions: List<HearingSessionRecord>,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Compare Screenings",
            onBack = onBack,
            actions = { if (sessions.size < 2) EchoStatusPill(label = "Sample data") }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            if (sessions.size >= 2) {
                val latest = sessions[0]
                val prev = sessions[1]
                EchoCard {
                    Text("Latest vs Previous Screening", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(8.dp))
                    val latestMap = latest.thresholdResults.associateBy { it.ear to it.frequencyHz }
                    val prevMap = prev.thresholdResults.associateBy { it.ear to it.frequencyHz }
                    latestMap.keys.forEach { key ->
                        val a = latestMap[key]?.thresholdDb
                        val b = prevMap[key]?.thresholdDb
                        val diff = if (a != null && b != null) a - b else null
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("${key.first.clinicalCode} ${key.second} Hz", color = EchoNavy, fontSize = 13.5.sp)
                            Text(
                                "${b ?: "—"} → ${a ?: "—"} dBFS ${if (diff != null) "(${if (diff >= 0) "+$diff" else "$diff"})" else ""}",
                                color = EchoPrimary,
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
            } else {
                EchoCard {
                    Text("Sample Comparison", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "Complete at least 2 screenings to compare your real threshold results side-by-side. Sample reference shown below:",
                        color = EchoTextMuted,
                        fontSize = 13.sp
                    )
                    Spacer(modifier = Modifier.height(10.dp))
                    listOf(500, 1000, 2000, 4000).forEach { hz ->
                        Row(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("AS/AD $hz Hz", color = EchoNavy, fontSize = 13.5.sp)
                            Text("20 → 20 dBFS (0 dB)", color = EchoPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScreeningRemindersScreen(
    profile: UserProfile,
    onUpdateProfile: (UserProfile) -> Unit,
    onBack: () -> Unit
) {
    val options = listOf("Weekly", "Monthly", "Quarterly", "Off")
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Screening Reminders", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Reminder Cadence", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                Text("Choose how often ECHO reminds you to take a routine sound check.", color = EchoTextMuted, fontSize = 13.5.sp)
                Spacer(modifier = Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    options.forEach { opt ->
                        EchoChoiceChip(
                            label = opt,
                            selected = profile.reminderFrequency == opt,
                            onClick = { onUpdateProfile(profile.copy(reminderFrequency = opt)) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RecordDetailScreen(
    record: HearingSessionRecord?,
    onBack: () -> Unit
) {
    val results = record?.thresholdResults ?: listOf(
        ThresholdResult(Ear.LEFT, 500, 20, 2, 4),
        ThresholdResult(Ear.LEFT, 1000, 15, 2, 4),
        ThresholdResult(Ear.LEFT, 2000, 20, 2, 4),
        ThresholdResult(Ear.LEFT, 4000, 25, 2, 5),
        ThresholdResult(Ear.RIGHT, 500, 20, 2, 4),
        ThresholdResult(Ear.RIGHT, 1000, 20, 2, 4),
        ThresholdResult(Ear.RIGHT, 2000, 25, 2, 4),
        ThresholdResult(Ear.RIGHT, 4000, 25, 2, 5)
    )
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = if (record != null) "Screening Record" else "Sample Record #1",
            onBack = onBack,
            actions = { if (record == null) EchoStatusPill(label = "Sample data") }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            AudiogramView(thresholdResults = results)
            EchoCard {
                Text(
                    if (record != null) "Session Summary (${record.strategyType})" else "Sample Session Summary",
                    color = EchoNavy,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(6.dp))
                results.forEach { r ->
                    Text("${r.ear.clinicalCode} · ${r.frequencyHz} Hz: ${r.thresholdDb} dBFS", color = EchoTextMuted, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
fun SimulationDrawer(
    modifier: Modifier = Modifier,
    isSimulationActive: Boolean,
    onToggleSimulationMode: () -> Unit,
    onClose: () -> Unit,
    onInjectNoise: (NoiseAssessment) -> Unit,
    onDisconnectDevice: () -> Unit
) {
    EchoCard(
        modifier = modifier.padding(16.dp),
        borderColor = if (isSimulationActive) Amber500 else EchoBorder
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Developer Test Harness",
                    color = if (isSimulationActive) Amber500 else EchoNavy,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    if (isSimulationActive) "[ACTIVE]" else "[OFF]",
                    color = if (isSimulationActive) Amber500 else EchoTextMuted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold
                )
            }
            IconButton(onClick = onClose) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = EchoTextMuted)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "Override Physical Hardware with Synthetic Data",
                color = EchoTextMuted,
                fontSize = 12.sp,
                modifier = Modifier.weight(1f)
            )
            Switch(checked = isSimulationActive, onCheckedChange = { onToggleSimulationMode() })
        }

        Spacer(modifier = Modifier.height(8.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = { onInjectNoise(NoiseAssessment.INVALID) },
                enabled = isSimulationActive,
                colors = ButtonDefaults.buttonColors(containerColor = Rose500),
                modifier = Modifier.weight(1f)
            ) { Text("Inject Noise", fontSize = 11.sp) }
            Button(
                onClick = { onInjectNoise(NoiseAssessment.VALID) },
                enabled = isSimulationActive,
                colors = ButtonDefaults.buttonColors(containerColor = Emerald500),
                modifier = Modifier.weight(1f)
            ) { Text("Clear Noise", fontSize = 11.sp) }
            Button(
                onClick = onDisconnectDevice,
                enabled = isSimulationActive,
                colors = ButtonDefaults.buttonColors(containerColor = EchoPrimary),
                modifier = Modifier.weight(1f)
            ) { Text("Unplug", fontSize = 11.sp) }
        }
    }
}

private data class Quad<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
