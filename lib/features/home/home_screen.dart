import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/daily_exposure_store.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demoEnabled = ref.watch(demoDataEnabledProvider);
    final exposure = ref.watch(dailyExposureProvider);
    final screening = ref.watch(screeningNotifierProvider);

    final latestCompleted = screening.savedSessions
        .where((s) => s.isCompleted)
        .firstOrNull;

    final isToneSample = latestCompleted == null || demoEnabled;
    final isExposureSample = exposure.isSample || demoEnabled;
    final isHomeSample = isToneSample || isExposureSample || demoEnabled;

    final String lastCheckedText;
    if (latestCompleted != null) {
      final daysAgo = DateTime.now()
          .difference(
            DateTime.fromMillisecondsSinceEpoch(latestCompleted.startedAt),
          )
          .inDays;
      if (daysAgo == 0) {
        lastCheckedText = 'Today';
      } else if (daysAgo == 1) {
        lastCheckedText = 'Yesterday';
      } else {
        lastCheckedText = '$daysAgo days ago';
      }
    } else if (demoEnabled) {
      lastCheckedText = '3 days ago';
    } else {
      lastCheckedText = 'Never (initial check pending)';
    }

    return Scaffold(
      appBar: EchoTopBar(
        title: 'ECHO Dashboard',
        actions: [
          if (isHomeSample) const EchoStatusPill(label: 'Sample data'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Card 1: Headphones Connection Status ---
              EchoCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: EchoColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        exposure.connectionType.toLowerCase().contains('bluetooth')
                            ? Icons.bluetooth_rounded
                            : Icons.headphones_rounded,
                        color: EchoColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exposure.isHeadphoneConnected
                                ? 'Headphones Connected'
                                : 'Headphones Disconnected',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            exposure.connectionSubtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: EchoColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Card 2: Daily Sound Exposure ---
              EchoCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Daily Sound Exposure',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                        if (isExposureSample) ...[
                          const SizedBox(width: 8),
                          const EchoStatusPill(label: 'Sample data'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Illustrative estimate based on personal audio monitoring guidelines',
                      style: TextStyle(
                        fontSize: 12,
                        color: EchoColors.muted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            exposure.formattedTodayListening,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: EchoColors.primary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "Today's Listening",
                            style: TextStyle(
                              fontSize: 13,
                              color: EchoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            exposure.ambientLevelText,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: EchoColors.primary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Ambient Exposure',
                            style: TextStyle(
                              fontSize: 13,
                              color: EchoColors.muted,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            exposure.formattedCurrentSession,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: EchoColors.primary,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Current Session',
                            style: TextStyle(
                              fontSize: 13,
                              color: EchoColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: exposure.dailyProgress > 0
                            ? exposure.dailyProgress
                            : 0.05,
                        minHeight: 8,
                        backgroundColor: EchoColors.surfaceAlt,
                        color: EchoColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Card 3: Tone Response Profile ---
              EchoCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Tone Response Profile',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                        if (isToneSample) ...[
                          const SizedBox(width: 8),
                          const EchoStatusPill(label: 'Sample data'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Last checked: $lastCheckedText',
                      style: const TextStyle(
                        fontSize: 13,
                        color: EchoColors.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Consistent relative sound response across speech frequencies (Levels 1–13).',
                      style: TextStyle(
                        fontSize: 14,
                        color: EchoColors.navy,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    EchoOutlinedPillButton(
                      text: 'Check Response Again',
                      icon: Icons.refresh_rounded,
                      onPressed: () {
                        ref
                            .read(screeningNotifierProvider.notifier)
                            .openSubScreen(ScreeningSubScreen.mainFlow);
                        context.go('/test');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Section: Quick Access ---
              const Text(
                'Quick Access',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 12),
              EchoOutlinedPillButton(
                text: 'History',
                icon: Icons.history_rounded,
                onPressed: () {
                  ref
                      .read(screeningNotifierProvider.notifier)
                      .openSubScreen(ScreeningSubScreen.history);
                  context.go('/test');
                },
              ),
              const SizedBox(height: 20),

              const Center(
                child: Text(
                  'ECHO is a preliminary screening & sound awareness tool, not diagnostic medical equipment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: EchoColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
