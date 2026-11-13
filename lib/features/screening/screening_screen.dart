import 'dart:async';

import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/router.dart';
import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/domain/statemachine/session_state_machine.dart';
import 'package:echo_hearing/core/domain/threshold/threshold_estimation_strategy.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:echo_hearing/features/screening/widgets/audiogram_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class ScreeningShellScreen extends ConsumerStatefulWidget {
  const ScreeningShellScreen({super.key});

  @override
  ConsumerState<ScreeningShellScreen> createState() =>
      _ScreeningShellScreenState();
}

class _ScreeningShellScreenState extends ConsumerState<ScreeningShellScreen> {
  bool _simDrawerOpen = false;

  bool _shouldHideBottomNav(SessionState s) {
    return switch (s) {
      SessionState.practicePresentation ||
      SessionState.practiceFeedback ||
      SessionState.stimulusPresentation ||
      SessionState.waitingForResponse ||
      SessionState.trialValidation ||
      SessionState.thresholdEstimation ||
      SessionState.automaticPauseNoise ||
      SessionState.automaticPauseDevice ||
      SessionState.recoveryRecheck => true,
      _ => false,
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = ref.read(userProfileProvider);
      if (profile.healthNoticeAccepted) {
        ref.read(screeningNotifierProvider.notifier).ensureConsentedForLoggedInUser();
      }
      ref.read(screeningNotifierProvider.notifier).refreshDeviceRoute();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ScreeningUiState>(screeningNotifierProvider, (prev, next) {
      final hide = _shouldHideBottomNav(next.sessionState);
      if (ref.read(hideBottomNavProvider) != hide) {
        ref.read(hideBottomNavProvider.notifier).state = hide;
      }
      if (prev?.sessionState != SessionState.results &&
          next.sessionState == SessionState.results) {
        ref.read(userProfileProvider.notifier).markInitialScreeningCompleted();
      }
      if (prev?.savedSessions != next.savedSessions &&
          next.savedSessions.isNotEmpty) {
        unawaited(
          ref
              .read(monitorNotifierProvider.notifier)
              .importLatestScreening(silentWhenEmpty: true),
        );
      }
    });

    final state = ref.watch(screeningNotifierProvider);
    final notifier = ref.read(screeningNotifierProvider.notifier);
    final demoEnabled = ref.watch(demoDataEnabledProvider);
    final profile = ref.watch(userProfileProvider);

    Widget body;
    if (state.subScreen != ScreeningSubScreen.mainFlow) {
      body = switch (state.subScreen) {
        ScreeningSubScreen.history => _HistoryView(
          state: state,
          demoEnabled: demoEnabled,
          onBack: () => notifier.openSubScreen(ScreeningSubScreen.mainFlow),
          onCompare: () => notifier.openSubScreen(ScreeningSubScreen.compare),
          onReminders: () =>
              notifier.openSubScreen(ScreeningSubScreen.reminders),
          onViewRecord: (rec) => notifier.openSubScreen(
            ScreeningSubScreen.recordDetail,
            record: rec,
          ),
        ),
        ScreeningSubScreen.compare => _CompareView(
          state: state,
          demoEnabled: demoEnabled,
          onBack: () => notifier.openSubScreen(ScreeningSubScreen.history),
        ),
        ScreeningSubScreen.reminders => _RemindersView(
          onBack: () => notifier.openSubScreen(ScreeningSubScreen.history),
        ),
        ScreeningSubScreen.recordDetail => _RecordDetailView(
          record: state.selectedRecord,
          demoEnabled: demoEnabled,
          onBack: () => notifier.openSubScreen(ScreeningSubScreen.history),
        ),
        ScreeningSubScreen.mainFlow => const SizedBox.shrink(),
      };
    } else if (state.isLeftEarCompletePaused) {
      body = _LeftEarCompleteView(onContinue: notifier.onContinueRightEar);
    } else {
      body = switch (state.sessionState) {
        SessionState.notStarted ||
        SessionState.onboardingConsent => _DeviceSetupView(
          state: state,
          isInitialBaseline: !profile.initialScreeningCompleted,
          demoEnabled: demoEnabled,
          onToggleSimDrawer: () =>
              setState(() => _simDrawerOpen = !_simDrawerOpen),
          onOpenHistory: () =>
              notifier.openSubScreen(ScreeningSubScreen.history),
          onContinue: () {
            notifier.ensureConsentedForLoggedInUser();
            notifier.onDevicePrecheckContinue();
          },
        ),
        SessionState.deviceReadiness ||
        SessionState.calibrationGate ||
        SessionState.environmentalNoiseCheck => _DeviceSetupView(
          state: state,
          isInitialBaseline: !profile.initialScreeningCompleted,
          demoEnabled: demoEnabled,
          onToggleSimDrawer: () =>
              setState(() => _simDrawerOpen = !_simDrawerOpen),
          onOpenHistory: () =>
              notifier.openSubScreen(ScreeningSubScreen.history),
          onContinue: notifier.onDevicePrecheckContinue,
        ),
        SessionState.testPrep => _ScreeningBriefingView(
          isInitialBaseline: !profile.initialScreeningCompleted,
          extendedMode: state.isExtendedFrequencyMode,
          onBack: notifier.onTryAgain,
          onStartPractice: notifier.onStartPractice,
          onStartScreening: notifier.onStartScreening,
        ),
        SessionState.practicePresentation ||
        SessionState.practiceFeedback => _PracticeRoundView(
          state: state,
          onHeard: notifier.onPracticeHeardClicked,
          onNotHeard: notifier.onPracticeNotHeardClicked,
          onReplay: notifier.onStartPractice,
          onStartFormalTest: notifier.onStartScreening,
          onBack: notifier.onFinishPractice,
        ),
        SessionState.stimulusPresentation ||
        SessionState.waitingForResponse ||
        SessionState.trialValidation ||
        SessionState.thresholdEstimation => _ActiveScreeningView(
          state: state,
          onHeard: notifier.onUserHeardClicked,
          onNotHeard: notifier.onUserNotHeardClicked,
          onPause: notifier.onPauseRequested,
          onResume: notifier.onResumeRequested,
          onCancel: notifier.onCancelRequested,
        ),
        SessionState.automaticPauseNoise ||
        SessionState.automaticPauseDevice ||
        SessionState.recoveryRecheck => _PausedOverlayView(
          state: state,
          demoEnabled: demoEnabled,
          onToggleSimDrawer: () =>
              setState(() => _simDrawerOpen = !_simDrawerOpen),
          onCancel: notifier.onCancelRequested,
        ),
        SessionState.results || SessionState.completed => _ResultsView(
          state: state,
          onTryAgain: notifier.onTryAgain,
          onOpenHistory: () =>
              notifier.openSubScreen(ScreeningSubScreen.history),
          onOpenMonitor: () => context.go('/monitor'),
        ),
        SessionState.cancelled || SessionState.aborted => _AbortedView(
          reason:
              state.cancelReason ??
              'Screening was interrupted or cancelled before completion.',
          onTryAgain: notifier.onTryAgain,
        ),
      };
    }

    return Column(
      children: [
        if (demoEnabled && _simDrawerOpen)
          _SimulationDrawer(
            state: state,
            onToggleSim: notifier.toggleSimulationMode,
            onQuiet: () => notifier.simulateNoiseSpike(NoiseAssessment.valid),
            onLoud: () => notifier.simulateNoiseSpike(NoiseAssessment.invalid),
            onUnplug: notifier.simulateDeviceDisconnect,
            onReplug: notifier.simulateDeviceReconnect,
            onClose: () => setState(() => _simDrawerOpen = false),
          ),
        Expanded(child: body),
      ],
    );
  }
}

class _DeviceSetupView extends ConsumerWidget {
  const _DeviceSetupView({
    required this.state,
    required this.isInitialBaseline,
    required this.demoEnabled,
    required this.onToggleSimDrawer,
    required this.onOpenHistory,
    required this.onContinue,
  });

  final ScreeningUiState state;
  final bool isInitialBaseline;
  final bool demoEnabled;
  final VoidCallback onToggleSimDrawer;
  final VoidCallback onOpenHistory;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(screeningNotifierProvider.notifier);
    final noise = state.noiseReading;
    final route = state.audioRoute;
    final noiseOk =
        noise.assessment == NoiseAssessment.valid ||
        noise.assessment == NoiseAssessment.suspect;
    final noiseLabel = switch (noise.assessment) {
      NoiseAssessment.valid => 'Quiet Environment',
      NoiseAssessment.suspect => 'Moderate Room Sound',
      NoiseAssessment.invalid => 'Environment Too Loud',
      NoiseAssessment.unavailable => 'Mic Sensor Unavailable',
    };

    return Scaffold(
      appBar: EchoTopBar(
        title: 'Hearing Screening',
        actions: [
          if (demoEnabled)
            EchoStatusPill(
              label: state.isSimulationMode ? 'DEV SIM ON' : 'DEV SIM',
              icon: Icons.bug_report_outlined,
              onTap: onToggleSimDrawer,
            ),
          EchoStatusPill(
            label: 'History',
            icon: Icons.history_rounded,
            onTap: onOpenHistory,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isInitialBaseline) ...[
                EchoCard(
                  containerColor: EchoColors.primarySoft,
                  borderColor: EchoColors.pillBorder,
                  padding: const EdgeInsets.all(16),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: EchoColors.primary,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Initial Baseline Screening',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: EchoColors.navy,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Complete a quick baseline check to establish your starting response pattern across ears.',
                              style: TextStyle(
                                fontSize: 13,
                                color: EchoColors.muted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              EchoCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        EchoIconBadge(
                          icon: state.isHeadphoneConnected
                              ? Icons.headphones_rounded
                              : Icons.volume_up_rounded,
                          containerColor: state.isHeadphoneConnected
                              ? EchoColors.emeraldSoft
                              : EchoColors.roseSoft,
                          tint: state.isHeadphoneConnected
                              ? EchoColors.emerald
                              : EchoColors.rose,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Audio Output Route',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: EchoColors.muted,
                                ),
                              ),
                              Text(
                                route?.deviceName ?? 'Checking route...',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: EchoColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                        EchoStatusPill(
                          label: state.isHeadphoneConnected
                              ? 'Connected'
                              : 'Required',
                          icon: state.isHeadphoneConnected
                              ? Icons.check_circle_outline_rounded
                              : Icons.warning_amber_rounded,
                          containerColor: state.isHeadphoneConnected
                              ? EchoColors.emeraldSoft
                              : EchoColors.roseSoft,
                          borderColor: state.isHeadphoneConnected
                              ? EchoColors.emeraldSoft
                              : EchoColors.roseSoft,
                          contentColor: state.isHeadphoneConnected
                              ? EchoColors.emerald
                              : EchoColors.rose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: EchoColors.border),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        EchoIconBadge(
                          icon: Icons.mic_none_rounded,
                          containerColor: noiseOk
                              ? EchoColors.emeraldSoft
                              : EchoColors.amberSoft,
                          tint: noiseOk ? EchoColors.emerald : EchoColors.amber,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ambient Noise Floor',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: EchoColors.muted,
                                ),
                              ),
                              Text(
                                '$noiseLabel (${noise.levelDbFs.toStringAsFixed(1)} dBFS)',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: EchoColors.navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ((noise.levelDbFs + 80.0) / 80.0).clamp(
                          0.05,
                          1.0,
                        ),
                        minHeight: 8,
                        backgroundColor: EchoColors.surfaceAlt,
                        color: noiseOk ? EchoColors.emerald : EchoColors.rose,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.pauseReason != null) ...[
                const SizedBox(height: 14),
                EchoCard(
                  containerColor: EchoColors.roseSoft,
                  borderColor: EchoColors.rose,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: EchoColors.rose,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state.pauseReason!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: EchoColors.navy,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              EchoCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Screening Protocol & Algorithm',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: EchoColors.navy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        EchoChoiceChip(
                          label: 'Hughson–Westlake',
                          selected:
                              state.selectedStrategy ==
                              StrategyType.modifiedHughsonWestlake,
                          onTap: () => notifier.selectStrategy(
                            StrategyType.modifiedHughsonWestlake,
                          ),
                        ),
                        EchoChoiceChip(
                          label: 'Binary Search',
                          selected:
                              state.selectedStrategy ==
                              StrategyType.binarySearchRefinement,
                          onTap: () => notifier.selectStrategy(
                            StrategyType.binarySearchRefinement,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Extended 6-Frequency Range',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: EchoColors.navy,
                                ),
                              ),
                              Text(
                                '250, 500, 1k, 2k, 4k, 8k Hz (default is 4 core tones)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: EchoColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: state.isExtendedFrequencyMode,
                          activeThumbColor: Colors.white,
                          activeTrackColor: EchoColors.primary,
                          onChanged: notifier.toggleFrequencyMode,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              EchoPrimaryButton(
                text: 'Continue to Screening Briefing',
                icon: Icons.arrow_forward_rounded,
                onPressed: onContinue,
              ),
              const SizedBox(height: 10),
              EchoOutlinedPillButton(
                text: 'Refresh Device & Noise Check',
                icon: Icons.refresh_rounded,
                onPressed: notifier.refreshDeviceRoute,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreeningBriefingView extends StatelessWidget {
  const _ScreeningBriefingView({
    required this.isInitialBaseline,
    required this.extendedMode,
    required this.onBack,
    required this.onStartPractice,
    required this.onStartScreening,
  });

  final bool isInitialBaseline;
  final bool extendedMode;
  final VoidCallback onBack;
  final VoidCallback onStartPractice;
  final VoidCallback onStartScreening;

  @override
  Widget build(BuildContext context) {
    final freqDesc = extendedMode
        ? '6 test frequencies (250, 500, 1000, 2000, 4000, 8000 Hz)'
        : '4 core speech frequencies (500, 1000, 2000, 4000 Hz)';

    return Scaffold(
      appBar: EchoTopBar(
        title: isInitialBaseline
            ? 'Initial Screening Briefing'
            : 'Screening Briefing',
        onBack: onBack,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            children: [
              EchoCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.hearing_outlined,
                          color: EchoColors.primary,
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Preliminary Tone Screening',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'This sound check presents a sequence of $freqDesc to evaluate relative auditory response.',
                      style: const TextStyle(
                        fontSize: 15,
                        color: EchoColors.navy,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Whenever you hear a tone pulse, tap "I Hear It". If you do not hear it after several pulses, tap "I Can\'t Hear It" to test the next relative level.',
                      style: TextStyle(
                        fontSize: 14,
                        color: EchoColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const EchoCard(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Screening Protocol',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: EchoColors.navy,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '• Left Ear tested first across all test frequencies.\n'
                      '• Button-driven interstitial transition.\n'
                      '• Right Ear tested second.\n'
                      '• Summary response pattern presented upon completion.',
                      style: TextStyle(
                        fontSize: 14,
                        color: EchoColors.navy,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              EchoPrimaryButton(
                text: isInitialBaseline
                    ? 'Begin Initial Screening'
                    : 'Begin Screening',
                icon: Icons.play_arrow_rounded,
                onPressed: onStartScreening,
              ),
              const SizedBox(height: 12),
              EchoOutlinedPillButton(
                text: 'Play Practice Demo Tone (1000 Hz)',
                icon: Icons.volume_up_outlined,
                onPressed: onStartPractice,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeRoundView extends StatelessWidget {
  const _PracticeRoundView({
    required this.state,
    required this.onHeard,
    required this.onNotHeard,
    required this.onReplay,
    required this.onStartFormalTest,
    required this.onBack,
  });

  final ScreeningUiState state;
  final VoidCallback onHeard;
  final VoidCallback onNotHeard;
  final VoidCallback onReplay;
  final VoidCallback onStartFormalTest;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final inFeedback = state.sessionState == SessionState.practiceFeedback;

    return Scaffold(
      appBar: EchoTopBar(title: 'Practice Round', onBack: onBack),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EchoIconBadge(
                icon: state.practiceTonePlaying
                    ? Icons.graphic_eq_rounded
                    : Icons.headphones_rounded,
                size: 72,
                iconSize: 34,
                isCircle: true,
                containerColor: EchoColors.primarySoft,
              ),
              const SizedBox(height: 18),
              const Text(
                '1000 Hz Sample Tone (Left Ear)',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                state.practiceFeedbackMessage ??
                    'Listen carefully and indicate whether you heard the tone.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: EchoColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              if (!inFeedback) ...[
                EchoPrimaryButton(
                  text: 'I HEAR IT',
                  icon: Icons.check_rounded,
                  backgroundColor: EchoColors.emerald,
                  onPressed: onHeard,
                ),
                const SizedBox(height: 12),
                EchoOutlinedPillButton(
                  text: "I CAN'T HEAR IT",
                  icon: Icons.hearing_disabled_outlined,
                  onPressed: onNotHeard,
                ),
              ] else ...[
                EchoPrimaryButton(
                  text: 'Start Formal Screening',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onStartFormalTest,
                ),
                const SizedBox(height: 12),
                EchoOutlinedPillButton(
                  text: 'Replay Demo Tone',
                  icon: Icons.replay_rounded,
                  onPressed: onReplay,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveScreeningView extends StatelessWidget {
  const _ActiveScreeningView({
    required this.state,
    required this.onHeard,
    required this.onNotHeard,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final ScreeningUiState state;
  final VoidCallback onHeard;
  final VoidCallback onNotHeard;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final totalTargets =
        (state.isExtendedFrequencyMode ? 6 : 4) * 2; // left + right ears
    final completedTargets = state.thresholdResults.length;
    final progress = (completedTargets / totalTargets).clamp(0.05, 1.0);
    final isPaused = state.isNoisePaused && state.pauseReason != null;

    return Scaffold(
      appBar: EchoTopBar(
        title: 'Hearing Screening',
        actions: [
          EchoStatusPill(
            label: isPaused ? 'Resume' : 'Pause test',
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: isPaused ? onResume : onPause,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    EchoStatusPill(
                      label:
                          '${state.currentEar.displayName} (${state.currentEar.clinicalCode})',
                      icon: Icons.headphones_outlined,
                    ),
                    Text(
                      '${state.currentFrequencyHz} Hz • ${state.currentLevelDb} dBFS',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: EchoColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: EchoColors.surfaceAlt,
                  color: EchoColors.primary,
                ),
              ),
              const Spacer(),
              EchoIconBadge(
                icon: state.isTonePlaying
                    ? Icons.graphic_eq_rounded
                    : Icons.hearing_outlined,
                size: 84,
                iconSize: 40,
                isCircle: true,
                containerColor: state.isTonePlaying
                    ? EchoColors.primary
                    : EchoColors.primarySoft,
                tint: state.isTonePlaying ? Colors.white : EchoColors.primary,
              ),
              const SizedBox(height: 18),
              Text(
                isPaused
                    ? 'Screening Paused'
                    : state.isWaitingForResponse
                    ? 'Listen & Respond'
                    : 'Preparing Next Tone...',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isPaused
                    ? state.pauseReason!
                    : state.isWaitingForResponse
                    ? 'Tap "I Hear It" if you perceive the pure tone, or "I Can\'t Hear It".'
                    : 'Hold still in a quiet room. Trial #${state.trialNumber + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: EchoColors.muted,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              EchoPrimaryButton(
                text: 'I Hear It',
                icon: Icons.check_rounded,
                enabled: state.isWaitingForResponse && !isPaused,
                backgroundColor: EchoColors.emerald,
                onPressed: onHeard,
              ),
              const SizedBox(height: 12),
              EchoOutlinedPillButton(
                text: "I Can't Hear It",
                icon: Icons.hearing_disabled_outlined,
                enabled: state.isWaitingForResponse && !isPaused,
                onPressed: onNotHeard,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onCancel,
                child: const Text(
                  'Cancel Screening',
                  style: TextStyle(color: EchoColors.rose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeftEarCompleteView extends StatelessWidget {
  const _LeftEarCompleteView({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EchoTopBar(title: 'Hearing Screening'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const EchoIconBadge(
              icon: Icons.headphones_rounded,
              size: 72,
              iconSize: 34,
              isCircle: true,
              containerColor: EchoColors.primarySoft,
            ),
            const SizedBox(height: 20),
            Text(
              'Left Ear Screening Complete',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 10),
            const Text(
              'Please reposition your headphones or adjust fit to ensure a comfortable seal for your right ear.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: EchoColors.muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            EchoPrimaryButton(
              text: 'Continue to Right Ear',
              icon: Icons.arrow_forward_rounded,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

class _PausedOverlayView extends StatelessWidget {
  const _PausedOverlayView({
    required this.state,
    required this.demoEnabled,
    required this.onToggleSimDrawer,
    required this.onCancel,
  });

  final ScreeningUiState state;
  final bool demoEnabled;
  final VoidCallback onToggleSimDrawer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(
        title: 'Screening Paused',
        actions: [
          if (demoEnabled)
            EchoStatusPill(
              label: 'DEV SIM',
              icon: Icons.bug_report_outlined,
              onTap: onToggleSimDrawer,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            EchoIconBadge(
              icon: state.isDevicePaused
                  ? Icons.headset_off_outlined
                  : Icons.volume_up_outlined,
              size: 72,
              iconSize: 34,
              isCircle: true,
              containerColor: EchoColors.amberSoft,
              tint: EchoColors.amber,
            ),
            const SizedBox(height: 18),
            Text(
              state.isDevicePaused
                  ? 'Headphones Disconnected'
                  : 'Environmental Noise Detected',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 10),
            Text(
              state.pauseReason ??
                  'Waiting for quiet ambient conditions and a connected headphone route.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: EchoColors.muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            EchoOutlinedPillButton(
              text: 'Cancel Screening',
              contentColor: EchoColors.rose,
              borderColor: EchoColors.rose,
              containerColor: EchoColors.roseSoft,
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.state,
    required this.onTryAgain,
    required this.onOpenHistory,
    required this.onOpenMonitor,
  });

  final ScreeningUiState state;
  final VoidCallback onTryAgain;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenMonitor;

  @override
  Widget build(BuildContext context) {
    final outcome = state.screeningOutcome;
    final overall =
        outcome?.overallClassification ??
        ScreeningOutcomeClassification.inconclusive;
    final badgeColors = switch (overall) {
      ScreeningOutcomeClassification.pass => (
        EchoColors.emeraldSoft,
        EchoColors.emerald,
      ),
      ScreeningOutcomeClassification.refer => (
        EchoColors.amberSoft,
        EchoColors.amber,
      ),
      ScreeningOutcomeClassification.inconclusive => (
        EchoColors.roseSoft,
        EchoColors.rose,
      ),
    };

    return Scaffold(
      appBar: EchoTopBar(
        title: 'Screening Results',
        actions: [
          EchoStatusPill(
            label: 'History',
            icon: Icons.history_rounded,
            onTap: onOpenHistory,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EchoCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EchoStatusPill(
                      label: overall.displayName,
                      icon: Icons.assessment_outlined,
                      containerColor: badgeColors.$1,
                      borderColor: badgeColors.$1,
                      contentColor: badgeColors.$2,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      overall.clinicalDescription,
                      style: const TextStyle(
                        fontSize: 14,
                        color: EchoColors.navy,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Trials: ${outcome?.totalTrials ?? state.trials.length} • Noise Interruptions: ${state.noisePauseCount}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: EchoColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              EchoCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Response Pattern (Digital dBFS)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: EchoColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AudiogramView(thresholds: state.thresholdResults),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const EchoCard(
                containerColor: EchoColors.surfaceAlt,
                borderColor: EchoColors.pillBorder,
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: EchoColors.primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clinical Limitations & Disclaimer',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'This result is a preliminary screening / wellness tool, not diagnostic medical audiometry. Measurements reflect uncalibrated consumer hardware digital attenuation (dBFS). Consult a licensed audiologist for clinical evaluation.',
                            style: TextStyle(
                              fontSize: 12,
                              color: EchoColors.muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              EchoPrimaryButton(
                text: 'Open Personalized Sound Monitor',
                icon: Icons.graphic_eq_rounded,
                onPressed: onOpenMonitor,
              ),
              const SizedBox(height: 10),
              EchoOutlinedPillButton(
                text: 'Run Another Screening',
                icon: Icons.replay_rounded,
                onPressed: onTryAgain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbortedView extends StatelessWidget {
  const _AbortedView({required this.reason, required this.onTryAgain});

  final String reason;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EchoTopBar(title: 'Screening Ended'),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const EchoIconBadge(
              icon: Icons.cancel_outlined,
              size: 72,
              iconSize: 34,
              isCircle: true,
              containerColor: EchoColors.roseSoft,
              tint: EchoColors.rose,
            ),
            const SizedBox(height: 18),
            Text(
              'Screening Cancelled',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 10),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: EchoColors.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            EchoPrimaryButton(
              text: 'Try Again',
              icon: Icons.refresh_rounded,
              onPressed: onTryAgain,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({
    required this.state,
    required this.demoEnabled,
    required this.onBack,
    required this.onCompare,
    required this.onReminders,
    required this.onViewRecord,
  });

  final ScreeningUiState state;
  final bool demoEnabled;
  final VoidCallback onBack;
  final VoidCallback onCompare;
  final VoidCallback onReminders;
  final ValueChanged<HearingSessionRecord?> onViewRecord;

  @override
  Widget build(BuildContext context) {
    final sessions = state.savedSessions;

    return Scaffold(
      appBar: EchoTopBar(
        title: 'Screening History',
        onBack: onBack,
        actions: [
          if (demoEnabled)
            const EchoStatusPill(label: 'Sample data'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            children: [
              EchoCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Previous Screenings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                        if (demoEnabled) ...[
                          const SizedBox(width: 8),
                          const EchoStatusPill(label: 'Sample data'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Track preliminary tone response estimates over time.',
                      style: TextStyle(fontSize: 13, color: EchoColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              EchoOutlinedPillButton(
                text: 'Compare Screenings',
                icon: Icons.compare_arrows_rounded,
                onPressed: onCompare,
              ),
              const SizedBox(height: 10),
              EchoOutlinedPillButton(
                text: 'Screening Reminders',
                icon: Icons.alarm_outlined,
                onPressed: onReminders,
              ),
              if (sessions.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final rec in sessions) ...[
                  EchoCard(
                    onTap: () => onViewRecord(rec),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const EchoIconBadge(
                          icon: Icons.description_outlined,
                          size: 42,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('MMM d, y • h:mm a').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    rec.startedAt,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: EchoColors.navy,
                                ),
                              ),
                              Text(
                                '${rec.thresholdResults.length} targets • ${rec.screeningOutcome?.overallClassification.displayName ?? "Saved"}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: EchoColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: EchoColors.muted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ] else if (demoEnabled) ...[
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'View Latest Record (Sample #1)',
                  icon: Icons.description_outlined,
                  onPressed: () => onViewRecord(null),
                ),
              ] else ...[
                const SizedBox(height: 18),
                const EchoCard(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_toggle_off_rounded,
                        color: EchoColors.muted,
                        size: 32,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'No screening records saved yet.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: EchoColors.navy,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Complete a preliminary screening to store and review your audiogram.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: EchoColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompareView extends StatelessWidget {
  const _CompareView({
    required this.state,
    required this.demoEnabled,
    required this.onBack,
  });

  final ScreeningUiState state;
  final bool demoEnabled;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final sessions = state.savedSessions.where((s) => s.isCompleted).toList();

    return Scaffold(
      appBar: EchoTopBar(title: 'Compare Screenings', onBack: onBack),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: sessions.length >= 2
            ? Column(
                children: [
                  EchoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest Session',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: EchoColors.navy,
                          ),
                        ),
                        const SizedBox(height: 10),
                        AudiogramView(
                          thresholds: sessions.first.thresholdResults,
                          height: 180,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : demoEnabled
            ? const EchoCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EchoStatusPill(label: 'Sample Comparison'),
                    SizedBox(height: 10),
                    Text(
                      'Illustrative Delta: +0 dBFS change across 500–4000 Hz compared to reference sample.',
                      style: TextStyle(fontSize: 14, color: EchoColors.navy),
                    ),
                  ],
                ),
              )
            : const EchoCard(
                child: Text(
                  'Complete at least two screenings to compare changes over time.',
                  style: TextStyle(fontSize: 14, color: EchoColors.muted),
                ),
              ),
      ),
    );
  }
}

class _RemindersView extends StatefulWidget {
  const _RemindersView({required this.onBack});
  final VoidCallback onBack;

  @override
  State<_RemindersView> createState() => _RemindersViewState();
}

class _RemindersViewState extends State<_RemindersView> {
  String _cadence = 'Monthly Check-in';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(title: 'Screening Reminders', onBack: widget.onBack),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: EchoCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Check-in Schedule',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in [
                    'Weekly',
                    'Monthly Check-in',
                    'Quarterly',
                    'Off',
                  ])
                    EchoChoiceChip(
                      label: opt,
                      selected: _cadence == opt,
                      onTap: () => setState(() => _cadence = opt),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordDetailView extends StatelessWidget {
  const _RecordDetailView({
    required this.record,
    required this.demoEnabled,
    required this.onBack,
  });

  final HearingSessionRecord? record;
  final bool demoEnabled;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final thresholds =
        record?.thresholdResults ??
        (demoEnabled
            ? [
                ThresholdResult(
                  ear: Ear.left,
                  frequencyHz: 500,
                  thresholdDb: 20,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 5,
                ),
                ThresholdResult(
                  ear: Ear.left,
                  frequencyHz: 1000,
                  thresholdDb: 15,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 4,
                ),
                ThresholdResult(
                  ear: Ear.left,
                  frequencyHz: 2000,
                  thresholdDb: 20,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 5,
                ),
                ThresholdResult(
                  ear: Ear.left,
                  frequencyHz: 4000,
                  thresholdDb: 25,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 6,
                ),
                ThresholdResult(
                  ear: Ear.right,
                  frequencyHz: 500,
                  thresholdDb: 20,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 5,
                ),
                ThresholdResult(
                  ear: Ear.right,
                  frequencyHz: 1000,
                  thresholdDb: 20,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 5,
                ),
                ThresholdResult(
                  ear: Ear.right,
                  frequencyHz: 2000,
                  thresholdDb: 20,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 5,
                ),
                ThresholdResult(
                  ear: Ear.right,
                  frequencyHz: 4000,
                  thresholdDb: 20,
                  validAscendingResponses: 2,
                  totalTrialsForTarget: 5,
                ),
              ]
            : const <ThresholdResult>[]);

    return Scaffold(
      appBar: EchoTopBar(
        title: record == null && demoEnabled
            ? 'Sample Record #1'
            : 'Screening Record',
        onBack: onBack,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            EchoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (record == null && demoEnabled) ...[
                    const EchoStatusPill(label: 'Sample data'),
                    const SizedBox(height: 10),
                  ],
                  AudiogramView(thresholds: thresholds),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const EchoCard(
              containerColor: EchoColors.surfaceAlt,
              child: Text(
                'Preliminary screening / wellness tool, not diagnostic. Values represent digital attenuation (dBFS).',
                style: TextStyle(fontSize: 12, color: EchoColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimulationDrawer extends StatelessWidget {
  const _SimulationDrawer({
    required this.state,
    required this.onToggleSim,
    required this.onQuiet,
    required this.onLoud,
    required this.onUnplug,
    required this.onReplug,
    required this.onClose,
  });

  final ScreeningUiState state;
  final VoidCallback onToggleSim;
  final VoidCallback onQuiet;
  final VoidCallback onLoud;
  final VoidCallback onUnplug;
  final VoidCallback onReplug;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EchoColors.navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: onToggleSim,
                child: Text(
                  state.isSimulationMode ? 'SIM: ON' : 'SIM: OFF',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: onQuiet,
                child: const Text(
                  'Quiet',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: onLoud,
                child: const Text(
                  'Noise Spike',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: onUnplug,
                child: const Text(
                  'Unplug',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: onReplug,
                child: const Text(
                  'Replug',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
