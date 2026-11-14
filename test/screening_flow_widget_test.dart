import 'package:echo_hearing/app/app.dart';
import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/core/permissions/permission_gateway.dart';
import 'package:echo_hearing/features/screening/screening_notifier.dart';
import 'package:echo_hearing/features/screening/widgets/audiogram_view.dart';
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
    'Screening UI blocks speaker, switches to headphones, runs bilateral test, and shows empty history in release mode',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'echo.user.is_logged_in': true,
        'echo.user.onboarding_completed': true,
        'echo.user.health_notice_accepted': true,
        'echo.user.initial_screening_completed': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = InMemorySessionRepository();
      final stimulus = FakeStimulusEngine();
      final noise = FakeNoiseMonitor();
      final detector = FakeDeviceCapabilityManager();
      detector.setSimulatedRoute(
        AudioRouteType.builtinSpeaker,
        name: 'Phone Speaker',
      );
      final monitor = FakeLiveMonitorEngine();
      final coordinator = FakeAudioSessionCoordinator(
        stimulusEngine: stimulus,
        noiseMonitor: noise,
        liveMonitorEngine: monitor,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          permissionGatewayProvider.overrideWithValue(FakePermissionGateway()),
          audioCoordinatorProvider.overrideWithValue(coordinator),
          stimulusEngineProvider.overrideWithValue(stimulus),
          noiseMonitorProvider.overrideWithValue(noise),
          screeningDeviceDetectorProvider.overrideWithValue(detector),
          liveMonitorEngineProvider.overrideWithValue(monitor),
          sessionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      container.read(demoDataEnabledProvider.notifier).setEnabled(false);

      addTearDown(() {
        stimulus.dispose();
        noise.dispose();
        detector.dispose();
        monitor.dispose();
        container.dispose();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EchoApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Test tab
      await tester.tap(find.text('Test'));
      await tester.pumpAndSettle();

      expect(find.text('Hearing Screening'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);

      // Release-mode History & Compare empty states (no "Sample #1")
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Screening History'), findsOneWidget);
      expect(find.text('View Latest Record (Sample #1)'), findsNothing);
      await tester.tap(find.text('Compare Screenings'));
      await tester.pumpAndSettle();
      expect(
        find.text('Complete at least two screenings to compare changes over time.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Connect wired headphones + quiet room
      detector.setSimulatedRoute(
        AudioRouteType.wiredHeadphones,
        name: 'Wired Studio Headphones',
      );
      noise.injectAssessment(NoiseAssessment.valid, -56.0, quietSeconds: 3);
      await tapVisible(tester, find.text('Refresh Device & Noise Check'));
      expect(find.text('Connected'), findsOneWidget);

      // Enter Briefing & start screening
      await tapVisible(tester, find.text('Continue to Screening Briefing'));
      expect(find.text('Preliminary Tone Screening'), findsOneWidget);
      await tapVisible(tester, find.text('Begin Screening'));

      // Execute full bilateral modified Hughson-Westlake flow through the UI
      var seenLeftEarPause = false;
      for (var step = 0; step < 400; step++) {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        if (find.text('Screening Results').evaluate().isNotEmpty) {
          break;
        }
        if (find.text('Continue to Right Ear').evaluate().isNotEmpty) {
          seenLeftEarPause = true;
          await tester.tap(find.text('Continue to Right Ear'));
          await tester.pump();
          continue;
        }
        final uiState = container.read(screeningNotifierProvider);
        if (uiState.isWaitingForResponse) {
          if (uiState.currentLevelDb >= 20) {
            await tester.tap(find.text('I Hear It'));
          } else {
            await tester.tap(find.text("Can't Hear It"));
          }
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();

      expect(seenLeftEarPause, isTrue);
      expect(find.text('Screening Results'), findsOneWidget);
      expect(find.byType(AudiogramView), findsOneWidget);
      expect(find.textContaining('not diagnostic'), findsOneWidget);
      expect((await repo.loadAllSessions()).length, 1);
      container.dispose();
    },
  );
}
