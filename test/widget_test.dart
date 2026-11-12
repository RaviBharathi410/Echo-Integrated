import 'package:echo_hearing/app/app.dart';
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
  testWidgets(
    'EchoApp boots into onboarding, completes consent + permissions into 5-tab shell, and releases audio on background',
    (tester) async {
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

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          audioCoordinatorProvider.overrideWithValue(coordinator),
          stimulusEngineProvider.overrideWithValue(stimulus),
          noiseMonitorProvider.overrideWithValue(noise),
          liveMonitorEngineProvider.overrideWithValue(monitor),
          screeningDeviceDetectorProvider.overrideWithValue(detector),
          permissionGatewayProvider.overrideWithValue(FakePermissionGateway()),
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
        UncontrolledProviderScope(
          container: container,
          child: const EchoApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome to ECHO'), findsOneWidget);

      await _tapVisible(tester, find.text('Get Started'));
      await _tapVisible(tester, find.text('Continue as Guest'));
      await _tapVisible(tester, find.text('Continue'));

      await _tapVisible(tester, find.byType(Checkbox));
      await _tapVisible(tester, find.text('Accept & Continue'));

      await _tapVisible(tester, find.text('Continue to Device Setup'));

      // Should land inside 5-tab main scaffold (initialScreeningCompleted=false -> Test tab).
      expect(find.text('Hearing Screening'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      final before = coordinator.releaseCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(coordinator.releaseCalls, greaterThan(before));
    },
  );
}
