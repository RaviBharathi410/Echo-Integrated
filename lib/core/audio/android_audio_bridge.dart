import 'dart:async';
import 'dart:math' as math;

import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/services.dart';

/// Shared dispatcher around `com.echo.hearing/audio_control` + `audio_events`.
///
/// One native Kotlin `AudioSessionCoordinator` enforces the "single mic + single
/// output stream" rule across stimulus playback, ambient noise monitoring, and
/// the Oboe live DSP monitor.
class AndroidAudioBridge
    implements
        AudioSessionCoordinator,
        ScreeningDeviceDetector,
        NoiseMonitor,
        StimulusEngine,
        LiveMonitorEngine {
  AndroidAudioBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _method =
           methodChannel ??
           const MethodChannel('com.echo.hearing/audio_control'),
       _events =
           eventChannel ?? const EventChannel('com.echo.hearing/audio_events');

  final MethodChannel _method;
  final EventChannel _events;

  StreamSubscription<dynamic>? _eventSub;

  final _noiseCtrl = StreamController<NoiseReading>.broadcast();
  final _toneCtrl = StreamController<ToneEvent>.broadcast();
  final _routeCtrl = StreamController<AudioRouteInfo>.broadcast();
  final _deviceSnapCtrl = StreamController<MonitorDeviceSnapshot>.broadcast();
  final _monitorCtrl = StreamController<MonitorRuntimeEvent>.broadcast();

  NoiseReading _latestNoise = NoiseReading(
    levelDbFs: -60.0,
    assessment: NoiseAssessment.valid,
    isDisturbance: false,
    consecutiveQuietSeconds: 0,
  );
  bool _tonePlaying = false;

  void _ensureListening() {
    _eventSub ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    switch (map['type'] as String?) {
      case 'noiseReading':
        final reading = NoiseReading(
          levelDbFs: (map['levelDbFs'] as num?)?.toDouble() ?? -60.0,
          assessment: NoiseAssessment.fromJsonName(
            map['assessment'] as String?,
          ),
          isDisturbance: (map['isDisturbance'] as bool?) ?? false,
          consecutiveQuietSeconds:
              (map['consecutiveQuietSeconds'] as num?)?.toInt() ?? 0,
          timestamp: (map['timestampMs'] as num?)?.toInt(),
        );
        _latestNoise = reading;
        _noiseCtrl.add(reading);
        break;
      case 'toneState':
        final token = (map['token'] as String?) ?? '';
        final stateStr = (map['state'] as String?) ?? 'finished';
        final state = switch (stateStr) {
          'started' => ToneEventState.started,
          'interrupted' => ToneEventState.interrupted,
          'focusLost' => ToneEventState.focusLost,
          _ => ToneEventState.finished,
        };
        _tonePlaying = state == ToneEventState.started;
        _toneCtrl.add(ToneEvent(token: token, state: state));
        break;
      case 'devicesChanged':
        final routeRaw = map['screeningRoute'];
        if (routeRaw is Map) {
          _routeCtrl.add(
            AudioRouteInfo.fromJson(Map<String, dynamic>.from(routeRaw)),
          );
        }
        final monRaw = map['monitorDevices'];
        if (monRaw is Map) {
          _deviceSnapCtrl.add(
            _parseMonitorSnapshot(Map<String, dynamic>.from(monRaw)),
          );
        }
        break;
      case 'monitorPeak':
        _monitorCtrl.add(
          MonitorPeakEvent(
            peak: (map['peak'] as num?)?.toDouble() ?? 0.0,
            streamInfo: (map['streamInfo'] as String?) ?? 'Inactive',
            timestampMs:
                (map['timestampMs'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          ),
        );
        break;
      case 'monitorStopped':
        _monitorCtrl.add(
          MonitorStoppedEvent(
            reason: (map['reason'] as String?) ?? 'user',
            message: (map['message'] as String?) ?? 'Stopped',
          ),
        );
        break;
    }
  }

  MonitorDeviceSnapshot _parseMonitorSnapshot(Map<String, dynamic> map) {
    List<DeviceOption> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((item) {
        final m = Map<String, dynamic>.from(item);
        return DeviceOption(
          id: (m['id'] as num?)?.toInt() ?? 0,
          label: (m['label'] as String?) ?? 'Unknown',
          type: (m['type'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    }

    return MonitorDeviceSnapshot(
      inputs: parseList(map['inputs']),
      outputs: parseList(map['outputs']),
      defaultInputId: (map['defaultInputId'] as num?)?.toInt(),
      defaultOutputId: (map['defaultOutputId'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> releaseAll({String reason = 'backgrounded'}) async {
    _tonePlaying = false;
    await _method.invokeMethod<void>('releaseAllAudio', {'reason': reason});
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readLegacyPrefs() async {
    final raw = await _method.invokeMethod<dynamic>('readLegacyPrefs');
    if (raw is! Map) return const {};
    final result = <String, Map<String, dynamic>>{};
    raw.forEach((key, value) {
      if (key is String && value is Map) {
        result[key] = Map<String, dynamic>.from(value);
      }
    });
    return result;
  }

  // --- ScreeningDeviceDetector ---

  @override
  Future<AudioRouteInfo> getCurrentAudioRoute() async {
    _ensureListening();
    final raw = await _method.invokeMethod<dynamic>('getScreeningAudioRoute');
    if (raw is Map) {
      return AudioRouteInfo.fromJson(Map<String, dynamic>.from(raw));
    }
    return const AudioRouteInfo(
      routeType: AudioRouteType.otherUnsupported,
      deviceName: 'Unknown Audio Output',
      isStereoCapable: true,
      sampleRateHz: 44100,
      calibrationInfo: CalibrationInfo(
        deviceModel: 'Unknown',
        routeType: AudioRouteType.otherUnsupported,
        provenance: CalibrationProvenance.uncalibrated,
        isOfficiallySupported: false,
      ),
    );
  }

  @override
  Future<bool> isHeadphoneConnected() async {
    final route = await getCurrentAudioRoute();
    return route.routeType.isHeadphone;
  }

  @override
  Stream<AudioRouteInfo> get routeStream {
    _ensureListening();
    return _routeCtrl.stream;
  }

  @override
  CalibrationInfo getCalibrationStatus(AudioRouteType route) {
    return CalibrationInfo(
      deviceModel: 'Android Device',
      routeType: route,
      provenance: CalibrationProvenance.uncalibrated,
      isOfficiallySupported: route.isHeadphone,
    );
  }

  // --- NoiseMonitor ---

  @override
  NoiseReading get latestReading => _latestNoise;

  @override
  Stream<NoiseReading> get readingStream {
    _ensureListening();
    return _noiseCtrl.stream;
  }

  @override
  Future<bool> startMonitoring() async {
    _ensureListening();
    final ok = await _method.invokeMethod<bool>('startNoiseMonitor');
    return ok ?? false;
  }

  @override
  Future<void> stopMonitoring() async {
    await _method.invokeMethod<void>('stopNoiseMonitor');
  }

  @override
  Future<bool> isSensorAvailable() async {
    final ok = await _method.invokeMethod<bool>('isNoiseSensorAvailable');
    return ok ?? false;
  }

  @override
  bool checkRecovery({int requiredQuietSeconds = 3}) {
    return !_latestNoise.isDisturbance &&
        _latestNoise.consecutiveQuietSeconds >= requiredQuietSeconds;
  }

  // --- StimulusEngine ---

  @override
  Future<String> playTone({
    required int frequencyHz,
    required int levelDb,
    required Ear ear,
    int durationMs = 1200,
  }) async {
    _ensureListening();
    _tonePlaying = true;
    final token = await _method.invokeMethod<String>('playTone', {
      'frequencyHz': frequencyHz,
      'levelDb': levelDb,
      'ear': ear == Ear.left ? 'left' : 'right',
      'durationMs': durationMs,
    });
    return token ?? '';
  }

  @override
  Future<void> stopTone() async {
    _tonePlaying = false;
    await _method.invokeMethod<void>('stopTone');
  }

  @override
  Stream<ToneEvent> get toneEvents {
    _ensureListening();
    return _toneCtrl.stream;
  }

  @override
  bool isPlaying() => _tonePlaying;

  // --- LiveMonitorEngine ---

  @override
  Stream<MonitorRuntimeEvent> get runtimeEvents {
    _ensureListening();
    return _monitorCtrl.stream;
  }

  @override
  Stream<MonitorDeviceSnapshot> get deviceChanges {
    _ensureListening();
    return _deviceSnapCtrl.stream;
  }

  @override
  Future<MonitorDeviceSnapshot> getDevices() async {
    _ensureListening();
    final raw = await _method.invokeMethod<dynamic>('getMonitorDevices');
    if (raw is Map) {
      return _parseMonitorSnapshot(Map<String, dynamic>.from(raw));
    }
    return const MonitorDeviceSnapshot(inputs: [], outputs: []);
  }

  @override
  Future<MonitorStartResult> start({
    required int inputId,
    required int outputId,
    required double level,
  }) async {
    _ensureListening();
    final raw = await _method.invokeMethod<dynamic>('startMonitor', {
      'inputId': inputId,
      'outputId': outputId,
      'level': level,
    });
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      return MonitorStartResult(
        started: (m['started'] as bool?) ?? false,
        message: (m['message'] as String?) ?? 'Monitor start failed.',
      );
    }
    return const MonitorStartResult(
      started: false,
      message: 'Monitor start failed.',
    );
  }

  @override
  Future<void> stop({
    String reason = 'user',
    String message = 'Stopped',
  }) async {
    await _method.invokeMethod<void>('stopMonitor', {
      'reason': reason,
      'message': message,
    });
  }

  @override
  Future<void> applyDspConfig(MonitorDspConfig config) async {
    await setMonitorLevel(config.monitorLevel);
    await setNoiseGate(
      enabled: config.gateEnabled,
      thresholdDb: config.gateThresholdDb,
    );
    await setAdaptiveDenoiser(
      enabled: config.denoiserEnabled,
      strengthDb: config.denoiserStrengthDb,
    );
    await setSpeechCompression(
      enabled: config.compressionEnabled,
      ratio: config.compressionRatio,
    );
    for (var ear = 0; ear < math.min(2, config.gains.length); ear++) {
      for (var band = 0; band < math.min(6, config.gains[ear].length); band++) {
        await setEqualizerBand(ear, band, config.gains[ear][band]);
      }
    }
    await setDspBypassed(!config.processed);
  }

  @override
  Future<void> setMonitorLevel(double level) async {
    await _method.invokeMethod<void>('setMonitorLevel', {'level': level});
  }

  @override
  Future<void> setEqualizerBand(int ear, int band, double gainDb) async {
    await _method.invokeMethod<void>('setEqualizerBand', {
      'ear': ear,
      'band': band,
      'gainDb': gainDb,
    });
  }

  @override
  Future<void> setSpeechCompression({
    required bool enabled,
    required double ratio,
  }) async {
    await _method.invokeMethod<void>('setSpeechCompression', {
      'enabled': enabled,
      'ratio': ratio,
    });
  }

  @override
  Future<void> setNoiseGate({
    required bool enabled,
    required double thresholdDb,
  }) async {
    await _method.invokeMethod<void>('setNoiseGate', {
      'enabled': enabled,
      'thresholdDb': thresholdDb,
    });
  }

  @override
  Future<void> setAdaptiveDenoiser({
    required bool enabled,
    required double strengthDb,
  }) async {
    await _method.invokeMethod<void>('setAdaptiveDenoiser', {
      'enabled': enabled,
      'strengthDb': strengthDb,
    });
  }

  @override
  Future<void> setDspBypassed(bool bypassed) async {
    await _method.invokeMethod<void>('setDspBypassed', {'bypassed': bypassed});
  }

  @override
  Future<String> getStreamInfo() async {
    return (await _method.invokeMethod<String>('getMonitorStreamInfo')) ??
        'Inactive';
  }

  @override
  Future<bool> isRunning() async {
    return (await _method.invokeMethod<bool>('isMonitorRunning')) ?? false;
  }

  void dispose() {
    unawaited(_eventSub?.cancel());
    unawaited(_noiseCtrl.close());
    unawaited(_toneCtrl.close());
    unawaited(_routeCtrl.close());
    unawaited(_deviceSnapCtrl.close());
    unawaited(_monitorCtrl.close());
  }
}
