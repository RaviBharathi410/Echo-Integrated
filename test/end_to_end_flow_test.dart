import 'package:echo_hearing/app/app.dart';
import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/permissions/permission_gateway.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'End-to-end flow: Onboarding -> Baseline Screening -> Auto Monitor Sync -> Home -> Safe Monitor -> Sign Out',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = InMemorySessionRepository();
      final stimulus = FakeStimulusEngine();
      final noise = FakeNoiseMonitor();
      final detector = FakeDeviceCapabilityManager();
      final monitorEngine = FakeLiveMonitorEngine();
      final coordinator = FakeAudioSessionCoordinator(
        stimulusEngine: stimulus,
        noiseMonitor: noise,
        liveMonitorEngine: monitorEngine,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          permissionGatewayProvider.overrideWithValue(FakePermissionGateway()),
          audioCoordinatorProvider.overrideWithValue(coordinator),
          stimulusEngineProvider.overrideWithValue(stimulus),
          noiseMonitorProvider.overrideWithValue(noise),
          screeningDeviceDetectorProvider.overrideWithValue(detector),
          liveMonitorEngineProvider.overrideWithValue(monitorEngine),
          sessionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      container.read(demoDataEnabledProvider.notifier).setEnabled(false);

      addTearDown(() {
        stimulus.dispose();
        noise.dispose();
        detector.dispose();
        monitorEngine.dispose();
        container.dispose();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EchoApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Onboarding wizard
      await tapVisible(tester, find.text('Get Started'));
      await tapVisible(tester, find.text('Continue as Guest'));
      await tapVisible(tester, find.text('Continue'));
      await tapVisible(tester, find.byType(Checkbox));
      await tapVisible(tester, find.text('Accept & Continue'));
      await tapVisible(tester, find.text('Continue to Device Setup'));

      // Initial baseline screening opens automatically for new users
      expect(find.text('Initial Baseline Screening'), findsOneWidget);
      noise.injectAssessment(NoiseAssessment.valid, -56.0, quietSeconds: 3);

      // 2. Complete Initial Baseline Screening
      await tapVisible(tester, find.text('Continue to Screening Briefing'));
      await tapVisible(tester, find.text('Begin Initial Screening'));

      for (var step = 0; step < 400; step++) {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
        if (find.text('Screening Results').evaluate().isNotEmpty) {
          break;
        }
        if (find.text('Continue to Right Ear').evaluate().isNotEmpty) {
          await tester.tap(find.text('Continue to Right Ear'));
          await tester.pump();
          continue;
        }
        final uiState = container.read(screeningNotifierProvider);
        if (uiState.isWaitingForResponse) {
          if (uiState.currentLevelDb >= 20) {
            await tester.tap(find.text('I Hear It'));
          } else {
            await tester.tap(find.text("I Can't Hear It"));
          }
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();

      expect(find.text('Screening Results'), findsOneWidget);
      expect(
        container.read(userProfileProvider).initialScreeningCompleted,
        isTrue,
      );

      // Verify automatic Monitor reference sync occurred without overwriting flat gains
      final syncedMonitor = container.read(monitorNotifierProvider);
      expect(
        syncedMonitor.importMessage,
        contains('reference only. They do not change any gain'),
      );
      expect(syncedMonitor.gains[0], List<double>.filled(6, 0.0));
      expect(syncedMonitor.gains[1], List<double>.filled(6, 0.0));

      // 3. Home tab shows Latest Screening card and no longer shows Initial Baseline Pending
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Initial Baseline Pending'), findsNothing);
      expect(find.text('Latest Screening'), findsOneWidget);

      // 4. Open Monitor tab: verify built-in speaker block vs headphone start, and tab switch stop
      monitorEngine.setDeviceSnapshot(
        const MonitorDeviceSnapshot(
          inputs: [DeviceOption(id: 1, label: 'Mic (1)', type: 15)],
          outputs: [DeviceOption(id: 11, label: 'Speaker (11)', type: 2)],
          defaultInputId: 1,
          defaultOutputId: 11,
        ),
      );
      await tester.tap(find.text('Monitor'));
      await tester.pumpAndSettle();
      await container.read(monitorNotifierProvider.notifier).refreshDevices();
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Start Live Monitor'));
      expect(container.read(monitorNotifierProvider).running, isFalse);

      // Plug in headphones & start monitor cleanly
      monitorEngine.setDeviceSnapshot(
        const MonitorDeviceSnapshot(
          inputs: [DeviceOption(id: 1, label: 'Mic (1)', type: 15)],
          outputs: [DeviceOption(id: 10, label: 'Headphones (10)', type: 4)],
          defaultInputId: 1,
          defaultOutputId: 10,
        ),
      );
      await container.read(monitorNotifierProvider.notifier).refreshDevices();
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Start Live Monitor'));
      expect(container.read(monitorNotifierProvider).running, isTrue);

      // Switching away from Monitor stops live monitor engine automatically
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(await monitorEngine.isRunning(), isFalse);

      // 5. Sign Out returns cleanly to Welcome onboarding
      await tapVisible(tester, find.text('Sign Out'));
      expect(find.text('Welcome to ECHO'), findsOneWidget);
    },
  );
}
