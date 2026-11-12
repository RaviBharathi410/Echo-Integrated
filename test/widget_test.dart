import 'package:echo_hearing/app/app.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'EchoApp boots into onboarding, completes guest flow into 5-tab shell, and releases audio on background',
    (tester) async {
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

      await tester.tap(find.text('Continue as Guest'));
      await tester.pumpAndSettle();

      // Should land inside 5-tab main scaffold (initialScreeningCompleted=false -> Test tab).
      expect(find.text('Hearing Screening'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Verify lifecycle backgrounding calls AudioSessionCoordinator.releaseAll().
      final before = coordinator.releaseCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(coordinator.releaseCalls, greaterThan(before));
    },
  );
}
