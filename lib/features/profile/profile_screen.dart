import 'dart:convert';

import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ProfileSection {
  hub,
  editProfile,
  connectedDevices,
  notifications,
  privacyData,
  exportData,
  aboutEcho,
  helpFaq,
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _ProfileSection _section = _ProfileSection.hub;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final demoEnabled = ref.watch(demoDataEnabledProvider);
    final screening = ref.watch(screeningNotifierProvider);
    final monitor = ref.watch(monitorNotifierProvider);

    return switch (_section) {
      _ProfileSection.hub => Scaffold(
        appBar: const EchoTopBar(title: 'Profile & Settings'),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              children: [
                EchoCard(
                  onTap: () =>
                      setState(() => _section = _ProfileSection.editProfile),
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const EchoIconBadge(
                        icon: Icons.person_rounded,
                        size: 56,
                        iconSize: 28,
                        isCircle: true,
                        containerColor: EchoColors.primarySoft,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: EchoColors.navy,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Standard Listening Profile',
                              style: TextStyle(
                                fontSize: 13,
                                color: EchoColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.edit_outlined,
                        color: EchoColors.primary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                EchoOutlinedPillButton(
                  text: 'Connected Devices',
                  icon: Icons.headphones_outlined,
                  onPressed: () =>
                      setState(() => _section = _ProfileSection.connectedDevices),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Notifications',
                  icon: Icons.notifications_none_rounded,
                  onPressed: () =>
                      setState(() => _section = _ProfileSection.notifications),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Privacy & Data',
                  icon: Icons.lock_outline_rounded,
                  onPressed: () =>
                      setState(() => _section = _ProfileSection.privacyData),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Export Data',
                  icon: Icons.download_outlined,
                  onPressed: () =>
                      setState(() => _section = _ProfileSection.exportData),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'About ECHO',
                  icon: Icons.info_outline_rounded,
                  onPressed: () =>
                      setState(() => _section = _ProfileSection.aboutEcho),
                ),
                const SizedBox(height: 10),
                EchoOutlinedPillButton(
                  text: 'Help & FAQ',
                  icon: Icons.help_outline_rounded,
                  onPressed: () =>
                      setState(() => _section = _ProfileSection.helpFaq),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  EchoCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sample Data Previews (Debug)'),
                      subtitle: const Text(
                        'Show illustrative sample banners where no sessions exist',
                      ),
                      value: demoEnabled,
                      onChanged: (v) => ref
                          .read(demoDataEnabledProvider.notifier)
                          .setEnabled(v),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                EchoOutlinedPillButton(
                  text: 'Sign Out',
                  icon: Icons.logout_rounded,
                  contentColor: EchoColors.rose,
                  borderColor: EchoColors.rose,
                  containerColor: EchoColors.roseSoft,
                  onPressed: () async {
                    await ref.read(monitorNotifierProvider.notifier).stopMonitoring();
                    await ref.read(userProfileProvider.notifier).signOut();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      _ProfileSection.editProfile => _EditProfileSubView(
        onBack: () => setState(() => _section = _ProfileSection.hub),
      ),
      _ProfileSection.connectedDevices => Scaffold(
        appBar: EchoTopBar(
          title: 'Connected Devices',
          onBack: () => setState(() => _section = _ProfileSection.hub),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: EchoCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active Audio Route',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EchoColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  screening.audioRoute?.deviceName ?? 'Checking route...',
                  style: const TextStyle(fontSize: 14, color: EchoColors.navy),
                ),
                const SizedBox(height: 6),
                Text(
                  screening.isHeadphoneConnected
                      ? 'Headphone route verified for screening & live monitor.'
                      : 'No headphone route detected. Connect wired, USB-C, or Bluetooth headphones.',
                  style: const TextStyle(fontSize: 13, color: EchoColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
      _ProfileSection.notifications => Scaffold(
        appBar: EchoTopBar(
          title: 'Notifications',
          onBack: () => setState(() => _section = _ProfileSection.hub),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: EchoCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Screening & Listening Reminders'),
              subtitle: const Text('Local schedule reminders on this device.'),
              value: profile.notificationsEnabled,
              onChanged: (v) => ref
                  .read(userProfileProvider.notifier)
                  .updatePermissions(notificationsEnabled: v),
            ),
          ),
        ),
      ),
      _ProfileSection.privacyData => Scaffold(
        appBar: EchoTopBar(
          title: 'Privacy & Data',
          onBack: () => setState(() => _section = _ProfileSection.hub),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const EchoCard(
                child: Text(
                  'All microphone audio (ambient quietness check and Oboe live monitor) is processed exclusively in RAM on-device. Raw PCM audio is never recorded or uploaded.',
                  style: TextStyle(
                    fontSize: 14,
                    color: EchoColors.navy,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              EchoOutlinedPillButton(
                text: 'Delete Saved Sessions & Reset DSP',
                icon: Icons.delete_outline_rounded,
                contentColor: EchoColors.rose,
                borderColor: EchoColors.rose,
                containerColor: EchoColors.roseSoft,
                onPressed: () async {
                  await ref.read(sessionRepositoryProvider).deleteAllSessions();
                  await ref
                      .read(screeningNotifierProvider.notifier)
                      .refreshSavedSessions();
                  await ref
                      .read(monitorNotifierProvider.notifier)
                      .resetDefaults();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Local sessions and DSP settings cleared.'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      _ProfileSection.exportData => _ExportDataSubView(
        payloadJson: const JsonEncoder.withIndent('  ').convert({
          'profile': profile.toJson(),
          'sessions': screening.savedSessions.map((s) => s.toJson()).toList(),
          'clarityTrials': monitor.trials,
        }),
        onBack: () => setState(() => _section = _ProfileSection.hub),
      ),
      _ProfileSection.aboutEcho => Scaffold(
        appBar: EchoTopBar(
          title: 'About ECHO',
          onBack: () => setState(() => _section = _ProfileSection.hub),
        ),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: EchoCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ECHO Hearing Companion',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: EchoColors.navy,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Version 1.0.0 (Flutter + Native Oboe C++ DSP)\n'
                  'Application ID: com.echo.hearing\n\n'
                  'Preliminary screening & wellness tool, not diagnostic medical equipment.',
                  style: TextStyle(
                    fontSize: 13,
                    color: EchoColors.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _ProfileSection.helpFaq => Scaffold(
        appBar: EchoTopBar(
          title: 'Help & FAQ',
          onBack: () => setState(() => _section = _ProfileSection.hub),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            EchoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why does Live Monitor require headphones?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Built-in device speakers cause immediate acoustic feedback loops with the device microphone and cannot isolate left/right ear channels.',
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
                    'Are screening levels calibrated to dB HL?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EchoColors.navy,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'No. Screening outputs are digital attenuation levels (dBFS) on consumer hardware and are not a substitute for clinical audiometry.',
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
    };
  }
}

class _EditProfileSubView extends ConsumerStatefulWidget {
  const _EditProfileSubView({required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<_EditProfileSubView> createState() =>
      _EditProfileSubViewState();
}

class _EditProfileSubViewState extends ConsumerState<_EditProfileSubView> {
  late final TextEditingController _nameCtrl;
  late String _ageGroup;
  late String _goal;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider);
    _nameCtrl = TextEditingController(text: p.name);
    _ageGroup = p.ageGroup;
    _goal = p.primaryGoal;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(title: 'Edit Profile', onBack: widget.onBack),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in [
                  'Under 18',
                  '18–24',
                  '25–34',
                  '35–44',
                  '45–54',
                  '55+',
                ])
                  EchoChoiceChip(
                    label: g,
                    selected: _ageGroup == g,
                    onTap: () => setState(() => _ageGroup = g),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final goal in [
                  'Daily Clarity & Focus',
                  'Hearing Awareness',
                  'Ambient Noise Tracking',
                  'Speech Enhancement',
                ])
                  EchoChoiceChip(
                    label: goal,
                    selected: _goal == goal,
                    onTap: () => setState(() => _goal = goal),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            EchoPrimaryButton(
              text: 'Save Profile',
              onPressed: () async {
                await ref
                    .read(userProfileProvider.notifier)
                    .updateProfile(
                      name: _nameCtrl.text,
                      ageGroup: _ageGroup,
                      primaryGoal: _goal,
                    );
                widget.onBack();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportDataSubView extends StatelessWidget {
  const _ExportDataSubView({required this.payloadJson, required this.onBack});

  final String payloadJson;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(title: 'Export Data', onBack: onBack),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: EchoCard(
                child: SingleChildScrollView(
                  child: SelectableText(
                    payloadJson,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: EchoColors.navy,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            EchoPrimaryButton(
              text: 'Copy JSON to Clipboard',
              icon: Icons.copy_rounded,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payloadJson));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ECHO data JSON copied to clipboard.'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
