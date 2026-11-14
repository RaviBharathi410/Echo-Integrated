import 'package:echo_hearing/app/app.dart';
import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
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
    'Home, Reports (release empty state), and Profile edit/export/privacy/signout work cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'echo.user.is_logged_in': true,
        'echo.user.onboarding_completed': true,
        'echo.user.health_notice_accepted': true,
        'echo.user.initial_screening_completed': true,
        'echo.user.user_name': 'Ravi',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = InMemorySessionRepository();
      await repo.saveSession(
        HearingSessionRecord(
          sessionId: 'rep-1',
          startedAt: 1710000000000,
          deviceModel: 'Pixel 8',
          androidVersion: 35,
          isCompleted: true,
          audioRoute: const AudioRouteInfo(
            routeType: AudioRouteType.wiredHeadphones,
            deviceName: 'Headphones',
            isStereoCapable: true,
            sampleRateHz: 44100,
            calibrationInfo: CalibrationInfo(
              deviceModel: 'Pixel 8',
              routeType: AudioRouteType.wiredHeadphones,
              provenance: CalibrationProvenance.uncalibrated,
              isOfficiallySupported: true,
            ),
          ),
          thresholdResults: [
            ThresholdResult(
              ear: Ear.left,
              frequencyHz: 1000,
              thresholdDb: 20,
              validAscendingResponses: 2,
              totalTrialsForTarget: 5,
            ),
          ],
          screeningOutcome: const SessionScreeningOutcome(
            overallClassification: ScreeningOutcomeClassification.pass,
            leftEarSummary: EarScreeningSummary(
              ear: Ear.left,
              classification: ScreeningOutcomeClassification.pass,
              thresholds: [],
              averageLevelDb: 20,
              isComplete: true,
              summaryNotes: 'Pass',
            ),
            rightEarSummary: EarScreeningSummary(
              ear: Ear.right,
              classification: ScreeningOutcomeClassification.pass,
              thresholds: [],
              averageLevelDb: 20,
              isComplete: true,
              summaryNotes: 'Pass',
            ),
            totalTrials: 5,
            contaminatedTrials: 0,
          ),
        ),
      );

      final stimulus = FakeStimulusEngine();
      final noise = FakeNoiseMonitor();
      final detector = FakeDeviceCapabilityManager();
      final monitor = FakeLiveMonitorEngine();
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
          screeningDeviceDetectorProvider.overrideWithValue(detector),
          liveMonitorEngineProvider.overrideWithValue(monitor),
          sessionRepositoryProvider.overrideWithValue(repo),
          permissionGatewayProvider.overrideWithValue(FakePermissionGateway()),
        ],
      );
      // Disable demo data to verify strict non-sample release-style behavior.
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

      // Home tab
      expect(find.text('ECHO Dashboard'), findsOneWidget);
      expect(find.text('Tone Response Profile'), findsOneWidget);

      // Reports tab (release-style empty sample guard)
      await _tapVisible(tester, find.text('Reports'));
      expect(find.text('Listening Reports'), findsOneWidget);
      expect(find.text('Sample data'), findsNothing);
      await _tapVisible(tester, find.text('Exposure Trends'));
      expect(find.text('No Exposure Trend Logs Available'), findsOneWidget);
      await _tapVisible(tester, find.byTooltip('Back'));

      // Profile tab -> Edit -> Export -> Delete -> Sign Out
      await _tapVisible(tester, find.text('Profile'));
      expect(find.text('Ravi'), findsOneWidget);

      await _tapVisible(tester, find.text('Export Data'));
      expect(find.text('Copy JSON to Clipboard'), findsOneWidget);
      await _tapVisible(tester, find.byTooltip('Back'));

      await _tapVisible(tester, find.text('Privacy & Data'));
      await _tapVisible(tester, find.text('Delete Saved Sessions & Reset DSP'));
      expect((await repo.loadAllSessions()), isEmpty);
      await _tapVisible(tester, find.byTooltip('Back'));

      await _tapVisible(tester, find.text('Sign Out'));
      expect(find.text('Welcome to ECHO'), findsOneWidget);
      container.dispose();
    },
  );
}
