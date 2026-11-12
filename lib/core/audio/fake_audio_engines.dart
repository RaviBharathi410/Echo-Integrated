import 'dart:async';

import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';

/// Deterministic simulation engine for unit/widget tests and debug simulation drawer.
class FakeStimulusEngine implements StimulusEngine {
  int playCount = 0;
  int stopCount = 0;
  int? lastPlayedFrequency;
  int? lastPlayedLevelDb;
  Ear? lastPlayedEar;
  final List<({int frequencyHz, int levelDb, Ear ear})> playedTones = [];

  final _toneCtrl = StreamController<ToneEvent>.broadcast();
  bool _playing = false;
  int _tokenSeq = 0;

  @override
  Future<String> playTone({
    required int frequencyHz,
    required int levelDb,
    required Ear ear,
    int durationMs = 1200,
  }) async {
    playCount++;
    lastPlayedFrequency = frequencyHz;
    lastPlayedLevelDb = levelDb;
    lastPlayedEar = ear;
    playedTones.add((frequencyHz: frequencyHz, levelDb: levelDb, ear: ear));
    _playing = true;
    final token = 'fake-tone-${++_tokenSeq}';
    _toneCtrl.add(ToneEvent(token: token, state: ToneEventState.started));
    return token;
  }

  @override
  Future<void> stopTone() async {
    stopCount++;
    if (_playing) {
      _playing = false;
      _toneCtrl.add(
        ToneEvent(
          token: 'fake-tone-$_tokenSeq',
          state: ToneEventState.interrupted,
        ),
      );
    }
  }

  void finishCurrentTone() {
    _playing = false;
    _toneCtrl.add(
      ToneEvent(token: 'fake-tone-$_tokenSeq', state: ToneEventState.finished),
    );
  }

  @override
  Stream<ToneEvent> get toneEvents => _toneCtrl.stream;

  @override
  bool isPlaying() => _playing;

  void dispose() {
    unawaited(_toneCtrl.close());
  }
}

/// Deterministic simulated ambient noise monitor for tests and debug simulations.
class FakeNoiseMonitor implements NoiseMonitor {
  final _ctrl = StreamController<NoiseReading>.broadcast();

  NoiseReading _latest = NoiseReading(
    levelDbFs: -55.0,
    assessment: NoiseAssessment.valid,
    isDisturbance: false,
    consecutiveQuietSeconds: 0,
  );
  bool sensorAvailable = true;
  bool monitoringActive = false;

  @override
  NoiseReading get latestReading => _latest;

  @override
  Stream<NoiseReading> get readingStream => _ctrl.stream;

  @override
  Future<bool> startMonitoring() async {
    monitoringActive = sensorAvailable;
    if (!sensorAvailable) {
      injectAssessment(NoiseAssessment.unavailable, -100.0, quietSeconds: 0);
    }
    return monitoringActive;
  }

  @override
  Future<void> stopMonitoring() async {
    monitoringActive = false;
  }

  @override
  Future<bool> isSensorAvailable() async => sensorAvailable;

  void injectAssessment(
    NoiseAssessment assessment,
    double dbFs, {
    int quietSeconds = 0,
  }) {
    _latest = NoiseReading(
      levelDbFs: dbFs,
      assessment: assessment,
      isDisturbance:
          assessment == NoiseAssessment.invalid ||
          assessment == NoiseAssessment.unavailable,
      consecutiveQuietSeconds: assessment == NoiseAssessment.valid
          ? quietSeconds
          : 0,
    );
    _ctrl.add(_latest);
  }

  void emitSimulatedNoise(double dbFs, {int quietSeconds = 0}) {
    final assessment = dbFs > -25.0
        ? NoiseAssessment.invalid
        : dbFs > -35.0
        ? NoiseAssessment.suspect
        : NoiseAssessment.valid;
    injectAssessment(assessment, dbFs, quietSeconds: quietSeconds);
  }

  void emitSimulatedDisturbance() {
    _latest = NoiseReading(
      levelDbFs: -12.0,
      assessment: NoiseAssessment.invalid,
      isDisturbance: true,
      consecutiveQuietSeconds: 0,
    );
    _ctrl.add(_latest);
  }

  void emitQuietSeconds(int seconds) {
    _latest = NoiseReading(
      levelDbFs: -50.0,
      assessment: NoiseAssessment.valid,
      isDisturbance: false,
      consecutiveQuietSeconds: seconds,
    );
    _ctrl.add(_latest);
  }

  @override
  bool checkRecovery({int requiredQuietSeconds = 3}) {
    return !_latest.isDisturbance &&
        _latest.consecutiveQuietSeconds >= requiredQuietSeconds;
  }

  void dispose() {
    unawaited(_ctrl.close());
  }
}

/// Deterministic simulated audio output detector for tests and debug drawer.
class FakeDeviceCapabilityManager implements ScreeningDeviceDetector {
  final _routeCtrl = StreamController<AudioRouteInfo>.broadcast();

  AudioRouteInfo _currentRoute = const AudioRouteInfo(
    routeType: AudioRouteType.wiredHeadphones,
    deviceName: 'Simulated Wired Headphones',
    isStereoCapable: true,
    sampleRateHz: 44100,
    calibrationInfo: CalibrationInfo(
      deviceModel: 'Simulator',
      routeType: AudioRouteType.wiredHeadphones,
      provenance: CalibrationProvenance.simulatedProfile,
      isOfficiallySupported: true,
    ),
  );

  void setSimulatedRoute(AudioRouteType type, {String? name}) {
    _currentRoute = AudioRouteInfo(
      routeType: type,
      deviceName: name ?? type.displayName,
      isStereoCapable: type != AudioRouteType.builtinSpeaker,
      sampleRateHz: 44100,
      calibrationInfo: CalibrationInfo(
        deviceModel: 'Simulator',
        routeType: type,
        provenance: CalibrationProvenance.simulatedProfile,
        isOfficiallySupported: type.isHeadphone,
      ),
    );
    _routeCtrl.add(_currentRoute);
  }

  @override
  Future<AudioRouteInfo> getCurrentAudioRoute() async => _currentRoute;

  @override
  Future<bool> isHeadphoneConnected() async =>
      _currentRoute.routeType.isHeadphone;

  @override
  Stream<AudioRouteInfo> get routeStream => _routeCtrl.stream;

  @override
  CalibrationInfo getCalibrationStatus(AudioRouteType route) {
    return CalibrationInfo(
      deviceModel: 'Simulator',
      routeType: route,
      provenance: CalibrationProvenance.simulatedProfile,
      isOfficiallySupported: route.isHeadphone,
    );
  }

  void dispose() {
    unawaited(_routeCtrl.close());
  }
}

/// Deterministic fake live monitor engine for unit/widget tests & host targets.
class FakeLiveMonitorEngine implements LiveMonitorEngine {
  final _runtimeCtrl = StreamController<MonitorRuntimeEvent>.broadcast();
  final _deviceCtrl = StreamController<MonitorDeviceSnapshot>.broadcast();

  bool _running = false;
  MonitorDspConfig lastAppliedConfig = const MonitorDspConfig();
  int releaseCount = 0;

  // AudioDeviceInfo.TYPE_BUILTIN_SPEAKER == 2, TYPE_WIRED_HEADPHONES == 4
  MonitorDeviceSnapshot _snapshot = const MonitorDeviceSnapshot(
    inputs: [
      DeviceOption(id: 1, label: 'Built-in Mic (1)', type: 15),
      DeviceOption(id: 2, label: 'Wired Headset Mic (2)', type: 3),
    ],
    outputs: [
      DeviceOption(id: 10, label: 'Wired Headphones (10)', type: 4),
      DeviceOption(id: 11, label: 'Speaker (11)', type: 2),
    ],
    defaultInputId: 1,
    defaultOutputId: 10,
  );

  void setDeviceSnapshot(MonitorDeviceSnapshot snapshot) {
    _snapshot = snapshot;
    _deviceCtrl.add(snapshot);
  }

  void emitPeak(double peak, {String streamInfo = 'Fake Oboe Active'}) {
    _runtimeCtrl.add(
      MonitorPeakEvent(
        peak: peak,
        streamInfo: streamInfo,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void emitStopped({String reason = 'disconnected', String message = 'Unplugged'}) {
    _running = false;
    _runtimeCtrl.add(MonitorStoppedEvent(reason: reason, message: message));
  }

  @override
  Stream<MonitorRuntimeEvent> get runtimeEvents => _runtimeCtrl.stream;

  @override
  Stream<MonitorDeviceSnapshot> get deviceChanges => _deviceCtrl.stream;

  @override
  Future<MonitorDeviceSnapshot> getDevices() async => _snapshot;

  @override
  Future<MonitorStartResult> start({
    required int inputId,
    required int outputId,
    required double level,
  }) async {
    final out = _snapshot.outputs.where((d) => d.id == outputId).firstOrNull;
    if (out != null && (out.type == 2 || out.type == 1 || out.type == 24)) {
      return const MonitorStartResult(
        started: false,
        message:
            'Built-in speaker is blocked to prevent acoustic feedback. Connect headphones.',
      );
    }
    _running = true;
    return const MonitorStartResult(
      started: true,
      message: 'Fake Oboe monitor active.',
    );
  }

  @override
  Future<void> stop({String reason = 'user', String message = 'Stopped'}) async {
    _running = false;
    _runtimeCtrl.add(MonitorStoppedEvent(reason: reason, message: message));
  }

  @override
  Future<void> applyDspConfig(MonitorDspConfig config) async {
    lastAppliedConfig = config;
  }

  @override
  Future<void> setMonitorLevel(double level) async {
    lastAppliedConfig = MonitorDspConfig(
      monitorLevel: level,
      gateEnabled: lastAppliedConfig.gateEnabled,
      gateThresholdDb: lastAppliedConfig.gateThresholdDb,
      denoiserEnabled: lastAppliedConfig.denoiserEnabled,
      denoiserStrengthDb: lastAppliedConfig.denoiserStrengthDb,
      compressionEnabled: lastAppliedConfig.compressionEnabled,
      compressionRatio: lastAppliedConfig.compressionRatio,
      processed: lastAppliedConfig.processed,
      gains: lastAppliedConfig.gains,
    );
  }

  @override
  Future<void> setEqualizerBand(int ear, int band, double gainDb) async {
    final copy = lastAppliedConfig.gains.map((r) => [...r]).toList();
    copy[ear][band] = gainDb;
    lastAppliedConfig = MonitorDspConfig(
      monitorLevel: lastAppliedConfig.monitorLevel,
      gateEnabled: lastAppliedConfig.gateEnabled,
      gateThresholdDb: lastAppliedConfig.gateThresholdDb,
      denoiserEnabled: lastAppliedConfig.denoiserEnabled,
      denoiserStrengthDb: lastAppliedConfig.denoiserStrengthDb,
      compressionEnabled: lastAppliedConfig.compressionEnabled,
      compressionRatio: lastAppliedConfig.compressionRatio,
      processed: lastAppliedConfig.processed,
      gains: copy,
    );
  }

  @override
  Future<void> setSpeechCompression({
    required bool enabled,
    required double ratio,
  }) async {}

  @override
  Future<void> setNoiseGate({
    required bool enabled,
    required double thresholdDb,
  }) async {}

  @override
  Future<void> setAdaptiveDenoiser({
    required bool enabled,
    required double strengthDb,
  }) async {}

  @override
  Future<void> setDspBypassed(bool bypassed) async {}

  @override
  Future<String> getStreamInfo() async =>
      _running ? 'Fake Oboe Active' : 'Inactive';

  @override
  Future<bool> isRunning() async => _running;

  void dispose() {
    unawaited(_runtimeCtrl.close());
    unawaited(_deviceCtrl.close());
  }
}

class FakeAudioSessionCoordinator implements AudioSessionCoordinator {
  FakeAudioSessionCoordinator({
    required this.stimulusEngine,
    required this.noiseMonitor,
    required this.liveMonitorEngine,
  });

  final FakeStimulusEngine stimulusEngine;
  final FakeNoiseMonitor noiseMonitor;
  final FakeLiveMonitorEngine liveMonitorEngine;

  int releaseCalls = 0;
  String? lastReleaseReason;
  Map<String, Map<String, dynamic>> legacyPrefsStub = const {};

  @override
  Future<void> releaseAll({String reason = 'backgrounded'}) async {
    releaseCalls++;
    lastReleaseReason = reason;
    await stimulusEngine.stopTone();
    await noiseMonitor.stopMonitoring();
    await liveMonitorEngine.stop(reason: reason, message: 'Released ($reason)');
  }

  @override
  Future<Map<String, Map<String, dynamic>>> readLegacyPrefs() async =>
      legacyPrefsStub;
}
