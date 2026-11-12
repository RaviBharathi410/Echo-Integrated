import 'dart:async';

import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/features/home/home_screen.dart';
import 'package:echo_hearing/features/monitor/monitor_screen.dart';
import 'package:echo_hearing/features/onboarding/onboarding_screens.dart';
import 'package:echo_hearing/features/profile/profile_screen.dart';
import 'package:echo_hearing/features/reports/reports_screen.dart';
import 'package:echo_hearing/features/screening/screening_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Controls whether active full-screen test flows hide the bottom nav bar.
final hideBottomNavProvider = StateProvider<bool>((ref) => false);

class _RouterRefreshListenable extends ChangeNotifier {
  void trigger() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _RouterRefreshListenable();
  ref.listen(userProfileProvider, (_, _) => refreshListenable.trigger());
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final profile = ref.read(userProfileProvider);
      final location = state.matchedLocation;
      final inOnboarding = location.startsWith('/onboarding');

      if (!profile.onboardingCompleted) {
        if (!inOnboarding) return '/onboarding/welcome';
        // Enforce consent gate before advancing to permissions.
        if (location == '/onboarding/permissions' &&
            !profile.healthNoticeAccepted) {
          return '/onboarding/health-notice';
        }
        return null;
      }
      if (inOnboarding) {
        return profile.initialScreeningCompleted ? '/home' : '/test';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding/account',
        builder: (context, state) => AccountScreen(
          initialRegisterMode: state.uri.queryParameters['mode'] == 'register',
        ),
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/onboarding/health-notice',
        builder: (context, state) => const HealthNoticeScreen(),
      ),
      GoRoute(
        path: '/onboarding/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return EchoMainScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/test',
                builder: (context, state) => const ScreeningShellScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/monitor',
                builder: (context, state) => const MonitorScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reports',
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class EchoMainScaffold extends ConsumerWidget {
  const EchoMainScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabs = [
    (label: 'Test', icon: Icons.hearing_outlined),
    (label: 'Home', icon: Icons.grid_view_rounded),
    (label: 'Monitor', icon: Icons.graphic_eq_rounded),
    (label: 'Reports', icon: Icons.bar_chart_rounded),
    (label: 'Profile', icon: Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideNav = ref.watch(hideBottomNavProvider);
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: hideNav
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: EchoColors.border, width: 1),
                ),
              ),
              child: NavigationBar(
                selectedIndex: currentIndex,
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                indicatorColor: EchoColors.primarySoft,
                height: 70,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: (index) {
                  if (currentIndex == 2 && index != 2) {
                    unawaited(
                      ref.read(liveMonitorEngineProvider).stop(
                        reason: 'tabSwitch',
                        message: 'Live monitor stopped when switching tabs.',
                      ),
                    );
                  }
                  if (index != 0) {
                    ref.read(hideBottomNavProvider.notifier).state = false;
                  }
                  navigationShell.goBranch(
                    index,
                    initialLocation: index == currentIndex,
                  );
                },
                destinations: [
                  for (var i = 0; i < _tabs.length; i++)
                    NavigationDestination(
                      icon: Icon(
                        _tabs[i].icon,
                        color: currentIndex == i
                            ? EchoColors.primary
                            : EchoColors.navy,
                      ),
                      label: _tabs[i].label,
                    ),
                ],
              ),
            ),
    );
  }
}
