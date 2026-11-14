import 'dart:async';

import 'package:echo_hearing/app/feature_flags.dart';
import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/audio_providers.dart';
import 'package:echo_hearing/core/data/user_profile_store.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

@immutable
class DailyExposureData {
  const DailyExposureData({
    this.todayListeningSeconds = 0,
    this.currentSessionSeconds = 0,
    this.ambientLevelText = 'Moderate (Level 2 of 5)',
    this.ambientDescription = 'Comfortable ambient environment',
    this.isHeadphoneConnected = false,
    this.connectionSubtitle = 'Connect headphones to start automatic sound monitoring',
    this.connectionType = 'Bluetooth',
    this.lastTrackedDate = '',
    this.dailyBudgetSeconds = 14400, // 4 hours guideline
    this.isSample = false,
  });

  final int todayListeningSeconds;
  final int currentSessionSeconds;
  final String ambientLevelText;
  final String ambientDescription;
  final bool isHeadphoneConnected;
  final String connectionSubtitle;
  final String connectionType;
  final String lastTrackedDate;
  final int dailyBudgetSeconds;
  final bool isSample;

  String get formattedTodayListening {
    final hours = todayListeningSeconds ~/ 3600;
    final minutes = (todayListeningSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '0m';
    }
  }

  String get formattedCurrentSession {
    final hours = currentSessionSeconds ~/ 3600;
    final minutes = (currentSessionSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      return '0m';
    }
  }

  double get dailyProgress {
    if (dailyBudgetSeconds <= 0) return 0.0;
    return (todayListeningSeconds / dailyBudgetSeconds).clamp(0.0, 1.0);
  }

  DailyExposureData copyWith({
    int? todayListeningSeconds,
    int? currentSessionSeconds,
    String? ambientLevelText,
    String? ambientDescription,
    bool? isHeadphoneConnected,
    String? connectionSubtitle,
    String? connectionType,
    String? lastTrackedDate,
    int? dailyBudgetSeconds,
    bool? isSample,
  }) {
    return DailyExposureData(
      todayListeningSeconds:
          todayListeningSeconds ?? this.todayListeningSeconds,
      currentSessionSeconds:
          currentSessionSeconds ?? this.currentSessionSeconds,
      ambientLevelText: ambientLevelText ?? this.ambientLevelText,
      ambientDescription: ambientDescription ?? this.ambientDescription,
      isHeadphoneConnected: isHeadphoneConnected ?? this.isHeadphoneConnected,
      connectionSubtitle: connectionSubtitle ?? this.connectionSubtitle,
      connectionType: connectionType ?? this.connectionType,
      lastTrackedDate: lastTrackedDate ?? this.lastTrackedDate,
      dailyBudgetSeconds: dailyBudgetSeconds ?? this.dailyBudgetSeconds,
      isSample: isSample ?? this.isSample,
    );
  }
}

class DailyExposureNotifier extends Notifier<DailyExposureData> {
  static const _prefix = 'echo.daily_exposure.';
  static const _kTodaySeconds = '${_prefix}today_seconds';
  static const _kDate = '${_prefix}date';
  static const _kAmbientLevel = '${_prefix}ambient_level';

  Timer? _tickerTimer;
  StreamSubscription<AudioRouteInfo>? _routeSubscription;
  StreamSubscription<NoiseReading>? _noiseSubscription;

  @override
  DailyExposureData build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final demoEnabled = ref.watch(demoDataEnabledProvider);
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final savedDate = prefs.getString(_kDate) ?? '';
    int savedTodaySeconds = 0;
    if (savedDate == todayStr) {
      savedTodaySeconds = prefs.getInt(_kTodaySeconds) ?? 0;
    }

    final initial = (savedTodaySeconds == 0 && demoEnabled)
        ? DailyExposureData(
            todayListeningSeconds: 8100, // 2h 15m
            currentSessionSeconds: 2700, // 45m
            ambientLevelText: 'Moderate (Level 2 of 5)',
            ambientDescription: 'Comfortable ambient environment',
            isHeadphoneConnected: true,
            connectionSubtitle: 'Connected via Bluetooth • Audio Profile Active',
            connectionType: 'Bluetooth',
            lastTrackedDate: todayStr,
            isSample: true,
          )
        : DailyExposureData(
            todayListeningSeconds: savedTodaySeconds,
            currentSessionSeconds: 0,
            ambientLevelText:
                prefs.getString(_kAmbientLevel) ?? 'Moderate (Level 2 of 5)',
            ambientDescription: 'Comfortable ambient environment',
            isHeadphoneConnected: false,
            connectionSubtitle:
                'Connect headphones to start automatic sound monitoring',
            connectionType: 'None',
            lastTrackedDate: todayStr,
            isSample: false,
          );

    _initListeners();

    ref.onDispose(() {
      _tickerTimer?.cancel();
      _routeSubscription?.cancel();
      _noiseSubscription?.cancel();
    });

    return initial;
  }

  void _initListeners() {
    final detector = ref.read(screeningDeviceDetectorProvider);
    final noiseMonitor = ref.read(noiseMonitorProvider);

    detector.getCurrentAudioRoute().then((route) {
      _handleRoute(route);
    });

    _routeSubscription = detector.routeStream.listen(_handleRoute);
    _noiseSubscription = noiseMonitor.readingStream.listen(_handleNoiseReading);
  }

  void _handleRoute(AudioRouteInfo route) {
    final isHeadphones = route.routeType.isHeadphone;
    final connType = route.routeType == AudioRouteType.bluetoothA2dp
        ? 'Bluetooth'
        : (route.routeType == AudioRouteType.wiredHeadset ||
                route.routeType == AudioRouteType.wiredHeadphones
            ? 'Wired Headset'
            : (route.routeType == AudioRouteType.usbHeadset
                ? 'USB-C Audio'
                : 'Headphones'));

    if (isHeadphones) {
      _onHeadphonesConnected(connType: connType, deviceName: route.deviceName);
    } else {
      _onHeadphonesDisconnected();
    }
  }

  void _onHeadphonesConnected({required String connType, String? deviceName}) {
    if (state.isHeadphoneConnected &&
        _tickerTimer != null &&
        _tickerTimer!.isActive) {
      return;
    }

    state = state.copyWith(
      isHeadphoneConnected: true,
      connectionType: connType,
      connectionSubtitle: 'Connected via $connType • Audio Profile Active',
      isSample: false,
    );

    _startActiveMonitoringTimer();
  }

  void _onHeadphonesDisconnected() {
    _tickerTimer?.cancel();
    _tickerTimer = null;

    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setInt(_kTodaySeconds, state.todayListeningSeconds);
    prefs.setString(_kDate, state.lastTrackedDate);
    prefs.setString(_kAmbientLevel, state.ambientLevelText);

    state = state.copyWith(
      isHeadphoneConnected: false,
      currentSessionSeconds: 0,
      connectionSubtitle: 'Headphones Disconnected • Audio Profile Inactive',
      isSample: false,
    );
  }

  void _startActiveMonitoringTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      int newToday = state.todayListeningSeconds + 1;
      int newSession = state.currentSessionSeconds + 1;

      if (state.lastTrackedDate.isNotEmpty && state.lastTrackedDate != todayStr) {
        newToday = 1;
      }

      state = state.copyWith(
        todayListeningSeconds: newToday,
        currentSessionSeconds: newSession,
        lastTrackedDate: todayStr,
      );

      if (newSession % 10 == 0) {
        final prefs = ref.read(sharedPreferencesProvider);
        prefs.setInt(_kTodaySeconds, newToday);
        prefs.setString(_kDate, todayStr);
        prefs.setString(_kAmbientLevel, state.ambientLevelText);
      }
    });
  }

  void _handleNoiseReading(NoiseReading reading) {
    if (!state.isHeadphoneConnected) return;

    final db = reading.levelDbFs;
    String levelText;
    String desc;
    if (db <= -55) {
      levelText = 'Quiet (Level 1 of 5)';
      desc = 'Very quiet ambient environment';
    } else if (db <= -40) {
      levelText = 'Moderate (Level 2 of 5)';
      desc = 'Comfortable ambient environment';
    } else if (db <= -25) {
      levelText = 'Elevated (Level 3 of 5)';
      desc = 'Noticeable background noise';
    } else if (db <= -15) {
      levelText = 'High (Level 4 of 5)';
      desc = 'Loud background noise';
    } else {
      levelText = 'Critical (Level 5 of 5)';
      desc = 'Very loud background environment';
    }

    state = state.copyWith(
      ambientLevelText: levelText,
      ambientDescription: desc,
    );
  }

  void setHeadphonesConnectedForTesting(
    bool connected, {
    String connType = 'Bluetooth',
  }) {
    if (connected) {
      _onHeadphonesConnected(connType: connType);
    } else {
      _onHeadphonesDisconnected();
    }
  }

  void addSimulatedSeconds(int seconds) {
    state = state.copyWith(
      todayListeningSeconds: state.todayListeningSeconds + seconds,
      currentSessionSeconds: state.currentSessionSeconds + seconds,
    );
  }
}

final dailyExposureProvider =
    NotifierProvider<DailyExposureNotifier, DailyExposureData>(
      DailyExposureNotifier.new,
    );
