import 'package:echo_hearing/app/app.dart';
import 'package:echo_hearing/app/router.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/permissions/permission_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  Future<
    ({
      ProviderContainer container,
      FakePermissionGateway permissions,
      FakeAudioSessionCoordinator coordinator,
    })
  >
  pumpOnboardingApp(WidgetTester tester, {bool micGranted = true}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final stimulus = FakeStimulusEngine();
    final noise = FakeNoiseMonitor();
    final monitor = FakeLiveMonitorEngine();
    final detector = FakeDeviceCapabilityManager();
    final coordinator = FakeAudioSessionCoordinator(
      stimulusEngine: stimulus,
      noiseMonitor: noise,
      liveMonitorEngine: monitor,
    );
    final permissions = FakePermissionGateway(
      micGranted: micGranted,
      notificationsGranted: true,
    );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioCoordinatorProvider.overrideWithValue(coordinator),
        stimulusEngineProvider.overrideWithValue(stimulus),
        noiseMonitorProvider.overrideWithValue(noise),
        liveMonitorEngineProvider.overrideWithValue(monitor),
        screeningDeviceDetectorProvider.overrideWithValue(detector),
        permissionGatewayProvider.overrideWithValue(permissions),
      ],
    );
    addTearDown(() {
      stimulus.dispose();
      noise.dispose();
      monitor.dispose();
      detector.dispose();
      container.dispose();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EchoApp()),
    );
    await tester.pumpAndSettle();
    return (
      container: container,
      permissions: permissions,
      coordinator: coordinator,
    );
  }

  testWidgets(
    'Full onboarding wizard enforces Health Notice checkbox and persists OS mic permission',
    (tester) async {
      final ctx = await pumpOnboardingApp(tester, micGranted: true);

      expect(find.text('Welcome to ECHO'), findsOneWidget);
      await _tapVisible(tester, find.text('Get Started'));

      // Account screen in Register mode.
      expect(find.text('Create Account'), findsWidgets);
      await _tapVisible(tester, find.text('Continue as Guest'));

      // Profile setup screen.
      expect(find.text('Personalize Your Setup'), findsOneWidget);
      await _tapVisible(tester, find.text('35–44'));
      await _tapVisible(tester, find.text('Continue'));

      // Health Notice consent gate: button must be disabled until checkbox checked.
      expect(find.text('Important Health Notice'), findsOneWidget);
      final buttonBefore = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(buttonBefore.onPressed, isNull);

      // Direct navigation to permissions before accepting consent redirects back.
      ctx.container.read(routerProvider).go('/onboarding/permissions');
      await tester.pumpAndSettle();
      expect(find.text('Important Health Notice'), findsOneWidget);

      await _tapVisible(tester, find.byType(Checkbox));

      final buttonAfter = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(buttonAfter.onPressed, isNotNull);

      await _tapVisible(tester, find.text('Accept & Continue'));

      // Permissions screen.
      expect(find.text('System Permissions'), findsOneWidget);
      expect(
        ctx.container.read(userProfileProvider).healthNoticeAccepted,
        isTrue,
      );

      await _tapVisible(tester, find.byType(Switch).first);
      expect(ctx.permissions.micRequests, greaterThanOrEqualTo(0));

      await _tapVisible(tester, find.text('Continue to Device Setup'));

      expect(ctx.container.read(userProfileProvider).onboardingCompleted, isTrue);
      expect(find.text('Hearing Screening'), findsOneWidget);
    },
  );
}
