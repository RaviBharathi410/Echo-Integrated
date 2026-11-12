package com.echo.hearing.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.automirrored.outlined.Logout
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.echo.hearing.data.UserProfile
import com.echo.hearing.domain.model.HearingSessionRecord
import com.echo.hearing.monitor.MonitorUiState
import com.echo.hearing.ui.components.*
import com.echo.hearing.ui.theme.*
import com.google.gson.GsonBuilder
import java.text.DateFormat
import java.util.Date

// ---- HOME TAB ----

@Composable
fun HomeScreen(
    profile: UserProfile,
    screeningState: HearingScreeningUiState,
    monitorState: MonitorUiState,
    initialTestPending: Boolean = false,
    onStartInitialTest: () -> Unit = {},
    onNavigateToTest: () -> Unit,
    onNavigateToMonitor: () -> Unit,
    onNavigateToReports: () -> Unit,
    onOpenScreeningHistory: () -> Unit
) {
    val latest = screeningState.savedSessions.firstOrNull()
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(EchoBg)
    ) {
        EchoTopBar(
            title = "ECHO",
            actions = {
                EchoStatusPill(
                    label = if (monitorState.running) "Monitor Live" else "Ready",
                    icon = if (monitorState.running) Icons.Filled.GraphicEq else Icons.Outlined.CheckCircle,
                    containerColor = if (monitorState.running) EmeraldSoft else EchoSurfaceAlt,
                    borderColor = if (monitorState.running) Emerald500 else EchoPillBorder,
                    contentColor = if (monitorState.running) Emerald500 else EchoPrimary
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
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = "Welcome back, ${profile.preferredName}",
                    color = EchoNavy,
                    fontSize = 23.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Personalized hearing clarity and daily listening monitoring.",
                    color = EchoTextMuted,
                    fontSize = 14.sp
                )
            }

            if (initialTestPending) {
                EchoCard(borderColor = EchoPillBorder, containerColor = EchoSurfaceAlt) {
                    Text("Initial Hearing Input Pending", color = EchoPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        "Take your initial pure-tone screening to capture your baseline hearing input and calibrate ECHO.",
                        color = EchoNavy,
                        fontSize = 13.5.sp,
                        lineHeight = 19.sp
                    )
                    Spacer(modifier = Modifier.height(10.dp))
                    EchoPrimaryButton(
                        text = "Start Initial Hearing Test",
                        icon = Icons.Outlined.Hearing,
                        onClick = onStartInitialTest
                    )
                }
            }

            // Status Overview Card
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("System Status", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                    EchoStatusPill(
                        label = if (screeningState.isHeadphoneConnected) "Headphones Ready" else "Check Headphones",
                        icon = Icons.Outlined.Headphones
                    )
                }
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    text = if (latest != null) {
                        val date = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(latest.startedAt))
                        "Latest screening ($date): ${latest.screeningOutcome?.overallClassification?.displayName ?: "Saved"} (${latest.thresholdResults.size} thresholds)"
                    } else {
                        "No screening saved yet. Run a preliminary pure-tone check to establish your baseline."
                    },
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 19.sp
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "Live Audio Monitor: ${if (monitorState.running) "Active · ${if (monitorState.processed) "ECHO DSP On" else "Baseline"}" else "Stopped"}",
                    color = if (monitorState.running) Emerald500 else EchoTextMuted,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            // Three core cards matching Welcome screen
            HomeActionCard(
                icon = Icons.Outlined.Hearing,
                title = "Preliminary Sound Screening",
                description = "Modified Hughson–Westlake or Binary Search screening with ambient noise gating and audiogram.",
                buttonText = "Open Screening",
                onClick = onNavigateToTest
            )

            HomeActionCard(
                icon = Icons.Outlined.GraphicEq,
                title = "Live Audio Monitor & DSP",
                description = "Real-time Oboe full-duplex monitor with noise gate, adaptive denoiser, 4-band compression & 6-band EQ.",
                buttonText = "Open Sound Monitor",
                onClick = onNavigateToMonitor
            )

            HomeActionCard(
                icon = Icons.Outlined.Assessment,
                title = "Listening Reports & History",
                description = "Weekly exposure summaries, speech clarity A/B scores, and saved screening comparisons.",
                buttonText = "View Reports",
                onClick = onNavigateToReports
            )

            EchoOutlinedPillButton(
                text = "View Screening History (${screeningState.savedSessions.size})",
                icon = Icons.Outlined.History,
                onClick = onOpenScreeningHistory
            )
        }
    }
}

@Composable
private fun HomeActionCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String,
    buttonText: String,
    onClick: () -> Unit
) {
    EchoCard {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            EchoIconBadge(icon = icon, sizeDp = 44, iconSizeDp = 22)
            Column(modifier = Modifier.weight(1f)) {
                Text(title, color = EchoNavy, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(2.dp))
                Text(description, color = EchoTextMuted, fontSize = 12.5.sp, lineHeight = 17.sp)
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        EchoPrimaryButton(text = buttonText, onClick = onClick)
    }
}

// ---- REPORTS TAB (Image 1) ----

private enum class ReportsSubScreen {
    MAIN,
    WEEKLY_REPORT,
    EXPOSURE_TRENDS,
    INSIGHTS_TIPS,
    HISTORICAL_DATA
}

@Composable
fun ReportsScreen(
    screeningState: HearingScreeningUiState,
    monitorState: MonitorUiState,
    onOpenScreeningHistory: () -> Unit
) {
    var subScreen by remember { mutableStateOf(ReportsSubScreen.MAIN) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(EchoBg)
    ) {
        when (subScreen) {
            ReportsSubScreen.MAIN -> ReportsMainScreen(
                screeningState = screeningState,
                monitorState = monitorState,
                onWeeklyReport = { subScreen = ReportsSubScreen.WEEKLY_REPORT },
                onExposureTrends = { subScreen = ReportsSubScreen.EXPOSURE_TRENDS },
                onInsights = { subScreen = ReportsSubScreen.INSIGHTS_TIPS },
                onHistoricalData = { subScreen = ReportsSubScreen.HISTORICAL_DATA }
            )

            ReportsSubScreen.WEEKLY_REPORT -> WeeklyReportSubScreen(
                screeningCount = screeningState.savedSessions.size,
                clarityCount = monitorState.trials.size,
                onBack = { subScreen = ReportsSubScreen.MAIN }
            )

            ReportsSubScreen.EXPOSURE_TRENDS -> ExposureTrendsSubScreen(
                onBack = { subScreen = ReportsSubScreen.MAIN }
            )

            ReportsSubScreen.INSIGHTS_TIPS -> InsightsTipsSubScreen(
                onBack = { subScreen = ReportsSubScreen.MAIN }
            )

            ReportsSubScreen.HISTORICAL_DATA -> HistoricalDataSubScreen(
                sessions = screeningState.savedSessions,
                clarityTrials = monitorState.trials,
                onOpenScreeningHistory = onOpenScreeningHistory,
                onBack = { subScreen = ReportsSubScreen.MAIN }
            )
        }
    }
}

@Composable
private fun ReportsMainScreen(
    screeningState: HearingScreeningUiState,
    monitorState: MonitorUiState,
    onWeeklyReport: () -> Unit,
    onExposureTrends: () -> Unit,
    onInsights: () -> Unit,
    onHistoricalData: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Listening Reports",
            actions = { EchoStatusPill(label = "Sample data") }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Weekly Summary Card (Image 1)
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Weekly Summary", color = EchoNavy, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    EchoStatusPill(label = "Sample data")
                }
                Spacer(modifier = Modifier.height(10.dp))
                Text(
                    text = "Your listening habits remained 100% within recommended sound limits this week.",
                    color = EchoTextMuted,
                    fontSize = 14.5.sp,
                    lineHeight = 21.sp
                )
                if (screeningState.savedSessions.isNotEmpty() || monitorState.trials.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Saved on device: ${screeningState.savedSessions.size} screening session(s) · ${monitorState.trials.size} speech clarity trial(s).",
                        color = EchoPrimary,
                        fontSize = 12.5.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            // Four signature pill buttons from Image 1
            EchoOutlinedPillButton(
                text = "Weekly Report",
                icon = Icons.Outlined.ViewWeek,
                onClick = onWeeklyReport
            )
            EchoOutlinedPillButton(
                text = "Exposure Trends",
                icon = Icons.AutoMirrored.Filled.TrendingUp,
                onClick = onExposureTrends
            )
            EchoOutlinedPillButton(
                text = "Insights & Tips",
                icon = Icons.Outlined.Lightbulb,
                onClick = onInsights
            )
            EchoOutlinedPillButton(
                text = "Historical Data",
                icon = Icons.Outlined.History,
                onClick = onHistoricalData
            )
        }
    }
}

@Composable
private fun WeeklyReportSubScreen(
    screeningCount: Int,
    clarityCount: Int,
    onBack: () -> Unit
) {
    val days = listOf("Mon" to 0.35f, "Tue" to 0.50f, "Wed" to 0.42f, "Thu" to 0.60f, "Fri" to 0.48f, "Sat" to 0.30f, "Sun" to 0.25f)
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Weekly Report", onBack = onBack, actions = { EchoStatusPill(label = "Sample data") })
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Weekly Safe Listening Budget (Sample)", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.Bottom
                ) {
                    days.forEach { (day, frac) ->
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(
                                modifier = Modifier
                                    .width(22.dp)
                                    .height((90 * frac).dp)
                                    .clip(RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp))
                                    .background(EchoPrimary)
                            )
                            Spacer(modifier = Modifier.height(6.dp))
                            Text(day, color = EchoTextMuted, fontSize = 11.sp)
                        }
                    }
                }
            }
            EchoCard {
                Text("Recorded Activity on Device", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                Text("• Completed / saved screening records: $screeningCount", color = EchoTextMuted, fontSize = 13.5.sp)
                Text("• Logged Speech Clarity A/B trials: $clarityCount", color = EchoTextMuted, fontSize = 13.5.sp)
            }
        }
    }
}

@Composable
private fun ExposureTrendsSubScreen(onBack: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Exposure Trends", onBack = onBack, actions = { EchoStatusPill(label = "Sample data") })
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Ambient Level Distribution (Sample)", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(10.dp))
                TrendBar("Quiet (< -45 dBFS)", 0.65f, Emerald500)
                Spacer(modifier = Modifier.height(8.dp))
                TrendBar("Moderate (-45 to -32 dBFS)", 0.28f, EchoPrimary)
                Spacer(modifier = Modifier.height(8.dp))
                TrendBar("Elevated (> -32 dBFS)", 0.07f, Amber500)
            }
        }
    }
}

@Composable
private fun TrendBar(label: String, fraction: Float, color: Color) {
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, color = EchoNavy, fontSize = 13.sp)
            Text("${(fraction * 100).toInt()}%", color = color, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(modifier = Modifier.height(4.dp))
        LinearProgressIndicator(
            progress = { fraction },
            modifier = Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)),
            color = color,
            trackColor = EchoPrimarySoft
        )
    }
}

@Composable
private fun InsightsTipsSubScreen(onBack: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Insights & Tips", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            val tips = listOf(
                "Quiet Screening Room" to "Run preliminary tone checks in a room with ambient noise below -45 dBFS so the noise gate stays green.",
                "Conservative Monitor Trim" to "Keep Live Monitor volume trim low (starting around 15%) and never exceed comfortable listening levels.",
                "Matched A/B Word Lists" to "When logging Speech Clarity A/B trials, use unseen word lists of the same length in Processed vs Baseline mode."
            )
            tips.forEach { (t, d) ->
                EchoCard {
                    Text(t, color = EchoNavy, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(d, color = EchoTextMuted, fontSize = 13.5.sp, lineHeight = 19.sp)
                }
            }
        }
    }
}

@Composable
private fun HistoricalDataSubScreen(
    sessions: List<HearingSessionRecord>,
    clarityTrials: List<String>,
    onOpenScreeningHistory: () -> Unit,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Historical Data", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Screening Sessions (${sessions.size})", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                if (sessions.isEmpty()) {
                    Text("No saved screenings yet.", color = EchoTextMuted, fontSize = 13.sp)
                } else {
                    sessions.take(5).forEach { rec ->
                        val date = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(rec.startedAt))
                        Text("• $date — ${rec.screeningOutcome?.overallClassification?.displayName ?: "Saved"}", color = EchoTextMuted, fontSize = 13.sp)
                    }
                }
                Spacer(modifier = Modifier.height(10.dp))
                EchoOutlinedPillButton(text = "Open Full Screening History", onClick = onOpenScreeningHistory)
            }

            EchoCard {
                Text("Speech Clarity A/B Trials (${clarityTrials.size})", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                if (clarityTrials.isEmpty()) {
                    Text("No speech clarity logs recorded yet.", color = EchoTextMuted, fontSize = 13.sp)
                } else {
                    clarityTrials.take(10).forEach {
                        Text("• $it", color = EchoTextMuted, fontSize = 12.5.sp, lineHeight = 19.sp)
                    }
                }
            }
        }
    }
}

// ---- PROFILE TAB (Image 10) ----

private enum class ProfileSubScreen {
    MAIN,
    EDIT_PROFILE,
    CONNECTED_DEVICES,
    NOTIFICATIONS,
    PRIVACY_DATA,
    EXPORT_DATA,
    ABOUT_ECHO,
    HELP_FAQ
}

@Composable
fun ProfileScreen(
    profile: UserProfile,
    onUpdateProfile: (UserProfile) -> Unit,
    screeningState: HearingScreeningUiState,
    monitorState: MonitorUiState,
    onRefreshDeviceRoute: () -> Unit,
    onRestartOnboarding: () -> Unit,
    onSignOut: () -> Unit = {}
) {
    var subScreen by remember { mutableStateOf(ProfileSubScreen.MAIN) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(EchoBg)
    ) {
        when (subScreen) {
            ProfileSubScreen.MAIN -> ProfileMainScreen(
                profile = profile,
                onEditProfile = { subScreen = ProfileSubScreen.EDIT_PROFILE },
                onConnectedDevices = { subScreen = ProfileSubScreen.CONNECTED_DEVICES },
                onNotifications = { subScreen = ProfileSubScreen.NOTIFICATIONS },
                onPrivacy = { subScreen = ProfileSubScreen.PRIVACY_DATA },
                onExport = { subScreen = ProfileSubScreen.EXPORT_DATA },
                onAbout = { subScreen = ProfileSubScreen.ABOUT_ECHO },
                onHelp = { subScreen = ProfileSubScreen.HELP_FAQ },
                onSignOut = onSignOut
            )

            ProfileSubScreen.EDIT_PROFILE -> EditProfileSubScreen(
                profile = profile,
                onSave = {
                    onUpdateProfile(it)
                    subScreen = ProfileSubScreen.MAIN
                },
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )

            ProfileSubScreen.CONNECTED_DEVICES -> ConnectedDevicesSubScreen(
                screeningState = screeningState,
                monitorState = monitorState,
                onRefresh = onRefreshDeviceRoute,
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )

            ProfileSubScreen.NOTIFICATIONS -> NotificationsSubScreen(
                profile = profile,
                onUpdateProfile = onUpdateProfile,
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )

            ProfileSubScreen.PRIVACY_DATA -> PrivacyDataSubScreen(
                onRestartOnboarding = onRestartOnboarding,
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )

            ProfileSubScreen.EXPORT_DATA -> ExportDataSubScreen(
                profile = profile,
                sessions = screeningState.savedSessions,
                clarityTrials = monitorState.trials,
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )

            ProfileSubScreen.ABOUT_ECHO -> AboutEchoSubScreen(
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )

            ProfileSubScreen.HELP_FAQ -> HelpFaqSubScreen(
                onBack = { subScreen = ProfileSubScreen.MAIN }
            )
        }
    }
}

@Composable
private fun ProfileMainScreen(
    profile: UserProfile,
    onEditProfile: () -> Unit,
    onConnectedDevices: () -> Unit,
    onNotifications: () -> Unit,
    onPrivacy: () -> Unit,
    onExport: () -> Unit,
    onAbout: () -> Unit,
    onHelp: () -> Unit,
    onSignOut: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Profile & Settings")

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Profile Card (Image 10)
            EchoCard(modifier = Modifier.clickable(onClick = onEditProfile)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    EchoIconBadge(
                        icon = Icons.Filled.Person,
                        sizeDp = 58,
                        iconSizeDp = 30,
                        isCircle = true,
                        containerColor = EchoPrimarySoft,
                        tint = EchoPrimary
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = profile.preferredName,
                            color = EchoNavy,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = "Standard Listening Profile",
                            color = EchoTextMuted,
                            fontSize = 13.5.sp
                        )
                        Text(
                            text = "${profile.ageRange} · ${profile.preferredLanguage} · ${profile.accountMode}",
                            color = EchoTextLight,
                            fontSize = 12.sp
                        )
                    }
                    Icon(Icons.Outlined.Edit, contentDescription = "Edit Profile", tint = EchoPrimary)
                }
            }

            // Six signature pill buttons from Image 10
            EchoOutlinedPillButton(
                text = "Connected Devices",
                icon = Icons.Outlined.Headphones,
                onClick = onConnectedDevices
            )
            EchoOutlinedPillButton(
                text = "Notifications",
                icon = Icons.Outlined.Notifications,
                onClick = onNotifications
            )
            EchoOutlinedPillButton(
                text = "Privacy & Data",
                icon = Icons.Outlined.Lock,
                onClick = onPrivacy
            )
            EchoOutlinedPillButton(
                text = "Export Data",
                icon = Icons.Outlined.Download,
                onClick = onExport
            )
            EchoOutlinedPillButton(
                text = "About ECHO",
                icon = Icons.Outlined.Info,
                onClick = onAbout
            )
            EchoOutlinedPillButton(
                text = "Help & FAQ",
                icon = Icons.AutoMirrored.Filled.HelpOutline,
                onClick = onHelp
            )
            EchoOutlinedPillButton(
                text = "Sign Out / Switch Account",
                icon = Icons.AutoMirrored.Outlined.Logout,
                onClick = onSignOut
            )
        }
    }
}

@Composable
private fun EditProfileSubScreen(
    profile: UserProfile,
    onSave: (UserProfile) -> Unit,
    onBack: () -> Unit
) {
    var name by remember { mutableStateOf(profile.preferredName) }
    var ageRange by remember { mutableStateOf(profile.ageRange) }
    var language by remember { mutableStateOf(profile.preferredLanguage) }

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Edit Profile", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Preferred Name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Text("Age Range", color = EchoNavy, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("18–35", "36–50", "51–65", "65+").forEach { opt ->
                    EchoChoiceChip(label = opt, selected = ageRange == opt, onClick = { ageRange = opt })
                }
            }
            Text("Preferred Language", color = EchoNavy, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("English", "Spanish", "French", "German").forEach { opt ->
                    EchoChoiceChip(label = opt, selected = language == opt, onClick = { language = opt })
                }
            }
            Spacer(modifier = Modifier.weight(1f))
            EchoPrimaryButton(
                text = "Save Profile",
                onClick = { onSave(profile.copy(preferredName = name.ifBlank { "Alex Parker" }, ageRange = ageRange, preferredLanguage = language)) }
            )
        }
    }
}

@Composable
private fun ConnectedDevicesSubScreen(
    screeningState: HearingScreeningUiState,
    monitorState: MonitorUiState,
    onRefresh: () -> Unit,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Connected Devices", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Active Screening Route", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    screeningState.audioRoute?.deviceName ?: "No route detected",
                    color = EchoPrimary,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    if (screeningState.isHeadphoneConnected) "Supported headphone route" else "Speaker active (headphones required for screening)",
                    color = EchoTextMuted,
                    fontSize = 13.sp
                )
                Spacer(modifier = Modifier.height(10.dp))
                EchoOutlinedPillButton(text = "Refresh Audio Route", icon = Icons.Default.Refresh, onClick = onRefresh)
            }
            EchoCard {
                Text("Monitor Inputs (${monitorState.inputs.size})", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                monitorState.inputs.forEach { Text("• ${it.label}", color = EchoTextMuted, fontSize = 12.5.sp) }
                Spacer(modifier = Modifier.height(8.dp))
                Text("Monitor Outputs (${monitorState.outputs.size})", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                monitorState.outputs.forEach { Text("• ${it.label}", color = EchoTextMuted, fontSize = 12.5.sp) }
            }
        }
    }
}

@Composable
private fun NotificationsSubScreen(
    profile: UserProfile,
    onUpdateProfile: (UserProfile) -> Unit,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Notifications", onBack = onBack)
        Column(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Screening & Listening Alerts", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        Text("Reminder cadence: ${profile.reminderFrequency}", color = EchoTextMuted, fontSize = 13.sp)
                    }
                    Switch(
                        checked = profile.notificationsEnabled,
                        onCheckedChange = { onUpdateProfile(profile.copy(notificationsEnabled = it)) },
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = EchoPrimary)
                    )
                }
            }
        }
    }
}

@Composable
private fun PrivacyDataSubScreen(
    onRestartOnboarding: () -> Unit,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Privacy & Data", onBack = onBack)
        Column(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Offline-First Privacy Guarantee", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "• Microphone audio for ambient noise gating and Live Monitor DSP is processed transiently in RAM only.\n" +
                        "• Zero raw audio is saved to disk or transmitted to any cloud server.\n" +
                        "• Screening sessions and EQ settings are stored exclusively in app-private local storage.",
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 21.sp
                )
            }
            EchoOutlinedPillButton(
                text = "Re-open Welcome & Health Notice",
                icon = Icons.Outlined.Replay,
                onClick = onRestartOnboarding
            )
        }
    }
}

@Composable
private fun ExportDataSubScreen(
    profile: UserProfile,
    sessions: List<HearingSessionRecord>,
    clarityTrials: List<String>,
    onBack: () -> Unit
) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    val jsonPreview = remember(profile, sessions, clarityTrials) {
        GsonBuilder().setPrettyPrinting().create().toJson(
            mapOf(
                "profile" to profile,
                "screeningSessions" to sessions,
                "speechClarityTrials" to clarityTrials
            )
        )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Export Data", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoPrimaryButton(
                text = if (copied) "Copied JSON to Clipboard" else "Copy Export JSON",
                icon = Icons.Outlined.ContentCopy,
                onClick = {
                    clipboard.setText(AnnotatedString(jsonPreview))
                    copied = true
                }
            )
            EchoCard {
                Text("JSON Export Preview", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = jsonPreview.take(3000),
                    color = EchoTextMuted,
                    fontSize = 11.5.sp,
                    lineHeight = 16.sp
                )
            }
        }
    }
}

@Composable
private fun AboutEchoSubScreen(onBack: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "About ECHO", onBack = onBack)
        Column(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("ECHO Integrated POC", color = EchoNavy, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "Combines pure-tone audiometric screening (Modified Hughson–Westlake & Experimental Binary Search Refinement with continuous ambient noise gating) and a native C++ Oboe full-duplex live audio DSP monitor (4-band LR4 crossover, noise gate, adaptive denoiser, downward compression, and 6-band per-ear EQ).\n\n" +
                        "Engineering prototype only — not a medical device or calibrated hearing aid.",
                    color = EchoTextMuted,
                    fontSize = 13.5.sp,
                    lineHeight = 20.sp
                )
            }
        }
    }
}

@Composable
private fun HelpFaqSubScreen(onBack: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Help & FAQ", onBack = onBack)
        Column(
            modifier = Modifier.fillMaxSize().padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            EchoCard {
                Text("Why are results reported in dBFS instead of dB HL?", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Consumer phones and earbuds lack IEC 60318-1/4 artificial-ear calibration, so ECHO honestly reports digital attenuation steps (dBFS).",
                    color = EchoTextMuted,
                    fontSize = 13.sp,
                    lineHeight = 19.sp
                )
            }
            EchoCard {
                Text("Why does Live Monitor stop when I switch tabs?", color = EchoNavy, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    "Screening and live monitoring share the microphone and audio output route, so leaving Monitor or backgrounding the app safely stops the stream.",
                    color = EchoTextMuted,
                    fontSize = 13.sp,
                    lineHeight = 19.sp
                )
            }
        }
    }
}

