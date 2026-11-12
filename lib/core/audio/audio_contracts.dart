import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/foundation.dart';

/// Platform-neutral ambient noise reading (transient RAM analysis only).
@immutable
class NoiseReading {
  NoiseReading({
    required this.levelDbFs,
    required this.assessment,
    required this.isDisturbance,
    required this.consecutiveQuietSeconds,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  final double levelDbFs;
  final NoiseAssessment assessment;
  final bool isDisturbance;
  final int consecutiveQuietSeconds;
  final int timestamp;
}

enum ToneEventState { started, finished, interrupted, focusLost }

@immutable
class ToneEvent {
  const ToneEvent({required this.token, required this.state});
  final String token;
  final ToneEventState state;
}

@immutable
class DeviceOption {
  const DeviceOption({required this.id, required this.label, this.type = 0});
  final int id;
  final String label;
  final int type;
}

@immutable
class MonitorDeviceSnapshot {
  const MonitorDeviceSnapshot({
    required this.inputs,
    required this.outputs,
    this.defaultInputId,
    this.defaultOutputId,
  });

  final List<DeviceOption> inputs;
  final List<DeviceOption> outputs;
  final int? defaultInputId;
  final int? defaultOutputId;
}

@immutable
class MonitorDspConfig {
  const MonitorDspConfig({
    this.monitorLevel = 0.15,
    this.gateEnabled = true,
    this.gateThresholdDb = -54.0,
    this.denoiserEnabled = false,
    this.denoiserStrengthDb = 9.0,
    this.compressionEnabled = true,
    this.compressionRatio = 2.0,
    this.processed = true,
    this.gains = const [
      [0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0],
    ],
  });

  final double monitorLevel;
  final bool gateEnabled;
  final double gateThresholdDb;
  final bool denoiserEnabled;
  final double denoiserStrengthDb;
  final bool compressionEnabled;
  final double compressionRatio;
  final bool processed;
  final List<List<double>> gains;
}

sealed class MonitorRuntimeEvent {
  const MonitorRuntimeEvent();
}

final class MonitorPeakEvent extends MonitorRuntimeEvent {
  const MonitorPeakEvent({
    required this.peak,
    required this.streamInfo,
    required this.timestampMs,
  });
  final double peak;
  final String streamInfo;
  final int timestampMs;
}

final class MonitorStoppedEvent extends MonitorRuntimeEvent {
  const MonitorStoppedEvent({required this.reason, required this.message});
  final String reason;
  final String message;
}

final class MonitorStartResult {
  const MonitorStartResult({required this.started, required this.message});
  final bool started;
  final String message;
}

/// Platform-neutral session lifecycle coordinator contract.
/// On Android, wraps AudioSessionCoordinator (Oboe + AudioTrack + AudioRecord);
/// a future iOS AVAudioEngine backend implements this same interface.
abstract interface class AudioSessionCoordinator {
  Future<void> releaseAll({String reason = 'backgrounded'});
  Future<Map<String, Map<String, dynamic>>> readLegacyPrefs();
}

/// Platform-neutral audio output route & calibration capability manager.
abstract interface class ScreeningDeviceDetector {
  Future<AudioRouteInfo> getCurrentAudioRoute();
  Future<bool> isHeadphoneConnected();
  Stream<AudioRouteInfo> get routeStream;
  CalibrationInfo getCalibrationStatus(AudioRouteType route);
}

/// Platform-neutral ambient noise monitor contract.
abstract interface class NoiseMonitor {
  NoiseReading get latestReading;
  Stream<NoiseReading> get readingStream;
  Future<bool> startMonitoring();
  Future<void> stopMonitoring();
  Future<bool> isSensorAvailable();
  bool checkRecovery({int requiredQuietSeconds = 3});
}

/// Platform-neutral audiometric pure-tone stimulus playback contract.
abstract interface class StimulusEngine {
  Future<String> playTone({
    required int frequencyHz,
    required int levelDb,
    required Ear ear,
    int durationMs = 1200,
  });

  Future<void> stopTone();
  Stream<ToneEvent> get toneEvents;
  bool isPlaying();
}

/// Platform-neutral low-latency live audio DSP monitor contract.
abstract interface class LiveMonitorEngine {
  Stream<MonitorRuntimeEvent> get runtimeEvents;
  Stream<MonitorDeviceSnapshot> get deviceChanges;
  Future<MonitorDeviceSnapshot> getDevices();
  Future<MonitorStartResult> start({
    required int inputId,
    required int outputId,
    required double level,
  });
  Future<void> stop({String reason = 'user', String message = 'Stopped'});
  Future<void> applyDspConfig(MonitorDspConfig config);
  Future<void> setMonitorLevel(double level);
  Future<void> setEqualizerBand(int ear, int band, double gainDb);
  Future<void> setSpeechCompression({
    required bool enabled,
    required double ratio,
  });
  Future<void> setNoiseGate({
    required bool enabled,
    required double thresholdDb,
  });
  Future<void> setAdaptiveDenoiser({
    required bool enabled,
    required double strengthDb,
  });
  Future<void> setDspBypassed(bool bypassed);
  Future<String> getStreamInfo();
  Future<bool> isRunning();
}
