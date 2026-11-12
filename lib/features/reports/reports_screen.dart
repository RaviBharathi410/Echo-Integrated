import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _ReportSection { hub, weeklyReport, exposureTrends, insightsTips, historical }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _ReportSection _section = _ReportSection.hub;

  @override
  Widget build(BuildContext context) {
    final demoEnabled = ref.watch(demoDataEnabledProvider);
    final screening = ref.watch(screeningNotifierProvider);
    final monitor = ref.watch(monitorNotifierProvider);

    return switch (_section) {
      _ReportSection.hub => Scaffold(
        appBar: EchoTopBar(
          title: 'Listening Reports',
          actions: [
            if (demoEnabled) const EchoStatusPill(label: 'Sample data'),
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              children: [
                EchoCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Weekly Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                          if (demoEnabled)
                            const EchoStatusPill(label: 'Sample data'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (demoEnabled)
                        const Text(
                          'Your listening habits remained 100% within recommended sound limits this week.',
                          style: TextStyle(
                            fontSize: 14,
                            color: EchoColors.muted,
                            height: 1.4,
                          ),
                        )
                      else
                        Text(
                          screening.savedSessions.isEmpty &&
                                  monitor.trials.isEmpty
                              ? 'No saved listening reports yet. Completed screenings and clarity A/B trials will appear here.'
                              : 'Recorded locally: ${screening.savedSessions.length} screening session(s) and ${monitor.trials.length} speech clarity trial(s).',
                          style: const TextStyle(
                            fontSize: 14,
                            color: EchoColors.muted,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                EchoOutlinedPillButton(
                  text: 'Weekly Report',
                  icon: Icons.view_week_outlined,
                  onPressed: () =>
                      setState(() => _section = _ReportSection.weeklyReport),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Exposure Trends',
                  icon: Icons.trending_up_rounded,
                  onPressed: () =>
                      setState(() => _section = _ReportSection.exposureTrends),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Insights & Tips',
                  icon: Icons.lightbulb_outline_rounded,
                  onPressed: () =>
                      setState(() => _section = _ReportSection.insightsTips),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Historical Data',
                  icon: Icons.history_rounded,
                  onPressed: () =>
                      setState(() => _section = _ReportSection.historical),
                ),
              ],
            ),
          ),
        ),
      ),
      _ReportSection.weeklyReport => Scaffold(
        appBar: EchoTopBar(
          title: 'Weekly Report',
          onBack: () => setState(() => _section = _ReportSection.hub),
          actions: [
            if (demoEnabled) const EchoStatusPill(label: 'Sample data'),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: demoEnabled
              ? const EchoCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EchoStatusPill(label: 'Sample data'),
                      SizedBox(height: 10),
                      Text(
                        'Weekly Sound Budget (Illustrative)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Mon–Sun sample chart values are placeholders until continuous dB logging is enabled post-migration.',
                        style: TextStyle(
                          fontSize: 13,
                          color: EchoColors.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              : EchoCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Activity Summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        screening.savedSessions.isEmpty &&
                                monitor.trials.isEmpty
                            ? 'No weekly report entries recorded yet.'
                            : 'Saved Screenings: ${screening.savedSessions.length}\nClarity A/B Trials: ${monitor.trials.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: EchoColors.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
      _ReportSection.exposureTrends => Scaffold(
        appBar: EchoTopBar(
          title: 'Exposure Trends',
          onBack: () => setState(() => _section = _ReportSection.hub),
          actions: [
            if (demoEnabled) const EchoStatusPill(label: 'Sample data'),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: EchoCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (demoEnabled) ...[
                  const EchoStatusPill(label: 'Sample data'),
                  const SizedBox(height: 10),
                ],
                Text(
                  demoEnabled
                      ? 'Exposure Trends Preview'
                      : 'No Exposure Trend Logs Available',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EchoColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  demoEnabled
                      ? 'Sample weekly listening exposure trajectory. Long-term background dB logging is out of scope of the initial migration.'
                      : 'Continuous background exposure logging is not yet enabled; microphone audio is analyzed only transiently in RAM.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: EchoColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _ReportSection.insightsTips => Scaffold(
        appBar: EchoTopBar(
          title: 'Insights & Tips',
          onBack: () => setState(() => _section = _ReportSection.hub),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            EchoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Follow the 60/60 Listening Habit',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Keep personal headphone volume modest and take periodic quiet breaks after extended listening sessions.',
                    style: TextStyle(
                      fontSize: 13,
                      color: EchoColors.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            EchoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test in Quiet Environments',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Consistent fit and low ambient noise make preliminary screening patterns far more repeatable over time.',
                    style: TextStyle(
                      fontSize: 13,
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
      _ReportSection.historical => Scaffold(
        appBar: EchoTopBar(
          title: 'Historical Data',
          onBack: () => setState(() => _section = _ReportSection.hub),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (screening.savedSessions.isEmpty && monitor.trials.isEmpty)
                const EchoCard(
                  child: Text(
                    'No historical screening sessions or speech clarity trials saved yet.',
                    style: TextStyle(fontSize: 14, color: EchoColors.muted),
                  ),
                ),
              for (final s in screening.savedSessions) ...[
                EchoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Screening • ${DateFormat.yMMMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(s.startedAt))}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${s.screeningOutcome?.overallClassification.displayName ?? "Incomplete"} • ${s.thresholdResults.length} thresholds',
                        style: const TextStyle(
                          fontSize: 12,
                          color: EchoColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (monitor.trials.isNotEmpty)
                EchoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clarity A/B Trials',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final t in monitor.trials)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '• $t',
                            style: const TextStyle(
                              fontSize: 12,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    };
  }
}
