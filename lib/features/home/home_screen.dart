import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:echo_hearing/features/screening/widgets/audiogram_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final screening = ref.watch(screeningNotifierProvider);
    final monitor = ref.watch(monitorNotifierProvider);
    final demoEnabled = ref.watch(demoDataEnabledProvider);

    final latestCompleted = screening.savedSessions
        .where((s) => s.isCompleted)
        .firstOrNull;

    return Scaffold(
      appBar: EchoTopBar(
        title: 'ECHO',
        actions: [
          if (demoEnabled) const EchoStatusPill(label: 'Sample data'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, ${profile.name}',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Goal: ${profile.primaryGoal}',
                style: const TextStyle(fontSize: 14, color: EchoColors.muted),
              ),
              const SizedBox(height: 18),
              if (!profile.initialScreeningCompleted) ...[
                EchoCard(
                  containerColor: EchoColors.primarySoft,
                  borderColor: EchoColors.pillBorder,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            color: EchoColors.primary,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Initial Baseline Pending',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: EchoColors.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Complete your initial hearing screening with headphones to establish a personal baseline.',
                        style: TextStyle(
                          fontSize: 13,
                          color: EchoColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      EchoPrimaryButton(
                        text: 'Start Initial Screening',
                        icon: Icons.hearing_outlined,
                        onPressed: () => context.go('/test'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (latestCompleted != null) ...[
                EchoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            const Text(
                              'Latest Screening',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: EchoColors.navy,
                              ),
                            ),
                            EchoStatusPill(
                              label:
                                  latestCompleted
                                      .screeningOutcome
                                      ?.overallClassification
                                      .displayName ??
                                  'Saved',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, y • h:mm a').format(
                          DateTime.fromMillisecondsSinceEpoch(
                            latestCompleted.startedAt,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: EchoColors.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AudiogramView(
                        thresholds: latestCompleted.thresholdResults,
                        height: 170,
                      ),
                    ],
                  ),
                ),
              ] else if (demoEnabled) ...[
                EchoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Screening Snapshot',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: EchoColors.navy,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          EchoStatusPill(label: 'Sample data'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Run a screening in the Test tab to replace sample preview text with your recorded thresholds.',
                        style: TextStyle(
                          fontSize: 13,
                          color: EchoColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      EchoOutlinedPillButton(
                        text: 'Go to Hearing Screening',
                        icon: Icons.hearing_outlined,
                        onPressed: () => context.go('/test'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                EchoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No Screenings Recorded Yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Start a preliminary screening in the Test tab to save your digital response pattern locally.',
                        style: TextStyle(
                          fontSize: 13,
                          color: EchoColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      EchoOutlinedPillButton(
                        text: 'Run Preliminary Screening',
                        icon: Icons.hearing_outlined,
                        onPressed: () => context.go('/test'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              EchoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        EchoIconBadge(
                          icon: monitor.hasSafeHeadphoneOutput
                              ? Icons.headphones_rounded
                              : Icons.graphic_eq_rounded,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Live Sound Monitor & EQ',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: EchoColors.navy,
                                ),
                              ),
                              Text(
                                monitor.running
                                    ? 'Active (${monitor.streamInfo})'
                                    : monitor.hasSafeHeadphoneOutput
                                    ? 'Headphones connected • Ready for real-time listening'
                                    : 'Connect wired, USB-C, or Bluetooth headphones',
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
                    const SizedBox(height: 14),
                    EchoOutlinedPillButton(
                      text: 'Open Sound Monitor',
                      icon: Icons.graphic_eq_rounded,
                      onPressed: () => context.go('/monitor'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'ECHO is a preliminary screening & sound awareness tool, not diagnostic medical equipment.',
                style: TextStyle(fontSize: 12, color: EchoColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
