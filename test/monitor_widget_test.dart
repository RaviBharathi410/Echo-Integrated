import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/app/theme/echo_theme.dart';
import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:echo_hearing/features/monitor/monitor_notifier.dart';
import 'package:echo_hearing/features/monitor/monitor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<
    ({
      ProviderContainer container,
      FakeLiveMonitorEngine engine,
      InMemorySessionRepository repo,
    })
  >
  createContainer({bool demoData = true}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final stimulus = FakeStimulusEngine();
    final noise = FakeNoiseMonitor();
    final detector = FakeDeviceCapabilityManager();
    final monitor = FakeLiveMonitorEngine();
    final coordinator = FakeAudioSessionCoordinator(
      stimulusEngine: stimulus,
      noiseMonitor: noise,
      liveMonitorEngine: monitor,
    );
    final repo = InMemorySessionRepository();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioCoordinatorProvider.overrideWithValue(coordinator),
        stimulusEngineProvider.overrideWithValue(stimulus),
        noiseMonitorProvider.overrideWithValue(noise),
        screeningDeviceDetectorProvider.overrideWithValue(detector),
        liveMonitorEngineProvider.overrideWithValue(monitor),
        sessionRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.read(demoDataEnabledProvider.notifier).setEnabled(demoData);
    addTearDown(() {
      stimulus.dispose();
      noise.dispose();
      detector.dispose();
      monitor.dispose();
      container.dispose();
    });
    await container.read(monitorNotifierProvider.notifier).refreshDevices();
    return (container: container, engine: monitor, repo: repo);
  }

  test('blocks built-in speaker output while allowing wired headphones', () async {
    final ctx = await createContainer();
    final notifier = ctx.container.read(monitorNotifierProvider.notifier);

    // Built-in speaker has AudioDeviceInfo.TYPE_BUILTIN_SPEAKER (type = 2)
    ctx.engine.setDeviceSnapshot(
      const MonitorDeviceSnapshot(
        inputs: [DeviceOption(id: 1, label: 'Mic (1)', type: 15)],
        outputs: [DeviceOption(id: 11, label: 'Phone Speaker (11)', type: 2)],
        defaultInputId: 1,
        defaultOutputId: 11,
      ),
    );
    await notifier.refreshDevices();
    await notifier.startMonitoring();

    var state = ctx.container.read(monitorNotifierProvider);
    expect(state.running, isFalse);
    expect(state.status.toLowerCase(), contains('blocked'));

    // Connect headphones (type = 4)
    ctx.engine.setDeviceSnapshot(
      const MonitorDeviceSnapshot(
        inputs: [DeviceOption(id: 1, label: 'Mic (1)', type: 15)],
        outputs: [DeviceOption(id: 10, label: 'Wired Headphones (10)', type: 4)],
        defaultInputId: 1,
        defaultOutputId: 10,
      ),
    );
    await notifier.refreshDevices();
    await notifier.startMonitoring();

    state = ctx.container.read(monitorNotifierProvider);
    expect(state.running, isTrue);
  });

  test('DSP gain clamping and importLatestScreening never change EQ gain', () async {
    final ctx = await createContainer();
    final notifier = ctx.container.read(monitorNotifierProvider.notifier);

    await notifier.setGain(0, 2, 12.0); // exceeds +6 dB max
    expect(ctx.container.read(monitorNotifierProvider).gains[0][2], 6.0);

    await notifier.setGain(0, 2, 0.0);
    await ctx.repo.saveSession(
      HearingSessionRecord(
        sessionId: 's-1',
        startedAt: 1710000000000,
        deviceModel: 'Pixel',
        androidVersion: 35,
        audioRoute: const AudioRouteInfo(
          routeType: AudioRouteType.wiredHeadphones,
          deviceName: 'Headset',
          isStereoCapable: true,
          sampleRateHz: 44100,
          calibrationInfo: CalibrationInfo(
            deviceModel: 'Pixel',
            routeType: AudioRouteType.wiredHeadphones,
            provenance: CalibrationProvenance.uncalibrated,
            isOfficiallySupported: true,
          ),
        ),
        thresholdResults: [
          ThresholdResult(
            ear: Ear.left,
            frequencyHz: 1000,
            thresholdDb: 35,
            validAscendingResponses: 2,
            totalTrialsForTarget: 5,
          ),
        ],
      ),
    );

    await notifier.importLatestScreening();
    final state = ctx.container.read(monitorNotifierProvider);
    expect(state.thresholds[0][2], '35');
    expect(state.gains[0][2], 0.0);
    expect(state.importMessage, contains('do not change any gain'));
  });

  test('clarity trial log validates counts and stores pipe-delimited record', () async {
    final ctx = await createContainer();
    final notifier = ctx.container.read(monitorNotifierProvider.notifier);

    expect(await notifier.saveClarityTrial('30', '20'), isFalse);
    expect(
      ctx.container.read(monitorNotifierProvider).trialMessage,
      isNotEmpty,
    );

    expect(await notifier.saveClarityTrial('18', '20'), isTrue);
    final trials = ctx.container.read(monitorNotifierProvider).trials;
    expect(trials.length, 1);
    expect(trials.first, contains('18/20 (90%)'));
  });

  testWidgets('Exposure history shows genuine empty state when demo data disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final ctx = await createContainer(demoData: false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ctx.container,
        child: MaterialApp(theme: EchoTheme.light(), home: const MonitorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sample data'), findsNothing);
    await tester.tap(find.text('View Exposure History'));
    await tester.pumpAndSettle();
    expect(find.text('No recorded exposure history.'), findsOneWidget);
  });
}
