import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/daily_exposure_store.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyExposureNotifier & Automatic Headphone Monitoring', () {
    late SharedPreferences prefs;
    late FakeDeviceCapabilityManager detector;
    late FakeNoiseMonitor noise;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      detector = FakeDeviceCapabilityManager();
      detector.setSimulatedRoute(
        AudioRouteType.bluetoothA2dp,
        name: 'Bluetooth Headphones',
      );
      noise = FakeNoiseMonitor();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          screeningDeviceDetectorProvider.overrideWithValue(detector),
          noiseMonitorProvider.overrideWithValue(noise),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      detector.dispose();
      noise.dispose();
    });

    test('initializes with sample exposure when demo mode is active', () {
      final data = container.read(dailyExposureProvider);
      expect(data.isSample, isTrue);
      expect(data.formattedTodayListening, '2h 15m');
      expect(data.formattedCurrentSession, '45m');
      expect(data.ambientLevelText, 'Moderate (Level 2 of 5)');
      expect(data.isHeadphoneConnected, isTrue);
      expect(data.dailyProgress, greaterThan(0.0));
    });

    test('automatically tracks exposure only when headphones are connected', () async {
      final notifier = container.read(dailyExposureProvider.notifier);

      // Simulate headphone connection
      notifier.setHeadphonesConnectedForTesting(true, connType: 'Bluetooth');
      expect(container.read(dailyExposureProvider).isHeadphoneConnected, isTrue);

      // Simulate 10 seconds of listening
      notifier.addSimulatedSeconds(10);
      final current = container.read(dailyExposureProvider);
      expect(current.todayListeningSeconds, greaterThanOrEqualTo(8110));
      expect(current.currentSessionSeconds, greaterThanOrEqualTo(2710));

      // Simulate headphone disconnection
      notifier.setHeadphonesConnectedForTesting(false);
      final disconnected = container.read(dailyExposureProvider);
      expect(disconnected.isHeadphoneConnected, isFalse);
      expect(disconnected.currentSessionSeconds, 0); // resets current session
      expect(disconnected.todayListeningSeconds, greaterThanOrEqualTo(8110)); // preserves total
    });
  });

  group('HomeScreen Dashboard UI Verification', () {
    late SharedPreferences prefs;
    late FakeDeviceCapabilityManager detector;
    late FakeNoiseMonitor noise;
    late FakeStimulusEngine stimulus;
    late FakeLiveMonitorEngine monitor;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'echo.user.onboarding_completed': true,
        'echo.user.is_logged_in': true,
        'echo.user.user_name': 'Alex Parker',
      });
      prefs = await SharedPreferences.getInstance();
      detector = FakeDeviceCapabilityManager();
      detector.setSimulatedRoute(
        AudioRouteType.bluetoothA2dp,
        name: 'Bluetooth Headphones',
      );
      noise = FakeNoiseMonitor();
      stimulus = FakeStimulusEngine();
      monitor = FakeLiveMonitorEngine();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          screeningDeviceDetectorProvider.overrideWithValue(detector),
          noiseMonitorProvider.overrideWithValue(noise),
          stimulusEngineProvider.overrideWithValue(stimulus),
          liveMonitorEngineProvider.overrideWithValue(monitor),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      detector.dispose();
      noise.dispose();
      stimulus.dispose();
      monitor.dispose();
    });

    testWidgets('renders ECHO Dashboard matching screenshots', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TopBar
      expect(find.text('ECHO Dashboard'), findsOneWidget);
      expect(find.text('Sample data'), findsWidgets);

      // Headphones card
      expect(find.text('Headphones Connected'), findsOneWidget);
      expect(find.textContaining('Connected via Bluetooth'), findsOneWidget);

      // Daily Sound Exposure card
      expect(find.text('Daily Sound Exposure'), findsOneWidget);
      expect(find.text("Today's Listening"), findsOneWidget);
      expect(find.text('2h 15m'), findsOneWidget);
      expect(find.text('Ambient Exposure'), findsOneWidget);
      expect(find.text('Moderate (Level 2 of 5)'), findsOneWidget);
      expect(find.text('Current Session'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);

      // Tone Response Profile card
      expect(find.text('Tone Response Profile'), findsOneWidget);
      expect(find.text('Last checked: 3 days ago'), findsOneWidget);
      expect(find.text('Check Response Again'), findsOneWidget);

      // Quick Access
      expect(find.text('Quick Access'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      // Non-diagnostic disclaimer
      expect(find.textContaining('not diagnostic medical equipment'), findsOneWidget);

      container.dispose();
    });
  });
}
