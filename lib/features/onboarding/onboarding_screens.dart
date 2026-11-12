import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/permissions/permission_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const EchoTopBar(title: 'ECHO'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const EchoIconBadge(
                icon: Icons.graphic_eq_rounded,
                size: 72,
                iconSize: 34,
                isCircle: true,
                containerColor: EchoColors.primarySoft,
                tint: EchoColors.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Welcome to ECHO',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Personalized hearing clarity and daily listening monitoring.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: EchoColors.muted,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const _WelcomeFeatureCard(
                icon: Icons.hearing_outlined,
                title: 'Preliminary Sound Screening',
                description:
                    'Fast, non-clinical tone response checks across key speech frequencies.',
              ),
              const SizedBox(height: 12),
              const _WelcomeFeatureCard(
                icon: Icons.headphones_outlined,
                title: 'Acoustic Monitoring',
                description:
                    'Real-time ambient quietness checks and headphone-only audio monitoring.',
              ),
              const SizedBox(height: 12),
              const _WelcomeFeatureCard(
                icon: Icons.tune_rounded,
                title: 'Sound Personalization',
                description:
                    'Customizable multi-band equalization tailored to your listening preferences.',
              ),
              const SizedBox(height: 28),
              EchoPrimaryButton(
                text: 'Get Started',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => context.go('/onboarding/account?mode=register'),
              ),
              const SizedBox(height: 12),
              EchoOutlinedPillButton(
                text: 'I Already Have an Account',
                onPressed: () => context.go('/onboarding/account?mode=signin'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeatureCard extends StatelessWidget {
  const _WelcomeFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return EchoCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EchoIconBadge(
            icon: icon,
            size: 46,
            iconSize: 22,
            containerColor: EchoColors.surfaceAlt,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: EchoColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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
    );
  }
}

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, this.initialRegisterMode = false});

  final bool initialRegisterMode;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late bool _isRegister = widget.initialRegisterMode;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final TextEditingController _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    _nameCtrl = TextEditingController(
      text: profile.name == 'Guest User' ? '' : profile.name,
    );
    _emailCtrl = TextEditingController(
      text: profile.email == 'guest@local' ? 'alex@example.com' : profile.email,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit({bool asGuest = false}) async {
    final notifier = ref.read(userProfileProvider.notifier);
    if (asGuest) {
      await notifier.saveAccount(name: 'Guest User', email: 'guest@local');
    } else {
      final email = _emailCtrl.text.trim().isEmpty
          ? 'alex@example.com'
          : _emailCtrl.text.trim();
      final fallbackName = email.contains('@')
          ? email.split('@').first
          : 'ECHO Listener';
      final name = _nameCtrl.text.trim().isEmpty
          ? fallbackName
          : _nameCtrl.text.trim();
      await notifier.saveAccount(name: name, email: email);
    }
    if (mounted) {
      context.go('/onboarding/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(
        title: 'Account',
        onBack: () => context.go('/onboarding/welcome'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isRegister ? 'Create Account' : 'Welcome Back',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _isRegister
                    ? 'Create a local profile to store your baseline and hearing sessions.'
                    : 'Sign in to access your saved screening history.',
                style: const TextStyle(fontSize: 14, color: EchoColors.muted),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _ModeTabButton(
                      label: 'Sign In',
                      selected: !_isRegister,
                      onTap: () => setState(() => _isRegister = false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeTabButton(
                      label: 'Register',
                      selected: _isRegister,
                      onTap: () => setState(() => _isRegister = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (_isRegister) ...[
                const Text(
                  'Full Name',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EchoColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Alex Parker',
                    prefixIcon: Icon(
                      Icons.person_outline_rounded,
                      color: EchoColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Email Address',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'alex@example.com',
                  prefixIcon: Icon(
                    Icons.mail_outline_rounded,
                    color: EchoColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Password',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: '••••••••',
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: EchoColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              EchoPrimaryButton(
                text: _isRegister ? 'Create Account' : 'Sign In',
                icon: Icons.check_rounded,
                onPressed: () => _submit(asGuest: false),
              ),
              const SizedBox(height: 12),
              EchoOutlinedPillButton(
                text: 'Continue as Guest',
                icon: Icons.person_outline_rounded,
                onPressed: () => _submit(asGuest: true),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Profiles and credentials remain private on this device. No data is transmitted externally.',
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

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Material(
        color: selected ? EchoColors.primary : EchoColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? EchoColors.primary : EchoColors.pillBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : EchoColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  static const _ageGroups = ['Under 18', '18–24', '25–34', '35–44', '45–54', '55+'];
  static const _goals = [
    'Daily Clarity & Focus',
    'Hearing Awareness',
    'Ambient Noise Tracking',
    'Speech Enhancement',
  ];
  static const _devices = [
    'Wireless Earbuds / Headphones',
    'Wired Headphones',
    'USB-C Audio Headset',
  ];

  late final TextEditingController _nameCtrl;
  late String _selectedAge;
  late String _selectedGoal;
  late String _selectedDevice;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userProfileProvider);
    _nameCtrl = TextEditingController(text: p.name);
    _selectedAge = p.ageGroup;
    _selectedGoal = p.primaryGoal;
    _selectedDevice = p.devicePreference;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    await ref
        .read(userProfileProvider.notifier)
        .updateProfile(
          name: _nameCtrl.text,
          ageGroup: _selectedAge,
          primaryGoal: _selectedGoal,
          devicePreference: _selectedDevice,
        );
    if (mounted) {
      context.go('/onboarding/health-notice');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(
        title: 'Listening Profile',
        onBack: () => context.go('/onboarding/account'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Personalize Your Setup',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'ECHO tailors screening prompts and live listening controls to your preferences.',
                style: TextStyle(fontSize: 14, color: EchoColors.muted),
              ),
              const SizedBox(height: 20),
              const Text(
                'Display Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: 'Alex Parker'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Age Group',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final age in _ageGroups)
                    EchoChoiceChip(
                      label: age,
                      selected: _selectedAge == age,
                      onTap: () => setState(() => _selectedAge = age),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Primary Goal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final goal in _goals)
                    EchoChoiceChip(
                      label: goal,
                      selected: _selectedGoal == goal,
                      onTap: () => setState(() => _selectedGoal = goal),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Preferred Listening Device',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: EchoColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final dev in _devices)
                    EchoChoiceChip(
                      label: dev,
                      selected: _selectedDevice == dev,
                      onTap: () => setState(() => _selectedDevice = dev),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              EchoPrimaryButton(
                text: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: _saveAndContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HealthNoticeScreen extends ConsumerStatefulWidget {
  const HealthNoticeScreen({super.key});

  @override
  ConsumerState<HealthNoticeScreen> createState() => _HealthNoticeScreenState();
}

class _HealthNoticeScreenState extends ConsumerState<HealthNoticeScreen> {
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _acknowledged = ref.read(userProfileProvider).healthNoticeAccepted;
  }

  Future<void> _acceptAndContinue() async {
    if (!_acknowledged) return;
    await ref.read(userProfileProvider.notifier).acceptHealthNotice();
    if (mounted) {
      context.go('/onboarding/permissions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(
        title: 'Health Notice',
        onBack: () => context.go('/onboarding/profile'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            children: [
              EchoCard(
                padding: const EdgeInsets.all(20),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: EchoColors.primary,
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Important Health Notice',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EchoColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'ECHO provides a preliminary screening, not a substitute for professional audiological assessment.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: EchoColors.navy,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'This software application does not perform calibrated medical diagnosis or clinical audiometry. Sound response indicators, ambient exposure levels, and listening estimates are indicative only and intended for personal audio habit awareness.',
                      style: TextStyle(
                        fontSize: 14,
                        color: EchoColors.muted,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'If you experience persistent ear discomfort, tinnitus, or sudden changes in hearing ability, consult a certified audiologist or physician.',
                      style: TextStyle(
                        fontSize: 14,
                        color: EchoColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _acknowledged = !_acknowledged),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _acknowledged,
                        activeColor: EchoColors.primary,
                        onChanged: (v) =>
                            setState(() => _acknowledged = v ?? false),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'I understand that ECHO provides a preliminary screening, not a substitute for professional audiological assessment.',
                            style: TextStyle(
                              fontSize: 14,
                              color: EchoColors.navy,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              EchoPrimaryButton(
                text: 'Accept & Continue',
                icon: Icons.check_rounded,
                enabled: _acknowledged,
                onPressed: _acceptAndContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  bool _micGranted = false;
  bool _notificationsGranted = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _syncCurrentStatuses();
  }

  Future<void> _syncCurrentStatuses() async {
    final gateway = ref.read(permissionGatewayProvider);
    final mic = await gateway.isMicrophoneGranted();
    final notif = await gateway.isNotificationsGranted();
    if (!mounted) return;
    setState(() {
      _micGranted = mic || ref.read(userProfileProvider).micPermissionGranted;
      _notificationsGranted = notif;
    });
  }

  Future<void> _toggleMic(bool desired) async {
    if (_loading) return;
    if (!desired) {
      await ref
          .read(userProfileProvider.notifier)
          .updatePermissions(micGranted: false);
      setState(() => _micGranted = false);
      return;
    }
    setState(() => _loading = true);
    final granted = await ref
        .read(permissionGatewayProvider)
        .requestMicrophone();
    await ref
        .read(userProfileProvider.notifier)
        .updatePermissions(micGranted: granted);
    if (!mounted) return;
    setState(() {
      _micGranted = granted;
      _loading = false;
    });
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone access is needed for ambient quietness checks and live sound monitoring.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleNotifications(bool desired) async {
    if (desired) {
      final granted = await ref
          .read(permissionGatewayProvider)
          .requestNotifications();
      await ref
          .read(userProfileProvider.notifier)
          .updatePermissions(notificationsEnabled: granted);
      if (mounted) setState(() => _notificationsGranted = granted);
    } else {
      await ref
          .read(userProfileProvider.notifier)
          .updatePermissions(notificationsEnabled: false);
      if (mounted) setState(() => _notificationsGranted = false);
    }
  }

  Future<void> _finishOnboarding() async {
    await ref
        .read(userProfileProvider.notifier)
        .updatePermissions(
          micGranted: _micGranted,
          notificationsEnabled: _notificationsGranted,
        );
    await ref.read(userProfileProvider.notifier).completeOnboarding();
    if (mounted) {
      context.go('/test');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EchoTopBar(
        title: 'Permissions',
        onBack: () => context.go('/onboarding/health-notice'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Permissions',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Audio levels are analyzed transiently in RAM. No raw microphone audio is recorded or saved.',
                style: TextStyle(fontSize: 14, color: EchoColors.muted, height: 1.4),
              ),
              const SizedBox(height: 20),
              _PermissionTile(
                icon: Icons.mic_none_rounded,
                title: 'Microphone Permission',
                subtitle:
                    'Used for ambient room noise checks and the live headphone monitor.',
                trailing: Switch(
                  value: _micGranted,
                  activeThumbColor: Colors.white,
                  activeTrackColor: EchoColors.primary,
                  onChanged: _toggleMic,
                ),
              ),
              const SizedBox(height: 12),
              _PermissionTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications Permission',
                subtitle: 'Daily listening reminders and screening follow-up alerts.',
                trailing: Switch(
                  value: _notificationsGranted,
                  activeThumbColor: Colors.white,
                  activeTrackColor: EchoColors.primary,
                  onChanged: _toggleNotifications,
                ),
              ),
              const SizedBox(height: 12),
              const _PermissionTile(
                icon: Icons.headphones_outlined,
                title: 'Audio Output Detection',
                subtitle:
                    'Automatically verifies wired, USB-C, or Bluetooth headphone routing.',
                trailing: EchoStatusPill(
                  label: 'Active',
                  icon: Icons.check_circle_outline_rounded,
                  containerColor: EchoColors.emeraldSoft,
                  borderColor: EchoColors.emeraldSoft,
                  contentColor: EchoColors.emerald,
                ),
              ),
              const SizedBox(height: 28),
              EchoPrimaryButton(
                text: 'Continue to Device Setup',
                icon: Icons.arrow_forward_rounded,
                onPressed: _finishOnboarding,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return EchoCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          EchoIconBadge(
            icon: icon,
            size: 44,
            iconSize: 22,
            containerColor: EchoColors.surfaceAlt,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: EchoColors.navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: EchoColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
