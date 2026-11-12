import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/monitor_profile_store.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MonitorScreen extends ConsumerWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(monitorNotifierProvider);
    final notifier = ref.read(monitorNotifierProvider.notifier);
    final demoEnabled = ref.watch(demoDataEnabledProvider);

    return switch (state.subScreen) {
      MonitorSubScreen.main => _MonitorMainView(
        state: state,
        notifier: notifier,
        demoEnabled: demoEnabled,
      ),
      MonitorSubScreen.exposureHistory => _ExposureHistoryView(
        demoEnabled: demoEnabled,
        onBack: () => notifier.openSubScreen(MonitorSubScreen.main),
      ),
      MonitorSubScreen.exposureDetails => _ExposureDetailsView(
        state: state,
        demoEnabled: demoEnabled,
        onBack: () => notifier.openSubScreen(MonitorSubScreen.main),
      ),
      MonitorSubScreen.settings => _MonitorSettingsView(
        state: state,
        notifier: notifier,
        onBack: () => notifier.openSubScreen(MonitorSubScreen.main),
      ),
    };
  }
}

class _MonitorMainView extends StatelessWidget {
  const _MonitorMainView({
    required this.state,
    required this.notifier,
    required this.demoEnabled,
  });

  final MonitorUiState state;
  final MonitorNotifier notifier;
  final bool demoEnabled;

  @override
  Widget build(BuildContext context) {
    final levelTitle = state.running
        ? (state.peak >= 0.6
              ? 'Elevated Output'
              : state.peak >= 0.2
              ? 'Moderate Level'
              : 'Quiet Signal')
        : state.hasSafeHeadphoneOutput
        ? 'Headphones Ready'
        : 'Headphones Required';

    final levelSubtitle = state.running
        ? state.streamInfo
        : state.hasSafeHeadphoneOutput
        ? 'Real-time Oboe monitor standby. Built-in speaker output is blocked.'
        : state.status;

    return Scaffold(
      appBar: EchoTopBar(
        title: 'Sound Monitoring',
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
                        const Expanded(
                          child: Text(
                            'Live Sound Monitor',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                        if (demoEnabled)
                          const EchoStatusPill(label: 'Sample data'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        EchoIconBadge(
                          icon: state.running
                              ? Icons.graphic_eq_rounded
                              : Icons.mic_none_rounded,
                          size: 48,
                          iconSize: 24,
                          containerColor: state.running
                              ? EchoColors.emeraldSoft
                              : EchoColors.surfaceAlt,
                          tint: state.running
                              ? EchoColors.emerald
                              : EchoColors.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                levelTitle,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: EchoColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                levelSubtitle,
                                style: const TextStyle(
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
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: state.running
                            ? state.peak.clamp(0.03, 1.0)
                            : 0.0,
                        minHeight: 8,
                        backgroundColor: EchoColors.surfaceAlt,
                        color: state.peak > 0.75
                            ? EchoColors.amber
                            : EchoColors.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!state.running)
                      EchoPrimaryButton(
                        text: 'Start Live Monitor',
                        icon: Icons.play_arrow_rounded,
                        onPressed: notifier.startMonitoring,
                      )
                    else
                      EchoPrimaryButton(
                        text: 'Stop Live Monitor',
                        icon: Icons.stop_rounded,
                        backgroundColor: EchoColors.rose,
                        onPressed: () => notifier.stopMonitoring(),
                      ),
                    if (state.status.isNotEmpty &&
                        state.status != 'Stopped') ...[
                      const SizedBox(height: 10),
                      Text(
                        state.status,
                        style: TextStyle(
                          fontSize: 12,
                          color: state.status.toLowerCase().contains('blocked')
                              ? EchoColors.rose
                              : EchoColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              EchoOutlinedPillButton(
                text: 'View Exposure History',
                icon: Icons.history_rounded,
                onPressed: () =>
                    notifier.openSubScreen(MonitorSubScreen.exposureHistory),
              ),
              const SizedBox(height: 10),
              EchoOutlinedPillButton(
                text: 'Exposure Details',
                icon: Icons.bar_chart_rounded,
                onPressed: () =>
                    notifier.openSubScreen(MonitorSubScreen.exposureDetails),
              ),
              const SizedBox(height: 10),
              EchoOutlinedPillButton(
                text: 'Monitoring Settings',
                icon: Icons.settings_outlined,
                onPressed: () =>
                    notifier.openSubScreen(MonitorSubScreen.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExposureHistoryView extends StatelessWidget {
  const _ExposureHistoryView({required this.demoEnabled, required this.onBack});

  final bool demoEnabled;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(
        title: 'Exposure History',
        onBack: onBack,
        actions: [
          if (demoEnabled) const EchoStatusPill(label: 'Sample data'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: demoEnabled
              ? const Column(
                  children: [
                    EchoCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EchoStatusPill(label: 'Sample data'),
                          SizedBox(height: 10),
                          Text(
                            'Illustrative 7-Day Sound Exposure',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Today: Moderate ambient average (placeholder metric until background dB logging is implemented).\nYesterday: 94% within daily budget.',
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
                )
              : const EchoCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: EchoColors.primary,
                        size: 32,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'No recorded exposure history.',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Live monitoring processes microphone audio transiently in RAM. Long-term background dB logging is planned for a future update.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
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
    );
  }
}

class _ExposureDetailsView extends StatelessWidget {
  const _ExposureDetailsView({
    required this.state,
    required this.demoEnabled,
    required this.onBack,
  });

  final MonitorUiState state;
  final bool demoEnabled;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(title: 'Exposure Details', onBack: onBack),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              EchoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Real-Time DSP & Safety Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: EchoColors.navy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Engine Stream',
                      value: state.running ? state.streamInfo : 'Inactive',
                    ),
                    _DetailRow(
                      label: 'Current Peak Level',
                      value: '${(state.peak * 100).toStringAsFixed(0)}%',
                    ),
                    _DetailRow(
                      label: 'Headphone Safety Gate',
                      value: state.hasSafeHeadphoneOutput
                          ? 'Active (Speaker Blocked)'
                          : 'Waiting for Headphones',
                    ),
                    _DetailRow(
                      label: 'Processing Mode',
                      value: state.processed
                          ? 'Processed (EQ + Comp + Gate)'
                          : 'Bypassed (Baseline)',
                    ),
                  ],
                ),
              ),
              if (demoEnabled) ...[
                const SizedBox(height: 14),
                const EchoCard(
                  containerColor: EchoColors.surfaceAlt,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EchoStatusPill(label: 'Sample data'),
                      SizedBox(height: 8),
                      Text(
                        'Illustrative daily budget telemetry is shown only in debug sample previews.',
                        style: TextStyle(fontSize: 13, color: EchoColors.muted),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: EchoColors.muted),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: EchoColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitorSettingsView extends StatefulWidget {
  const _MonitorSettingsView({
    required this.state,
    required this.notifier,
    required this.onBack,
  });

  final MonitorUiState state;
  final MonitorNotifier notifier;
  final VoidCallback onBack;

  @override
  State<_MonitorSettingsView> createState() => _MonitorSettingsViewState();
}

class _MonitorSettingsViewState extends State<_MonitorSettingsView> {
  final _correctCtrl = TextEditingController();
  final _totalCtrl = TextEditingController(text: '25');
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.state.realEarNotes);
  }

  @override
  void dispose() {
    _correctCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final n = widget.notifier;

    return Scaffold(
      appBar: EchoTopBar(title: 'Monitoring Settings', onBack: widget.onBack),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            children: [
              // 1. Input/Output Routing + Level
              EchoCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: const Text(
                    'Audio Routing & Output Level',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Microphone Input',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: EchoColors.navy,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          onPressed: n.refreshDevices,
                          tooltip: 'Refresh audio devices',
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final input in s.inputs)
                          EchoChoiceChip(
                            label: input.label,
                            selected: s.inputId == input.id,
                            onTap: () => n.selectInput(input.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Headphone Output (Built-in Speaker Blocked)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: EchoColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final out in s.outputs)
                          EchoChoiceChip(
                            label: MonitorLimits.isBlockedOutputDeviceType(
                                  out.type,
                                )
                                ? '${out.label} (Blocked)'
                                : out.label,
                            selected: s.outputId == out.id,
                            onTap: () => n.selectOutput(out.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Monitor Level',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(s.monitorLevel / MonitorLimits.maxMonitorLevel * 100).round()}%',
                          style: const TextStyle(color: EchoColors.primary),
                        ),
                      ],
                    ),
                    Slider(
                      value: s.monitorLevel,
                      min: 0.0,
                      max: MonitorLimits.maxMonitorLevel,
                      onChanged: n.setMonitorLevel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. 6-Band EQ
              EchoCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: const Text(
                    '6-Band Ear Equalization (±6 dB)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (var ear = 0; ear < 2; ear++) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          ear == 0 ? 'Left Ear Gain (dB)' : 'Right Ear Gain (dB)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: EchoColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (
                        var b = 0;
                        b < MonitorLimits.eqCentersHz.length;
                        b++
                      )
                        Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(
                                '${MonitorLimits.eqCentersHz[b]} Hz',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                value: s.gains[ear][b],
                                min: -MonitorLimits.maxGainDb,
                                max: MonitorLimits.maxGainDb,
                                divisions: 24,
                                onChanged: (v) => n.setGain(ear, b, v),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${s.gains[ear][b] >= 0 ? "+" : ""}${s.gains[ear][b].toStringAsFixed(1)}',
                                textAlign: TextAlign.end,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                    ],
                    EchoOutlinedPillButton(
                      text: 'Reset EQ & DSP Defaults',
                      onPressed: n.resetDefaults,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 3. Dynamic DSP Controls
              EchoCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: const Text(
                    'Noise Gate, Compressor & A/B Bypass',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Processed Audio (A/B Compare)'),
                      subtitle: Text(
                        s.processed ? 'Processed Mode' : 'Baseline Bypassed',
                      ),
                      value: s.processed,
                      onChanged: n.setProcessed,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Noise Gate'),
                      subtitle: Text(
                        '${s.gateThresholdDb.toStringAsFixed(0)} dBFS',
                      ),
                      value: s.gateEnabled,
                      onChanged: n.setGateEnabled,
                    ),
                    Slider(
                      value: s.gateThresholdDb,
                      min: MonitorLimits.minGateThresholdDb,
                      max: MonitorLimits.maxGateThresholdDb,
                      onChanged: s.gateEnabled ? n.setGateThreshold : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Speech Compression'),
                      subtitle: Text(
                        'Ratio ${s.compressionRatio.toStringAsFixed(1)}:1',
                      ),
                      value: s.compressionEnabled,
                      onChanged: n.setCompressionEnabled,
                    ),
                    Slider(
                      value: s.compressionRatio,
                      min: MonitorLimits.minCompressionRatio,
                      max: MonitorLimits.maxCompressionRatio,
                      onChanged: s.compressionEnabled
                          ? n.setCompressionRatio
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Adaptive Denoiser'),
                      subtitle: Text(
                        '${s.denoiserStrengthDb.toStringAsFixed(0)} dB attenuation',
                      ),
                      value: s.denoiserEnabled,
                      onChanged: n.setDenoiserEnabled,
                    ),
                    Slider(
                      value: s.denoiserStrengthDb,
                      min: MonitorLimits.minDenoiserDb,
                      max: MonitorLimits.maxDenoiserDb,
                      onChanged: s.denoiserEnabled
                          ? n.setDenoiserStrength
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Reference Screening Profile & Clarity A/B Log
              EchoCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: const Text(
                    'Reference Screening & Clarity A/B Log',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    EchoOutlinedPillButton(
                      text: 'Import Latest Screening (Reference Only)',
                      icon: Icons.download_rounded,
                      onPressed: n.importLatestScreening,
                    ),
                    if (s.importMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        s.importMessage,
                        style: const TextStyle(
                          fontSize: 12,
                          color: EchoColors.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Real-Ear Comfort Checked'),
                      value: s.realEarVerified,
                      onChanged: n.setRealEarVerified,
                    ),
                    TextField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Real-Ear Verification Notes',
                      ),
                      onChanged: n.setRealEarNotes,
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Log Clarity Trial',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: EchoColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final env in MonitorLimits.environments)
                          EchoChoiceChip(
                            label: env,
                            selected: s.environment == env,
                            onTap: () => n.setEnvironment(env),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _correctCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Correct',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _totalCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Words',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (s.trialMessage.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        s.trialMessage,
                        style: const TextStyle(
                          fontSize: 12,
                          color: EchoColors.rose,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    EchoPrimaryButton(
                      text: 'Save Clarity Trial',
                      onPressed: () async {
                        final ok = await n.saveClarityTrial(
                          _correctCtrl.text,
                          _totalCtrl.text,
                        );
                        if (ok) _correctCtrl.clear();
                      },
                    ),
                    if (s.trials.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final line in s.trials)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '• $line',
                              style: const TextStyle(
                                fontSize: 12,
                                color: EchoColors.navy,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
