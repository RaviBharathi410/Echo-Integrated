package com.echo.hearing.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.echo.hearing.data.UserProfileStore
import com.echo.hearing.domain.statemachine.SessionState
import com.echo.hearing.monitor.MonitorScreen
import com.echo.hearing.monitor.MonitorViewModel
import com.echo.hearing.ui.theme.*

private enum class EchoTab(val label: String, val selectedIcon: ImageVector, val unselectedIcon: ImageVector) {
    TEST("Test", Icons.Filled.Hearing, Icons.Outlined.Hearing),
    HOME("Home", Icons.Filled.GridView, Icons.Outlined.GridView),
    MONITOR("Monitor", Icons.Filled.GraphicEq, Icons.Outlined.GraphicEq),
    REPORTS("Reports", Icons.Filled.BarChart, Icons.Outlined.BarChart),
    PROFILE("Profile", Icons.Filled.Person, Icons.Outlined.Person)
}

/**
 * Top-level shell: onboarding flow followed by the 5-tab ECHO workspace
 * (Test, Home, Monitor, Reports, Profile).
 * Screening and live monitoring share the microphone and output route, so leaving
 * the Monitor tab or the app stops the live Oboe monitor loop.
 */
@Composable
fun EchoApp(
    screeningViewModel: HearingScreeningViewModel,
    monitorViewModel: MonitorViewModel,
    onRequestMicrophonePermission: () -> Unit
) {
    val context = LocalContext.current
    val profileStore = remember { UserProfileStore(context) }
    var profile by remember { mutableStateOf(profileStore.load()) }
    var showOnboarding by rememberSaveable { mutableStateOf(!profile.onboardingCompleted) }
    var tab by rememberSaveable { mutableStateOf(EchoTab.TEST) }
    var openHistorySignal by remember { mutableIntStateOf(0) }
    var launchInitialScreeningSignal by remember { mutableIntStateOf(0) }
    var openMonitorSettingsOnce by remember { mutableStateOf(false) }

    val screeningState by screeningViewModel.uiState.collectAsState()
    val monitorState by monitorViewModel.state.collectAsState()
    var initialTestPending by rememberSaveable {
        mutableStateOf(!profile.initialScreeningCompleted && screeningState.savedSessions.isEmpty())
    }

    LaunchedEffect(screeningState.sessionState) {
        if (screeningState.sessionState == SessionState.RESULTS && !profile.initialScreeningCompleted) {
            val completedInitial = profile.copy(initialScreeningCompleted = true)
            profile = completedInitial
            profileStore.save(completedInitial)
            initialTestPending = false
            monitorViewModel.importLatestScreening()
        }
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                monitorViewModel.stop("Stopped when the app left the foreground")
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    if (showOnboarding) {
        val needsInitial = !profile.initialScreeningCompleted && screeningState.savedSessions.isEmpty()
        OnboardingFlow(
            profile = profile,
            needsInitialTest = needsInitial,
            onUpdateProfile = { updated ->
                profile = updated
                profileStore.save(updated)
            },
            onConsentAgreed = { screeningViewModel.onConsentAgreed(true) },
            onRequestMicrophonePermission = onRequestMicrophonePermission,
            onCompleteOnboarding = {
                val shouldRunInitial = !profile.initialScreeningCompleted && screeningState.savedSessions.isEmpty()
                val completed = profile.copy(
                    onboardingCompleted = true,
                    useSixFrequencies = if (shouldRunInitial) true else profile.useSixFrequencies
                )
                profile = completed
                profileStore.save(completed)
                showOnboarding = false
                tab = EchoTab.TEST
                if (shouldRunInitial) {
                    initialTestPending = true
                    screeningViewModel.setUseSixFrequencies(true)
                    launchInitialScreeningSignal++
                }
            }
        )
        return
    }

    Scaffold(
        containerColor = EchoBg,
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            Column(modifier = Modifier.background(Color.White)) {
                HorizontalDivider(color = EchoBorder, thickness = 1.dp)
                NavigationBar(
                    containerColor = Color.White,
                    tonalElevation = 0.dp
                ) {
                    EchoTab.entries.forEach { t ->
                        val selected = tab == t
                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                if (t != EchoTab.MONITOR) {
                                    monitorViewModel.stop("Stopped")
                                }
                                openMonitorSettingsOnce = false
                                tab = t
                            },
                            icon = {
                                Icon(
                                    imageVector = if (selected) t.selectedIcon else t.unselectedIcon,
                                    contentDescription = t.label
                                )
                            },
                            label = {
                                Text(
                                    text = t.label,
                                    fontSize = 11.sp
                                )
                            },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = EchoPrimary,
                                selectedTextColor = EchoPrimary,
                                unselectedIconColor = EchoTextMuted,
                                unselectedTextColor = EchoTextMuted,
                                indicatorColor = EchoPrimarySoft
                            )
                        )
                    }
                }
            }
        }
    ) { padding: PaddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            when (tab) {
                EchoTab.TEST -> HearingScreeningApp(
                    viewModel = screeningViewModel,
                    profile = profile,
                    initialTestPending = initialTestPending,
                    launchInitialScreeningSignal = launchInitialScreeningSignal,
                    onUpdateProfile = { updated ->
                        profile = updated
                        profileStore.save(updated)
                    },
                    onRequestMicrophonePermission = onRequestMicrophonePermission,
                    onImportToMonitor = {
                        monitorViewModel.importLatestScreening()
                        openMonitorSettingsOnce = true
                        tab = EchoTab.MONITOR
                    },
                    onSkipInitialTest = {
                        initialTestPending = false
                        tab = EchoTab.HOME
                    },
                    onNavigateToHome = { tab = EchoTab.HOME },
                    openHistorySignal = openHistorySignal
                )

                EchoTab.HOME -> HomeScreen(
                    profile = profile,
                    screeningState = screeningState,
                    monitorState = monitorState,
                    initialTestPending = initialTestPending || (!profile.initialScreeningCompleted && screeningState.savedSessions.isEmpty()),
                    onStartInitialTest = {
                        tab = EchoTab.TEST
                        launchInitialScreeningSignal++
                    },
                    onNavigateToTest = { tab = EchoTab.TEST },
                    onNavigateToMonitor = { tab = EchoTab.MONITOR },
                    onNavigateToReports = { tab = EchoTab.REPORTS },
                    onOpenScreeningHistory = {
                        openHistorySignal++
                        tab = EchoTab.TEST
                    }
                )

                EchoTab.MONITOR -> MonitorScreen(
                    vm = monitorViewModel,
                    openSettingsInitially = openMonitorSettingsOnce
                )

                EchoTab.REPORTS -> ReportsScreen(
                    screeningState = screeningState,
                    monitorState = monitorState,
                    onOpenScreeningHistory = {
                        openHistorySignal++
                        tab = EchoTab.TEST
                    }
                )

                EchoTab.PROFILE -> ProfileScreen(
                    profile = profile,
                    onUpdateProfile = { updated ->
                        profile = updated
                        profileStore.save(updated)
                    },
                    screeningState = screeningState,
                    monitorState = monitorState,
                    onRefreshDeviceRoute = { screeningViewModel.refreshDeviceRoute() },
                    onRestartOnboarding = {
                        monitorViewModel.stop("Stopped")
                        profileStore.resetOnboarding()
                        profile = profile.copy(onboardingCompleted = false)
                        showOnboarding = true
                    },
                    onSignOut = {
                        monitorViewModel.stop("Stopped")
                        profileStore.signOut()
                        profile = profile.copy(
                            onboardingCompleted = false,
                            initialScreeningCompleted = false,
                            accountMode = "Guest"
                        )
                        initialTestPending = true
                        showOnboarding = true
                    }
                )
            }
        }
    }
}
