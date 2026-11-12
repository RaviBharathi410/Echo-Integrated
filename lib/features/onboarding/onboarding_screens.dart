import 'package:echo_hearing/app/theme/echo_components.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OnboardingWelcomePlaceholder extends ConsumerWidget {
  const OnboardingWelcomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const EchoTopBar(title: 'ECHO'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Welcome to ECHO'),
              const SizedBox(height: 16),
              EchoPrimaryButton(
                text: 'Get Started',
                onPressed: () => context.go('/onboarding/account'),
              ),
              const SizedBox(height: 12),
              EchoOutlinedPillButton(
                text: 'Continue as Guest',
                onPressed: () async {
                  await ref
                      .read(userProfileProvider.notifier)
                      .saveAccount(name: 'Guest User', email: 'guest@local');
                  await ref
                      .read(userProfileProvider.notifier)
                      .acceptHealthNotice();
                  await ref
                      .read(userProfileProvider.notifier)
                      .completeOnboarding();
                  if (context.mounted) context.go('/test');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingAccountPlaceholder extends StatelessWidget {
  const OnboardingAccountPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: EchoTopBar(title: 'Account'),
      body: Center(child: Text('Account')),
    );
  }
}
