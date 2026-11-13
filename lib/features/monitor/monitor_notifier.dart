import 'dart:async';

import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/data/monitor_profile_store.dart';
import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum MonitorSubScreen { main, exposureHistory, exposureDetails, settings }

@immutable
class MonitorUiState {
  const MonitorUiState({
    this.subScreen = MonitorSubScreen.main,
    this.running = false,
    this.status = 'Stopped',
    this.streamInfo = 'Inactive',
    this.peak = 0.0,
    this.inputs = const [],
    this.outputs = const [],
    this.inputId,
    this.outputId,
    this.monitorLevel = MonitorLimits.initialMonitorLevel,
    this.gateEnabled = true,
    this.gateThresholdDb = MonitorLimits.initialGateThresholdDb,
    this.denoiserEnabled = false,
    this.denoiserStrengthDb = MonitorLimits.initialDenoiserDb,
    this.compressionEnabled = true,
    this.compressionRatio = MonitorLimits.initialCompressionRatio,
    this.processed = true,
    this.gains = const [
      [0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0],
    ],
    this.thresholds = const [
      ['', '', '', '', '', ''],
      ['', '', '', '', '', ''],
    ],
    this.realEarVerified = false,
    this.realEarNotes = '',
    this.importMessage = '',
    this.environment = 'Quiet',
    this.trials = const [],
    this.trialMessage = '',
  });

  final MonitorSubScreen subScreen;
  final bool running;
  final String status;
  final String streamInfo;
  final double peak;
  final List<DeviceOption> inputs;
  final List<DeviceOption> outputs;
  final int? inputId;
  final int? outputId;
  final double monitorLevel;
  final bool gateEnabled;
  final double gateThresholdDb;
  final bool denoiserEnabled;
  final double denoiserStrengthDb;
  final bool compressionEnabled;
  final double compressionRatio;
  final bool processed;
  final List<List<double>> gains;
  final List<List<String>> thresholds;
  final bool realEarVerified;
  final String realEarNotes;
  final String importMessage;
  final String environment;
  final List<String> trials;
  final String trialMessage;

  bool get hasSafeHeadphoneOutput {
    final id = outputId;
    if (id == null) return false;
    final match = outputs.where((d) => d.id == id).firstOrNull;
    if (match == null) return false;
    return !MonitorLimits.isBlockedOutputDeviceType(match.type);
  }

  MonitorDspConfig toDspConfig() => MonitorDspConfig(
    monitorLevel: monitorLevel,
    gateEnabled: gateEnabled,
    gateThresholdDb: gateThresholdDb,
    denoiserEnabled: denoiserEnabled,
    denoiserStrengthDb: denoiserStrengthDb,
    compressionEnabled: compressionEnabled,
    compressionRatio: compressionRatio,
    processed: processed,
    gains: gains,
  );

  MonitorUiState copyWith({
    MonitorSubScreen? subScreen,
    bool? running,
    String? status,
    String? streamInfo,
    double? peak,
    List<DeviceOption>? inputs,
    List<DeviceOption>? outputs,
    int? Function()? inputId,
    int? Function()? outputId,
    double? monitorLevel,
    bool? gateEnabled,
    double? gateThresholdDb,
    bool? denoiserEnabled,
    double? denoiserStrengthDb,
    bool? compressionEnabled,
    double? compressionRatio,
    bool? processed,
    List<List<double>>? gains,
    List<List<String>>? thresholds,
    bool? realEarVerified,
    String? realEarNotes,
    String? importMessage,
    String? environment,
    List<String>? trials,
    String? trialMessage,
  }) {
    return MonitorUiState(
      subScreen: subScreen ?? this.subScreen,
      running: running ?? this.running,
      status: status ?? this.status,
      streamInfo: streamInfo ?? this.streamInfo,
      peak: peak ?? this.peak,
      inputs: inputs ?? this.inputs,
      outputs: outputs ?? this.outputs,
      inputId: inputId != null ? inputId() : this.inputId,
      outputId: outputId != null ? outputId() : this.outputId,
      monitorLevel: monitorLevel ?? this.monitorLevel,
      gateEnabled: gateEnabled ?? this.gateEnabled,
      gateThresholdDb: gateThresholdDb ?? this.gateThresholdDb,
      denoiserEnabled: denoiserEnabled ?? this.denoiserEnabled,
      denoiserStrengthDb: denoiserStrengthDb ?? this.denoiserStrengthDb,
      compressionEnabled: compressionEnabled ?? this.compressionEnabled,
      compressionRatio: compressionRatio ?? this.compressionRatio,
      processed: processed ?? this.processed,
      gains: gains ?? this.gains,
      thresholds: thresholds ?? this.thresholds,
      realEarVerified: realEarVerified ?? this.realEarVerified,
      realEarNotes: realEarNotes ?? this.realEarNotes,
      importMessage: importMessage ?? this.importMessage,
      environment: environment ?? this.environment,
      trials: trials ?? this.trials,
      trialMessage: trialMessage ?? this.trialMessage,
    );
  }
}

class MonitorNotifier extends Notifier<MonitorUiState> {
  LiveMonitorEngine get _engine => ref.read(liveMonitorEngineProvider);
  MonitorProfileStore get _store => ref.read(monitorProfileStoreProvider);
  SessionRepository get _repo => ref.read(sessionRepositoryProvider);
  AudioSessionCoordinator get _coordinator =>
      ref.read(audioCoordinatorProvider);

  StreamSubscription<MonitorRuntimeEvent>? _runtimeSub;
  StreamSubscription<MonitorDeviceSnapshot>? _deviceSub;

  @override
  MonitorUiState build() {
    final saved = _store.load();
    _runtimeSub = _engine.runtimeEvents.listen(_onRuntimeEvent);
    _deviceSub = _engine.deviceChanges.listen(_applyDeviceSnapshot);
    ref.onDispose(() {
      unawaited(_runtimeSub?.cancel());
      unawaited(_deviceSub?.cancel());
    });

    unawaited(_initAsync());

    return MonitorUiState(
      monitorLevel: saved.monitorLevel,
      gateEnabled: saved.gateEnabled,
      gateThresholdDb: saved.gateThresholdDb,
      denoiserEnabled: saved.denoiserEnabled,
      denoiserStrengthDb: saved.denoiserStrengthDb,
      compressionEnabled: saved.compressionEnabled,
      compressionRatio: saved.compressionRatio,
      processed: saved.processed,
      gains: saved.gains,
      thresholds: saved.thresholds,
      realEarVerified: saved.realEarVerified,
      realEarNotes: saved.realEarNotes,
      environment: saved.environment,
      trials: saved.trialsFormatted,
    );
  }

  Future<void> _initAsync() async {
    final migrated = await _store.importLegacyIfNeeded(_coordinator);
    if (migrated) {
      final restored = _store.load();
      state = state.copyWith(
        monitorLevel: restored.monitorLevel,
        gateEnabled: restored.gateEnabled,
        gateThresholdDb: restored.gateThresholdDb,
        denoiserEnabled: restored.denoiserEnabled,
        denoiserStrengthDb: restored.denoiserStrengthDb,
        compressionEnabled: restored.compressionEnabled,
        compressionRatio: restored.compressionRatio,
        processed: restored.processed,
        gains: restored.gains,
        thresholds: restored.thresholds,
        realEarVerified: restored.realEarVerified,
        realEarNotes: restored.realEarNotes,
        environment: restored.environment,
        trials: restored.trialsFormatted,
      );
    }
    await refreshDevices();
  }

  void _onRuntimeEvent(MonitorRuntimeEvent event) {
    switch (event) {
      case MonitorPeakEvent(:final peak, :final streamInfo):
        state = state.copyWith(
          peak: peak,
          streamInfo: streamInfo,
        );
        break;
      case MonitorStoppedEvent(:final message):
        state = state.copyWith(
          running: false,
          peak: 0.0,
          status: message,
          streamInfo: 'Inactive',
        );
        break;
    }
  }

  void _applyDeviceSnapshot(MonitorDeviceSnapshot snap) {
    final nextIn =
        snap.inputs.any((d) => d.id == state.inputId)
            ? state.inputId
            : (snap.defaultInputId ?? snap.inputs.firstOrNull?.id);

    // Prefer non-blocked headphone output when auto-selecting.
    final safeOutputs = snap.outputs
        .where((d) => !MonitorLimits.isBlockedOutputDeviceType(d.type))
        .toList();
    int? nextOut = state.outputId;
    if (nextOut == null ||
        !snap.outputs.any((d) => d.id == nextOut) ||
        MonitorLimits.isBlockedOutputDeviceType(
          snap.outputs.firstWhere((d) => d.id == nextOut).type,
        )) {
      if (snap.defaultOutputId != null &&
          safeOutputs.any((d) => d.id == snap.defaultOutputId)) {
        nextOut = snap.defaultOutputId;
      } else {
        nextOut = safeOutputs.firstOrNull?.id ?? snap.outputs.firstOrNull?.id;
      }
    }

    state = state.copyWith(
      inputs: snap.inputs,
      outputs: snap.outputs,
      inputId: () => nextIn,
      outputId: () => nextOut,
    );
  }

  Future<void> refreshDevices() async {
    final snap = await _engine.getDevices();
    _applyDeviceSnapshot(snap);
  }

  void openSubScreen(MonitorSubScreen subScreen) {
    state = state.copyWith(subScreen: subScreen);
  }

  void selectInput(int id) {
    state = state.copyWith(inputId: () => id);
  }

  void selectOutput(int id) {
    final chosen = state.outputs.where((d) => d.id == id).firstOrNull;
    if (chosen != null &&
        MonitorLimits.isBlockedOutputDeviceType(chosen.type)) {
      state = state.copyWith(
        outputId: () => id,
        status:
            'Built-in speaker is blocked to prevent acoustic feedback. Connect headphones.',
      );
      return;
    }
    state = state.copyWith(outputId: () => id);
  }

  Future<void> startMonitoring() async {
    await refreshDevices();
    final inId = state.inputId;
    final outId = state.outputId;
    if (inId == null || outId == null) {
      state = state.copyWith(
        running: false,
        status: 'No audio input or headphone output device available.',
      );
      return;
    }

    final selectedOut = state.outputs.where((d) => d.id == outId).firstOrNull;
    if (selectedOut == null ||
        MonitorLimits.isBlockedOutputDeviceType(selectedOut.type)) {
      state = state.copyWith(
        running: false,
        status:
            'Built-in speaker is blocked to prevent acoustic feedback. Connect wired, USB-C, or Bluetooth headphones.',
      );
      return;
    }

    final result = await _engine.start(
      inputId: inId,
      outputId: outId,
      level: state.monitorLevel,
    );
    if (!result.started) {
      state = state.copyWith(running: false, status: result.message);
      return;
    }

    await _engine.applyDspConfig(state.toDspConfig());
    final info = await _engine.getStreamInfo();
    state = state.copyWith(
      running: true,
      status: result.message,
      streamInfo: info,
    );
  }

  Future<void> stopMonitoring({
    String reason = 'user',
    String message = 'Stopped',
  }) async {
    await _engine.stop(reason: reason, message: message);
    state = state.copyWith(
      running: false,
      peak: 0.0,
      status: message,
      streamInfo: 'Inactive',
    );
  }

  void onPermissionDenied() {
    state = state.copyWith(
      status: 'Microphone permission is required for live monitoring.',
    );
  }

  // --- DSP Controls ---

  Future<void> setMonitorLevel(double v) async {
    final level = v.clamp(0.0, MonitorLimits.maxMonitorLevel);
    state = state.copyWith(monitorLevel: level);
    await _engine.setMonitorLevel(level);
    await _store.saveDouble('monitor_level', level);
  }

  Future<void> setGateEnabled(bool on) async {
    state = state.copyWith(gateEnabled: on);
    await _engine.setNoiseGate(enabled: on, thresholdDb: state.gateThresholdDb);
    await _store.saveBool('noise_gate_enabled', on);
  }

  Future<void> setGateThreshold(double db) async {
    final clamped = db.clamp(
      MonitorLimits.minGateThresholdDb,
      MonitorLimits.maxGateThresholdDb,
    );
    state = state.copyWith(gateThresholdDb: clamped);
    await _engine.setNoiseGate(
      enabled: state.gateEnabled,
      thresholdDb: clamped,
    );
    await _store.saveDouble('noise_gate_threshold_dbfs', clamped);
  }

  Future<void> setDenoiserEnabled(bool on) async {
    state = state.copyWith(denoiserEnabled: on);
    await _engine.setAdaptiveDenoiser(
      enabled: on,
      strengthDb: state.denoiserStrengthDb,
    );
    await _store.saveBool('adaptive_denoiser_enabled', on);
  }

  Future<void> setDenoiserStrength(double db) async {
    final clamped = db.clamp(
      MonitorLimits.minDenoiserDb,
      MonitorLimits.maxDenoiserDb,
    );
    state = state.copyWith(denoiserStrengthDb: clamped);
    await _engine.setAdaptiveDenoiser(
      enabled: state.denoiserEnabled,
      strengthDb: clamped,
    );
    await _store.saveDouble('adaptive_denoiser_strength_db', clamped);
  }

  Future<void> setCompressionEnabled(bool on) async {
    state = state.copyWith(compressionEnabled: on);
    await _engine.setSpeechCompression(
      enabled: on,
      ratio: state.compressionRatio,
    );
    await _store.saveBool('speech_compression_enabled', on);
  }

  Future<void> setCompressionRatio(double ratio) async {
    final clamped = ratio.clamp(
      MonitorLimits.minCompressionRatio,
      MonitorLimits.maxCompressionRatio,
    );
    state = state.copyWith(compressionRatio: clamped);
    await _engine.setSpeechCompression(
      enabled: state.compressionEnabled,
      ratio: clamped,
    );
    await _store.saveDouble('speech_compression_ratio', clamped);
  }

  Future<void> setProcessed(bool on) async {
    state = state.copyWith(processed: on);
    await _engine.setDspBypassed(!on);
    await _store.saveBool('clarity_processed_audio', on);
  }

  Future<void> setGain(int ear, int band, double db) async {
    final g = db.clamp(-MonitorLimits.maxGainDb, MonitorLimits.maxGainDb);
    final updated = [
      for (var e = 0; e < state.gains.length; e++)
        [
          for (var b = 0; b < state.gains[e].length; b++)
            (e == ear && b == band) ? g : state.gains[e][b],
        ],
    ];
    state = state.copyWith(gains: updated);
    await _engine.setEqualizerBand(ear, band, g);
    await _store.saveDouble(MonitorProfileStore.gainKey(ear, band), g);
  }

  Future<void> resetDefaults() async {
    const zeroGains = [
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    ];
    state = state.copyWith(
      monitorLevel: MonitorLimits.initialMonitorLevel,
      compressionEnabled: true,
      compressionRatio: MonitorLimits.initialCompressionRatio,
      gateEnabled: true,
      gateThresholdDb: MonitorLimits.initialGateThresholdDb,
      denoiserEnabled: false,
      denoiserStrengthDb: MonitorLimits.initialDenoiserDb,
      processed: true,
      gains: zeroGains,
    );
    await _engine.applyDspConfig(state.toDspConfig());
    await _store.saveDouble('monitor_level', MonitorLimits.initialMonitorLevel);
    await _store.saveBool('speech_compression_enabled', true);
    await _store.saveDouble(
      'speech_compression_ratio',
      MonitorLimits.initialCompressionRatio,
    );
    await _store.saveBool('noise_gate_enabled', true);
    await _store.saveDouble(
      'noise_gate_threshold_dbfs',
      MonitorLimits.initialGateThresholdDb,
    );
    await _store.saveBool('adaptive_denoiser_enabled', false);
    await _store.saveDouble(
      'adaptive_denoiser_strength_db',
      MonitorLimits.initialDenoiserDb,
    );
    await _store.saveBool('clarity_processed_audio', true);
    for (var ear = 0; ear < 2; ear++) {
      for (var b = 0; b < MonitorLimits.eqCentersHz.length; b++) {
        await _store.saveDouble(MonitorProfileStore.gainKey(ear, b), 0.0);
      }
    }
  }

  // --- Reference Profile & Clarity A/B Log ---

  Future<void> setThreshold(int ear, int band, String text) async {
    final next = [
      for (var e = 0; e < state.thresholds.length; e++)
        [
          for (var b = 0; b < state.thresholds[e].length; b++)
            (e == ear && b == band) ? text : state.thresholds[e][b],
        ],
    ];
    state = state.copyWith(thresholds: next);
    final v = double.tryParse(text.trim());
    if (text.trim().isEmpty ||
        (v != null && v >= MonitorLimits.minHl && v <= MonitorLimits.maxHl)) {
      await _store.saveString(
        MonitorProfileStore.thresholdKey(ear, band),
        text.trim(),
      );
    }
  }

  /// Copies latest saved screening thresholds as reference-only values (never changes EQ gains).
  Future<void> importLatestScreening({bool silentWhenEmpty = false}) async {
    final sessions = await _repo.loadAllSessions();
    final withResults =
        sessions.where((s) => s.thresholdResults.isNotEmpty).toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final latest = withResults.firstOrNull;
    if (latest == null) {
      if (!silentWhenEmpty) {
        state = state.copyWith(
          importMessage: 'No screening results saved yet. Run a screening first.',
        );
      }
      return;
    }

    var count = 0;
    for (final r in latest.thresholdResults) {
      final band = MonitorLimits.eqCentersHz.indexOf(r.frequencyHz);
      final ear = r.ear == Ear.left ? 0 : 1;
      if (band >= 0 &&
          r.thresholdDb >= MonitorLimits.minHl &&
          r.thresholdDb <= MonitorLimits.maxHl) {
        await setThreshold(ear, band, r.thresholdDb.toString());
        count++;
      }
    }

    final date = DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(latest.startedAt),
    );
    state = state.copyWith(
      importMessage:
          'Imported $count values from the $date screening. These are uncalibrated screening levels, kept as reference only. They do not change any gain.',
    );
  }

  Future<void> setRealEarVerified(bool v) async {
    state = state.copyWith(realEarVerified: v);
    await _store.saveBool('real_ear_verified', v);
  }

  Future<void> setRealEarNotes(String notes) async {
    state = state.copyWith(realEarNotes: notes);
    await _store.saveString('real_ear_notes', notes);
  }

  Future<void> setEnvironment(String env) async {
    state = state.copyWith(environment: env);
    await _store.saveString('clarity_environment', env);
  }

  Future<bool> saveClarityTrial(String correctText, String totalText) async {
    final correct = int.tryParse(correctText.trim());
    final total = int.tryParse(totalText.trim());
    if (total == null ||
        total < 1 ||
        total > MonitorLimits.maxClarityWords ||
        correct == null ||
        correct < 0 ||
        correct > total) {
      state = state.copyWith(
        trialMessage:
            'Enter a correct count from 0 to the list size (1–${MonitorLimits.maxClarityWords}).',
      );
      return false;
    }

    final mode = state.processed ? 'Processed' : 'Baseline';
    final entry =
        '${DateTime.now().millisecondsSinceEpoch}|${state.environment}|$mode|$correct|$total';
    final prev = _store.load().rawTrialLines;
    final nextRaw = [entry, ...prev].take(MonitorLimits.maxClarityTrials).toList();
    await _store.saveString('clarity_trials', nextRaw.join('\n'));
    state = state.copyWith(
      trials: MonitorProfileStore.formatTrialLines(nextRaw),
      trialMessage: '',
    );
    return true;
  }
}

final monitorNotifierProvider =
    NotifierProvider<MonitorNotifier, MonitorUiState>(MonitorNotifier.new);

