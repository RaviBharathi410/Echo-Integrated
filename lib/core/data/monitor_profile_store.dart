import 'dart:async';

import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class MonitorLimits {
  static const List<int> eqCentersHz = [250, 500, 1000, 2000, 4000, 6000];
  static const double initialMonitorLevel = 0.15;
  static const double maxMonitorLevel = 0.50;
  static const double initialCompressionRatio = 2.0;
  static const double minCompressionRatio = 1.0;
  static const double maxCompressionRatio = 3.0;
  static const double initialGateThresholdDb = -54.0;
  static const double minGateThresholdDb = -72.0;
  static const double maxGateThresholdDb = -36.0;
  static const double initialDenoiserDb = 9.0;
  static const double minDenoiserDb = 0.0;
  static const double maxDenoiserDb = 18.0;
  static const double maxGainDb = 6.0;
  static const double minHl = -10.0;
  static const double maxHl = 120.0;
  static const int maxClarityWords = 200;
  static const int maxClarityTrials = 40;
  static const List<String> environments = ['Quiet', 'Background noise'];

  /// Android AudioDeviceInfo.TYPE_BUILTIN_EARPIECE (1), TYPE_BUILTIN_SPEAKER (2),
  /// TYPE_BUILTIN_SPEAKER_SAFE (24).
  static bool isBlockedOutputDeviceType(int type) =>
      type == 1 || type == 2 || type == 24;
}

@immutable
class PersistedMonitorState {
  const PersistedMonitorState({
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
    this.environment = 'Quiet',
    this.rawTrialLines = const [],
    this.trialsFormatted = const [],
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
  final List<List<String>> thresholds;
  final bool realEarVerified;
  final String realEarNotes;
  final String environment;
  final List<String> rawTrialLines;
  final List<String> trialsFormatted;
}

class MonitorProfileStore {
  MonitorProfileStore(this._prefs);

  static const _prefix = 'echo.monitor.';
  static const _migratedFlag = 'echo.legacy_monitor_migrated';

  static const _kLevel = 'monitor_level';
  static const _kCompOn = 'speech_compression_enabled';
  static const _kCompRatio = 'speech_compression_ratio';
  static const _kGateOn = 'noise_gate_enabled';
  static const _kGateDb = 'noise_gate_threshold_dbfs';
  static const _kDenOn = 'adaptive_denoiser_enabled';
  static const _kDenDb = 'adaptive_denoiser_strength_db';
  static const _kProcessed = 'clarity_processed_audio';
  static const _kEnv = 'clarity_environment';
  static const _kTrials = 'clarity_trials';
  static const _kRealEar = 'real_ear_verified';
  static const _kRealEarNotes = 'real_ear_notes';

  final SharedPreferences _prefs;

  static String gainKey(int ear, int band) => 'gain_${ear}_$band';
  static String thresholdKey(int ear, int band) => 'audiogram_${ear}_$band';

  Future<bool> importLegacyIfNeeded(AudioSessionCoordinator coordinator) async {
    if (_prefs.getBool(_migratedFlag) ?? false) return false;
    try {
      final all = await coordinator.readLegacyPrefs();
      final legacy = all['echo_profile'];
      if (legacy != null && legacy.isNotEmpty) {
        await _writeNum(_kLevel, legacy[_kLevel]);
        await _writeBool(_kCompOn, legacy[_kCompOn]);
        await _writeNum(_kCompRatio, legacy[_kCompRatio]);
        await _writeBool(_kGateOn, legacy[_kGateOn]);
        await _writeNum(_kGateDb, legacy[_kGateDb]);
        await _writeBool(_kDenOn, legacy[_kDenOn]);
        await _writeNum(_kDenDb, legacy[_kDenDb]);
        await _writeBool(_kProcessed, legacy[_kProcessed]);
        await _writeString(_kEnv, legacy[_kEnv]);
        await _writeString(_kTrials, legacy[_kTrials]);
        await _writeBool(_kRealEar, legacy[_kRealEar]);
        await _writeString(_kRealEarNotes, legacy[_kRealEarNotes]);
        for (var ear = 0; ear < 2; ear++) {
          for (var b = 0; b < MonitorLimits.eqCentersHz.length; b++) {
            await _writeNum(gainKey(ear, b), legacy[gainKey(ear, b)]);
            await _writeString(
              thresholdKey(ear, b),
              legacy[thresholdKey(ear, b)],
            );
          }
        }
        await _prefs.setBool(_migratedFlag, true);
        return true;
      }
      await _prefs.setBool(_migratedFlag, true);
    } catch (_) {
      // Ignore bridge unavailability during tests.
    }
    return false;
  }

  Future<void> _writeNum(String key, dynamic val) async {
    if (val is num) await _prefs.setDouble('$_prefix$key', val.toDouble());
  }

  Future<void> _writeBool(String key, dynamic val) async {
    if (val is bool) await _prefs.setBool('$_prefix$key', val);
  }

  Future<void> _writeString(String key, dynamic val) async {
    if (val is String) await _prefs.setString('$_prefix$key', val);
  }

  PersistedMonitorState load() {
    final gains = [
      for (var ear = 0; ear < 2; ear++)
        [
          for (var b = 0; b < MonitorLimits.eqCentersHz.length; b++)
            (_prefs.getDouble('$_prefix${gainKey(ear, b)}') ?? 0.0).clamp(
              -MonitorLimits.maxGainDb,
              MonitorLimits.maxGainDb,
            ),
        ],
    ];
    final thresholds = [
      for (var ear = 0; ear < 2; ear++)
        [
          for (var b = 0; b < MonitorLimits.eqCentersHz.length; b++)
            _prefs.getString('$_prefix${thresholdKey(ear, b)}') ?? '',
        ],
    ];

    final rawEnv = _prefs.getString('$_prefix$_kEnv');
    final env =
        MonitorLimits.environments.contains(rawEnv)
            ? rawEnv!
            : MonitorLimits.environments.first;

    final rawBlob = _prefs.getString('$_prefix$_kTrials') ?? '';
    final rawLines = rawBlob
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(MonitorLimits.maxClarityTrials)
        .toList();

    return PersistedMonitorState(
      monitorLevel: (_prefs.getDouble('$_prefix$_kLevel') ??
              MonitorLimits.initialMonitorLevel)
          .clamp(0.0, MonitorLimits.maxMonitorLevel),
      gateEnabled: _prefs.getBool('$_prefix$_kGateOn') ?? true,
      gateThresholdDb: (_prefs.getDouble('$_prefix$_kGateDb') ??
              MonitorLimits.initialGateThresholdDb)
          .clamp(
            MonitorLimits.minGateThresholdDb,
            MonitorLimits.maxGateThresholdDb,
          ),
      denoiserEnabled: _prefs.getBool('$_prefix$_kDenOn') ?? false,
      denoiserStrengthDb: (_prefs.getDouble('$_prefix$_kDenDb') ??
              MonitorLimits.initialDenoiserDb)
          .clamp(MonitorLimits.minDenoiserDb, MonitorLimits.maxDenoiserDb),
      compressionEnabled: _prefs.getBool('$_prefix$_kCompOn') ?? true,
      compressionRatio: (_prefs.getDouble('$_prefix$_kCompRatio') ??
              MonitorLimits.initialCompressionRatio)
          .clamp(
            MonitorLimits.minCompressionRatio,
            MonitorLimits.maxCompressionRatio,
          ),
      processed: _prefs.getBool('$_prefix$_kProcessed') ?? true,
      gains: gains,
      thresholds: thresholds,
      realEarVerified: _prefs.getBool('$_prefix$_kRealEar') ?? false,
      realEarNotes: _prefs.getString('$_prefix$_kRealEarNotes') ?? '',
      environment: env,
      rawTrialLines: rawLines,
      trialsFormatted: formatTrialLines(rawLines),
    );
  }

  static List<String> formatTrialLines(List<String> lines) {
    final result = <String>[];
    for (final line in lines) {
      final f = line.split('|');
      if (f.length != 5) continue;
      final ts = int.tryParse(f[0]);
      final correct = int.tryParse(f[3]);
      final total = int.tryParse(f[4]);
      if (ts == null ||
          correct == null ||
          total == null ||
          total <= 0 ||
          correct < 0 ||
          correct > total) {
        continue;
      }
      final pct = (correct * 100) ~/ total;
      final dateStr = DateFormat.yMd().add_jm().format(
        DateTime.fromMillisecondsSinceEpoch(ts),
      );
      result.add('${f[1]} · ${f[2]} · $correct/$total ($pct%) · $dateStr');
      if (result.length >= MonitorLimits.maxClarityTrials) break;
    }
    return result;
  }

  Future<void> saveDouble(String key, double value) =>
      _prefs.setDouble('$_prefix$key', value);
  Future<void> saveBool(String key, bool value) =>
      _prefs.setBool('$_prefix$key', value);
  Future<void> saveString(String key, String value) =>
      _prefs.setString('$_prefix$key', value);
}

final monitorProfileStoreProvider = Provider<MonitorProfileStore>((ref) {
  return MonitorProfileStore(ref.watch(sharedPreferencesProvider));
});
