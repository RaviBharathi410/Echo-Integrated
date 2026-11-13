import 'package:echo_hearing/core/audio/android_audio_bridge.dart';
import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const controlChannel = MethodChannel('com.echo.hearing/audio_control');
  const eventsChannelName = 'com.echo.hearing/audio_events';

  late List<MethodCall> calls;
  late AndroidAudioBridge bridge;

  Future<void> emitPlatformEvent(Map<String, dynamic> payload) async {
    final encoded = const StandardMethodCodec().encodeSuccessEnvelope(payload);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(eventsChannelName, encoded, (_) {});
  }

  setUp(() {
    calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(controlChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getScreeningAudioRoute':
          return <String, dynamic>{
            'routeType': AudioRouteType.wiredHeadphones.toJsonName(),
            'deviceName': 'Test USB-C Headphones',
            'isStereoCapable': true,
            'sampleRateHz': 48000,
            'calibrationInfo': <String, dynamic>{
              'deviceModel': 'Pixel 8',
              'routeType': AudioRouteType.wiredHeadphones.toJsonName(),
              'provenance': CalibrationProvenance.uncalibrated.toJsonName(),
              'isOfficiallySupported': true,
            },
          };
        case 'startNoiseMonitor':
          return true;
        case 'playTone':
          return 'native-tone-42';
        case 'getMonitorDevices':
          return <String, dynamic>{
            'inputs': [
              {'id': 1, 'label': 'Built-in Mic (1)', 'type': 15},
            ],
            'outputs': [
              {'id': 10, 'label': 'Wired Headphones (10)', 'type': 4},
              {'id': 11, 'label': 'Speaker (11)', 'type': 2},
            ],
            'defaultInputId': 1,
            'defaultOutputId': 10,
          };
        case 'startMonitor':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final outId = args['outputId'] as int;
          if (outId == 11) {
            return <String, dynamic>{
              'started': false,
              'message': 'Built-in speaker is blocked.',
            };
          }
          return <String, dynamic>{
            'started': true,
            'message': 'Oboe full-duplex running',
          };
        case 'getMonitorStreamInfo':
          return '48000 Hz • Oboe LowLatency';
        case 'isMonitorRunning':
          return true;
        case 'readLegacyPrefs':
          return <String, dynamic>{
            'echo_profile': <String, dynamic>{
              'g0_2': 3.5,
              'proc': true,
            },
          };
        default:
          return null;
      }
    });

    messenger.setMockMethodCallHandler(
      const MethodChannel(eventsChannelName),
      (call) async => null,
    );

    bridge = AndroidAudioBridge();
  });

  tearDown(() {
    bridge.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(controlChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventsChannelName),
      null,
    );
  });

  test('serializes MethodChannel calls and decodes responses accurately', () async {
    final route = await bridge.getCurrentAudioRoute();
    expect(route.routeType, AudioRouteType.wiredHeadphones);
    expect(route.deviceName, 'Test USB-C Headphones');
    expect(route.sampleRateHz, 48000);

    expect(await bridge.startMonitoring(), isTrue);
    await bridge.stopMonitoring();

    final token = await bridge.playTone(
      frequencyHz: 1000,
      levelDb: 45,
      ear: Ear.left,
      durationMs: 1200,
    );
    expect(token, 'native-tone-42');
    expect(bridge.isPlaying(), isTrue);
    await bridge.stopTone();
    expect(bridge.isPlaying(), isFalse);

    final devices = await bridge.getDevices();
    expect(devices.inputs.length, 1);
    expect(devices.outputs.length, 2);
    expect(devices.defaultOutputId, 10);

    final blocked = await bridge.start(inputId: 1, outputId: 11, level: 0.75);
    expect(blocked.started, isFalse);

    final started = await bridge.start(inputId: 1, outputId: 10, level: 0.75);
    expect(started.started, isTrue);

    await bridge.setEqualizerBand(0, 2, 4.5);
    await bridge.setMonitorLevel(0.8);
    await bridge.setNoiseGate(enabled: true, thresholdDb: -42.0);
    await bridge.setAdaptiveDenoiser(enabled: true, strengthDb: 12.0);
    await bridge.setSpeechCompression(enabled: true, ratio: 3.0);
    await bridge.setDspBypassed(false);
    await bridge.stop(reason: 'user', message: 'Stopped');
    await bridge.releaseAll(reason: 'backgrounded');

    final legacy = await bridge.readLegacyPrefs();
    expect(legacy['echo_profile']?['g0_2'], 3.5);
    expect(legacy['echo_profile']?['proc'], isTrue);

    expect(
      calls.map((c) => c.method).toList(),
      containsAll(<String>[
        'getScreeningAudioRoute',
        'startNoiseMonitor',
        'stopNoiseMonitor',
        'playTone',
        'stopTone',
        'getMonitorDevices',
        'startMonitor',
        'setEqualizerBand',
        'setMonitorLevel',
        'setNoiseGate',
        'setAdaptiveDenoiser',
        'setSpeechCompression',
        'setDspBypassed',
        'stopMonitor',
        'releaseAllAudio',
        'readLegacyPrefs',
      ]),
    );

    final eqCall = calls.firstWhere((c) => c.method == 'setEqualizerBand');
    expect(eqCall.arguments, {'ear': 0, 'band': 2, 'gainDb': 4.5});

    final toneCall = calls.firstWhere((c) => c.method == 'playTone');
    expect(toneCall.arguments, {
      'frequencyHz': 1000,
      'levelDb': 45,
      'ear': 'left',
      'durationMs': 1200,
    });
  });

  test('decodes EventChannel broadcasts for noise, tones, devices, peaks, and stop', () async {
    final noiseFuture = bridge.readingStream.first;
    final toneFuture = bridge.toneEvents.take(2).toList();
    final routeFuture = bridge.routeStream.first;
    final devicesFuture = bridge.deviceChanges.first;
    final monitorEventsFuture = bridge.runtimeEvents.take(2).toList();

    await Future<void>.delayed(Duration.zero);

    await emitPlatformEvent({
      'type': 'noiseReading',
      'levelDbFs': -18.5,
      'assessment': NoiseAssessment.invalid.toJsonName(),
      'isDisturbance': true,
      'consecutiveQuietSeconds': 0,
      'timestampMs': 123456,
    });

    await emitPlatformEvent({
      'type': 'toneState',
      'token': 't-1',
      'state': 'started',
    });
    await emitPlatformEvent({
      'type': 'toneState',
      'token': 't-1',
      'state': 'focusLost',
    });

    await emitPlatformEvent({
      'type': 'devicesChanged',
      'screeningRoute': {
        'routeType': AudioRouteType.bluetoothA2dp.toJsonName(),
        'deviceName': 'Galaxy Buds',
        'isStereoCapable': true,
        'sampleRateHz': 44100,
        'calibrationInfo': {
          'deviceModel': 'Pixel',
          'routeType': AudioRouteType.bluetoothA2dp.toJsonName(),
          'provenance': CalibrationProvenance.uncalibrated.toJsonName(),
          'isOfficiallySupported': true,
        },
      },
      'monitorDevices': {
        'inputs': [
          {'id': 2, 'label': 'BT Mic', 'type': 7},
        ],
        'outputs': [
          {'id': 12, 'label': 'BT Audio', 'type': 8},
        ],
        'defaultInputId': 2,
        'defaultOutputId': 12,
      },
    });

    await emitPlatformEvent({
      'type': 'monitorPeak',
      'peak': 0.42,
      'streamInfo': '48000 Hz',
      'timestampMs': 999,
    });
    await emitPlatformEvent({
      'type': 'monitorStopped',
      'reason': 'disconnected',
      'message': 'Headphones unplugged',
    });

    final noise = await noiseFuture;
    expect(noise.levelDbFs, -18.5);
    expect(noise.assessment, NoiseAssessment.invalid);
    expect(noise.isDisturbance, isTrue);

    final tones = await toneFuture;
    expect(tones[0].state, ToneEventState.started);
    expect(tones[1].state, ToneEventState.focusLost);
    expect(bridge.isPlaying(), isFalse);

    final route = await routeFuture;
    expect(route.routeType, AudioRouteType.bluetoothA2dp);
    expect(route.deviceName, 'Galaxy Buds');

    final snap = await devicesFuture;
    expect(snap.outputs.single.id, 12);

    final monEvents = await monitorEventsFuture;
    expect(monEvents[0], isA<MonitorPeakEvent>());
    expect((monEvents[0] as MonitorPeakEvent).peak, 0.42);
    expect(monEvents[1], isA<MonitorStoppedEvent>());
    expect((monEvents[1] as MonitorStoppedEvent).reason, 'disconnected');
  });
}
