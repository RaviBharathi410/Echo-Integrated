import 'package:flutter/foundation.dart';

/// Standard audiometric test ear.
enum Ear {
  left('Left Ear', 'AS'),
  right('Right Ear', 'AD');

  const Ear(this.displayName, this.clinicalCode);
  final String displayName;
  final String clinicalCode;

  String toJsonName() => this == Ear.left ? 'LEFT' : 'RIGHT';

  static Ear fromJsonName(String? value) =>
      value?.toUpperCase() == 'RIGHT' ? Ear.right : Ear.left;
}

/// Standard pure tone audiometric test frequencies in Hz.
abstract final class AudiometricFrequencies {
  static const int freq250Hz = 250;
  static const int freq500Hz = 500;
  static const int freq1000Hz = 1000;
  static const int freq2000Hz = 2000;
  static const int freq4000Hz = 4000;
  static const int freq8000Hz = 8000;

  static const List<int> defaultScreeningFrequencies = [
    freq500Hz,
    freq1000Hz,
    freq2000Hz,
    freq4000Hz,
  ];

  static const List<int> extendedSixFrequencies = [
    freq250Hz,
    freq500Hz,
    freq1000Hz,
    freq2000Hz,
    freq4000Hz,
    freq8000Hz,
  ];
}

enum NoiseAssessment {
  valid,
  suspect,
  invalid,
  unavailable;

  String toJsonName() => name.toUpperCase();

  static NoiseAssessment fromJsonName(String? value) {
    return switch (value?.toUpperCase()) {
      'VALID' => NoiseAssessment.valid,
      'SUSPECT' => NoiseAssessment.suspect,
      'INVALID' => NoiseAssessment.invalid,
      _ => NoiseAssessment.unavailable,
    };
  }
}

enum AudioRouteType {
  wiredHeadphones('Wired Headphones (3.5mm)', true),
  wiredHeadset('Wired Headset w/ Mic', true),
  bluetoothA2dp('Bluetooth Audio (A2DP)', true),
  usbHeadset('USB-C Audio / Headset', true),
  builtinSpeaker('Built-in Device Speaker', false),
  otherUnsupported('Unsupported / Unknown Audio Output', false);

  const AudioRouteType(this.displayName, this.isHeadphone);
  final String displayName;
  final bool isHeadphone;

  String toJsonName() => switch (this) {
    AudioRouteType.wiredHeadphones => 'WIRED_HEADPHONES',
    AudioRouteType.wiredHeadset => 'WIRED_HEADSET',
    AudioRouteType.bluetoothA2dp => 'BLUETOOTH_A2DP',
    AudioRouteType.usbHeadset => 'USB_HEADSET',
    AudioRouteType.builtinSpeaker => 'BUILTIN_SPEAKER',
    AudioRouteType.otherUnsupported => 'OTHER_UNSUPPORTED',
  };

  static AudioRouteType fromJsonName(String? value) => switch (value?.toUpperCase()) {
    'WIRED_HEADPHONES' => AudioRouteType.wiredHeadphones,
    'WIRED_HEADSET' => AudioRouteType.wiredHeadset,
    'BLUETOOTH_A2DP' => AudioRouteType.bluetoothA2dp,
    'USB_HEADSET' => AudioRouteType.usbHeadset,
    'BUILTIN_SPEAKER' => AudioRouteType.builtinSpeaker,
    _ => AudioRouteType.otherUnsupported,
  };
}

enum CalibrationProvenance {
  uncalibrated,
  fixtureDefault,
  simulatedProfile,
  labCalibrated;

  String toJsonName() => switch (this) {
    CalibrationProvenance.uncalibrated => 'UNCALIBRATED',
    CalibrationProvenance.fixtureDefault => 'FIXTURE_DEFAULT',
    CalibrationProvenance.simulatedProfile => 'SIMULATED_PROFILE',
    CalibrationProvenance.labCalibrated => 'LAB_CALIBRATED',
  };

  static CalibrationProvenance fromJsonName(String? value) =>
      switch (value?.toUpperCase()) {
        'FIXTURE_DEFAULT' => CalibrationProvenance.fixtureDefault,
        'SIMULATED_PROFILE' => CalibrationProvenance.simulatedProfile,
        'LAB_CALIBRATED' => CalibrationProvenance.labCalibrated,
        _ => CalibrationProvenance.uncalibrated,
      };
}

@immutable
class CalibrationInfo {
  const CalibrationInfo({
    required this.deviceModel,
    required this.routeType,
    required this.provenance,
    required this.isOfficiallySupported,
    this.profileVersion = 'v0.1-provisional',
    this.notes =
        'No laboratory acoustic calibration has been performed. Outputs are digital dBFS only.',
  });

  final String deviceModel;
  final AudioRouteType routeType;
  final CalibrationProvenance provenance;
  final bool isOfficiallySupported;
  final String profileVersion;
  final String notes;

  Map<String, dynamic> toJson() => {
    'deviceModel': deviceModel,
    'routeType': routeType.toJsonName(),
    'provenance': provenance.toJsonName(),
    'isOfficiallySupported': isOfficiallySupported,
    'profileVersion': profileVersion,
    'notes': notes,
  };

  factory CalibrationInfo.fromJson(Map<String, dynamic> json) {
    return CalibrationInfo(
      deviceModel: (json['deviceModel'] as String?) ?? 'Unknown',
      routeType: AudioRouteType.fromJsonName(json['routeType'] as String?),
      provenance: CalibrationProvenance.fromJsonName(
        json['provenance'] as String?,
      ),
      isOfficiallySupported: (json['isOfficiallySupported'] as bool?) ?? false,
      profileVersion: (json['profileVersion'] as String?) ?? 'v0.1-provisional',
      notes:
          (json['notes'] as String?) ??
          'No laboratory acoustic calibration has been performed. Outputs are digital dBFS only.',
    );
  }
}

@immutable
class AudioRouteInfo {
  const AudioRouteInfo({
    required this.routeType,
    required this.deviceName,
    required this.isStereoCapable,
    required this.sampleRateHz,
    required this.calibrationInfo,
  });

  final AudioRouteType routeType;
  final String deviceName;
  final bool isStereoCapable;
  final int sampleRateHz;
  final CalibrationInfo calibrationInfo;

  Map<String, dynamic> toJson() => {
    'routeType': routeType.toJsonName(),
    'deviceName': deviceName,
    'isStereoCapable': isStereoCapable,
    'sampleRateHz': sampleRateHz,
    'calibrationInfo': calibrationInfo.toJson(),
  };

  factory AudioRouteInfo.fromJson(Map<String, dynamic> json) {
    final routeType = AudioRouteType.fromJsonName(json['routeType'] as String?);
    final calRaw = json['calibrationInfo'];
    final calibration = calRaw is Map<String, dynamic>
        ? CalibrationInfo.fromJson(calRaw)
        : calRaw is Map
        ? CalibrationInfo.fromJson(Map<String, dynamic>.from(calRaw))
        : CalibrationInfo(
            deviceModel: 'Unknown',
            routeType: routeType,
            provenance: CalibrationProvenance.uncalibrated,
            isOfficiallySupported: routeType.isHeadphone,
          );
    return AudioRouteInfo(
      routeType: routeType,
      deviceName: (json['deviceName'] as String?) ?? routeType.displayName,
      isStereoCapable: (json['isStereoCapable'] as bool?) ?? true,
      sampleRateHz: (json['sampleRateHz'] as num?)?.toInt() ?? 44100,
      calibrationInfo: calibration,
    );
  }
}

enum TrialOutcome {
  heard,
  notHeard,
  contaminatedByNoise,
  invalidInterrupted,
  unansweredTimeout;

  String toJsonName() => switch (this) {
    TrialOutcome.heard => 'HEARD',
    TrialOutcome.notHeard => 'NOT_HEARD',
    TrialOutcome.contaminatedByNoise => 'CONTAMINATED_BY_NOISE',
    TrialOutcome.invalidInterrupted => 'INVALID_INTERRUPTED',
    TrialOutcome.unansweredTimeout => 'UNANSWERED_TIMEOUT',
  };

  static TrialOutcome fromJsonName(String? value) =>
      switch (value?.toUpperCase()) {
        'HEARD' => TrialOutcome.heard,
        'NOT_HEARD' => TrialOutcome.notHeard,
        'CONTAMINATED_BY_NOISE' => TrialOutcome.contaminatedByNoise,
        'INVALID_INTERRUPTED' => TrialOutcome.invalidInterrupted,
        _ => TrialOutcome.unansweredTimeout,
      };
}

@immutable
class TrialRecord {
  TrialRecord({
    required this.trialNumber,
    required this.ear,
    required this.frequencyHz,
    required this.levelDb,
    required this.outcome,
    this.latencyMs,
    this.ambientNoiseLevelDbFs,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  final int trialNumber;
  final Ear ear;
  final int frequencyHz;
  final int levelDb;
  final TrialOutcome outcome;
  final int? latencyMs;
  final double? ambientNoiseLevelDbFs;
  final int timestamp;

  Map<String, dynamic> toJson() => {
    'trialNumber': trialNumber,
    'ear': ear.toJsonName(),
    'frequencyHz': frequencyHz,
    'levelDb': levelDb,
    'outcome': outcome.toJsonName(),
    'latencyMs': latencyMs,
    'ambientNoiseLevelDbFs': ambientNoiseLevelDbFs,
    'timestamp': timestamp,
  };

  factory TrialRecord.fromJson(Map<String, dynamic> json) => TrialRecord(
    trialNumber: (json['trialNumber'] as num?)?.toInt() ?? 0,
    ear: Ear.fromJsonName(json['ear'] as String?),
    frequencyHz: (json['frequencyHz'] as num?)?.toInt() ?? 1000,
    levelDb: (json['levelDb'] as num?)?.toInt() ?? 40,
    outcome: TrialOutcome.fromJsonName(json['outcome'] as String?),
    latencyMs: (json['latencyMs'] as num?)?.toInt(),
    ambientNoiseLevelDbFs: (json['ambientNoiseLevelDbFs'] as num?)?.toDouble(),
    timestamp: (json['timestamp'] as num?)?.toInt(),
  );
}

@immutable
class ThresholdResult {
  ThresholdResult({
    required this.ear,
    required this.frequencyHz,
    required this.thresholdDb,
    required this.validAscendingResponses,
    required this.totalTrialsForTarget,
    this.method = 'MODIFIED_HUGHSON_WESTLAKE_PROVISIONAL',
    this.confidence = 'UNVALIDATED_POC_ESTIMATE',
    this.strategyVersion,
    this.bracketLowerDb,
    this.bracketUpperDb,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  final Ear ear;
  final int frequencyHz;
  final int thresholdDb;
  final int validAscendingResponses;
  final int totalTrialsForTarget;
  final String method;
  final String confidence;
  final String? strategyVersion;
  final int? bracketLowerDb;
  final int? bracketUpperDb;
  final int timestamp;

  Map<String, dynamic> toJson() => {
    'ear': ear.toJsonName(),
    'frequencyHz': frequencyHz,
    'thresholdDb': thresholdDb,
    'validAscendingResponses': validAscendingResponses,
    'totalTrialsForTarget': totalTrialsForTarget,
    'method': method,
    'confidence': confidence,
    'strategyVersion': strategyVersion,
    'bracketLowerDb': bracketLowerDb,
    'bracketUpperDb': bracketUpperDb,
    'timestamp': timestamp,
  };

  factory ThresholdResult.fromJson(Map<String, dynamic> json) =>
      ThresholdResult(
        ear: Ear.fromJsonName(json['ear'] as String?),
        frequencyHz: (json['frequencyHz'] as num?)?.toInt() ?? 1000,
        thresholdDb: (json['thresholdDb'] as num?)?.toInt() ?? 0,
        validAscendingResponses:
            (json['validAscendingResponses'] as num?)?.toInt() ?? 0,
        totalTrialsForTarget:
            (json['totalTrialsForTarget'] as num?)?.toInt() ?? 0,
        method:
            (json['method'] as String?) ??
            'MODIFIED_HUGHSON_WESTLAKE_PROVISIONAL',
        confidence:
            (json['confidence'] as String?) ?? 'UNVALIDATED_POC_ESTIMATE',
        strategyVersion: json['strategyVersion'] as String?,
        bracketLowerDb: (json['bracketLowerDb'] as num?)?.toInt(),
        bracketUpperDb: (json['bracketUpperDb'] as num?)?.toInt(),
        timestamp: (json['timestamp'] as num?)?.toInt(),
      );
}

enum QualityFlag {
  simulationOnly,
  uncalibratedHardware,
  noTrustedNoiseSensor,
  environmentalNoisePausesDetected,
  audioRouteChangedDuringTest,
  incompleteTargets,
  excessiveReversals,
  binarySearchExperimental;

  String toJsonName() => switch (this) {
    QualityFlag.simulationOnly => 'SIMULATION_ONLY',
    QualityFlag.uncalibratedHardware => 'UNCALIBRATED_HARDWARE',
    QualityFlag.noTrustedNoiseSensor => 'NO_TRUSTED_NOISE_SENSOR',
    QualityFlag.environmentalNoisePausesDetected =>
      'ENVIRONMENTAL_NOISE_PAUSES_DETECTED',
    QualityFlag.audioRouteChangedDuringTest =>
      'AUDIO_ROUTE_CHANGED_DURING_TEST',
    QualityFlag.incompleteTargets => 'INCOMPLETE_TARGETS',
    QualityFlag.excessiveReversals => 'EXCESSIVE_REVERSALS',
    QualityFlag.binarySearchExperimental => 'BINARY_SEARCH_EXPERIMENTAL',
  };

  static QualityFlag? fromJsonName(String? value) =>
      switch (value?.toUpperCase()) {
        'SIMULATION_ONLY' => QualityFlag.simulationOnly,
        'UNCALIBRATED_HARDWARE' => QualityFlag.uncalibratedHardware,
        'NO_TRUSTED_NOISE_SENSOR' => QualityFlag.noTrustedNoiseSensor,
        'ENVIRONMENTAL_NOISE_PAUSES_DETECTED' =>
          QualityFlag.environmentalNoisePausesDetected,
        'AUDIO_ROUTE_CHANGED_DURING_TEST' =>
          QualityFlag.audioRouteChangedDuringTest,
        'INCOMPLETE_TARGETS' => QualityFlag.incompleteTargets,
        'EXCESSIVE_REVERSALS' => QualityFlag.excessiveReversals,
        'BINARY_SEARCH_EXPERIMENTAL' => QualityFlag.binarySearchExperimental,
        _ => null,
      };
}

enum ScreeningOutcomeClassification {
  pass(
    'Pass (Preliminary)',
    'Responses detected within screening baseline levels across tested frequencies.',
  ),
  refer(
    'Referral Recommended',
    'Elevated response levels or non-responses detected at one or more frequencies. Formal audiometry advised.',
  ),
  inconclusive(
    'Inconclusive / Incomplete',
    'Testing was interrupted, noise limits were exceeded, or a valid threshold bracket could not be established.',
  );

  const ScreeningOutcomeClassification(
    this.displayName,
    this.clinicalDescription,
  );
  final String displayName;
  final String clinicalDescription;

  String toJsonName() => name.toUpperCase();

  static ScreeningOutcomeClassification fromJsonName(String? value) =>
      switch (value?.toUpperCase()) {
        'PASS' => ScreeningOutcomeClassification.pass,
        'REFER' => ScreeningOutcomeClassification.refer,
        _ => ScreeningOutcomeClassification.inconclusive,
      };
}

@immutable
class EarScreeningSummary {
  const EarScreeningSummary({
    required this.ear,
    required this.classification,
    required this.thresholds,
    required this.averageLevelDb,
    required this.isComplete,
    required this.summaryNotes,
  });

  final Ear ear;
  final ScreeningOutcomeClassification classification;
  final List<ThresholdResult> thresholds;
  final double? averageLevelDb;
  final bool isComplete;
  final String summaryNotes;

  Map<String, dynamic> toJson() => {
    'ear': ear.toJsonName(),
    'classification': classification.toJsonName(),
    'thresholds': thresholds.map((e) => e.toJson()).toList(),
    'averageLevelDb': averageLevelDb,
    'isComplete': isComplete,
    'summaryNotes': summaryNotes,
  };

  factory EarScreeningSummary.fromJson(Map<String, dynamic> json) {
    final thresholdsRaw = (json['thresholds'] as List?) ?? const [];
    return EarScreeningSummary(
      ear: Ear.fromJsonName(json['ear'] as String?),
      classification: ScreeningOutcomeClassification.fromJsonName(
        json['classification'] as String?,
      ),
      thresholds: thresholdsRaw
          .whereType<Map>()
          .map((e) => ThresholdResult.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      averageLevelDb: (json['averageLevelDb'] as num?)?.toDouble(),
      isComplete: (json['isComplete'] as bool?) ?? false,
      summaryNotes: (json['summaryNotes'] as String?) ?? '',
    );
  }
}

@immutable
class SessionScreeningOutcome {
  const SessionScreeningOutcome({
    required this.overallClassification,
    required this.leftEarSummary,
    required this.rightEarSummary,
    required this.totalTrials,
    required this.contaminatedTrials,
    this.isCalibrated = false,
    this.advisoryNotes = const [],
  });

  final ScreeningOutcomeClassification overallClassification;
  final EarScreeningSummary leftEarSummary;
  final EarScreeningSummary rightEarSummary;
  final int totalTrials;
  final int contaminatedTrials;
  final bool isCalibrated;
  final List<String> advisoryNotes;

  Map<String, dynamic> toJson() => {
    'overallClassification': overallClassification.toJsonName(),
    'leftEarSummary': leftEarSummary.toJson(),
    'rightEarSummary': rightEarSummary.toJson(),
    'totalTrials': totalTrials,
    'contaminatedTrials': contaminatedTrials,
    'isCalibrated': isCalibrated,
    'advisoryNotes': advisoryNotes,
  };

  factory SessionScreeningOutcome.fromJson(Map<String, dynamic> json) {
    return SessionScreeningOutcome(
      overallClassification: ScreeningOutcomeClassification.fromJsonName(
        json['overallClassification'] as String?,
      ),
      leftEarSummary: EarScreeningSummary.fromJson(
        Map<String, dynamic>.from((json['leftEarSummary'] as Map?) ?? const {}),
      ),
      rightEarSummary: EarScreeningSummary.fromJson(
        Map<String, dynamic>.from(
          (json['rightEarSummary'] as Map?) ?? const {},
        ),
      ),
      totalTrials: (json['totalTrials'] as num?)?.toInt() ?? 0,
      contaminatedTrials: (json['contaminatedTrials'] as num?)?.toInt() ?? 0,
      isCalibrated: (json['isCalibrated'] as bool?) ?? false,
      advisoryNotes: ((json['advisoryNotes'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

@immutable
class HearingSessionRecord {
  const HearingSessionRecord({
    required this.sessionId,
    required this.startedAt,
    this.completedAt,
    this.appVersion = '1.0.0-flutter',
    this.protocolVersion = 'HW-2026-v1',
    this.strategyType = 'MODIFIED_HUGHSON_WESTLAKE',
    required this.deviceModel,
    required this.androidVersion,
    required this.audioRoute,
    this.isCompleted = false,
    this.qualityFlags = const {},
    this.trials = const [],
    this.thresholdResults = const [],
    this.noisePauseCount = 0,
    this.devicePauseCount = 0,
    this.screeningOutcome,
  });

  final String sessionId;
  final int startedAt;
  final int? completedAt;
  final String appVersion;
  final String protocolVersion;
  final String strategyType;
  final String deviceModel;
  final int androidVersion;
  final AudioRouteInfo audioRoute;
  final bool isCompleted;
  final Set<QualityFlag> qualityFlags;
  final List<TrialRecord> trials;
  final List<ThresholdResult> thresholdResults;
  final int noisePauseCount;
  final int devicePauseCount;
  final SessionScreeningOutcome? screeningOutcome;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'startedAt': startedAt,
    'completedAt': completedAt,
    'appVersion': appVersion,
    'protocolVersion': protocolVersion,
    'strategyType': strategyType,
    'deviceModel': deviceModel,
    'androidVersion': androidVersion,
    'audioRoute': audioRoute.toJson(),
    'isCompleted': isCompleted,
    'qualityFlags': qualityFlags.map((e) => e.toJsonName()).toList(),
    'trials': trials.map((e) => e.toJson()).toList(),
    'thresholdResults': thresholdResults.map((e) => e.toJson()).toList(),
    'noisePauseCount': noisePauseCount,
    'devicePauseCount': devicePauseCount,
    'screeningOutcome': screeningOutcome?.toJson(),
  };

  factory HearingSessionRecord.fromJson(Map<String, dynamic> json) {
    final flagsRaw = (json['qualityFlags'] as List?) ?? const [];
    final trialsRaw = (json['trials'] as List?) ?? const [];
    final thresholdsRaw = (json['thresholdResults'] as List?) ?? const [];
    final outcomeRaw = json['screeningOutcome'];

    return HearingSessionRecord(
      sessionId: (json['sessionId'] as String?) ?? '',
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      completedAt: (json['completedAt'] as num?)?.toInt(),
      appVersion: (json['appVersion'] as String?) ?? '1.0.0-poc',
      protocolVersion: (json['protocolVersion'] as String?) ?? 'HW-2026-v1',
      strategyType:
          (json['strategyType'] as String?) ?? 'MODIFIED_HUGHSON_WESTLAKE',
      deviceModel: (json['deviceModel'] as String?) ?? 'Unknown',
      androidVersion: (json['androidVersion'] as num?)?.toInt() ?? 0,
      audioRoute: AudioRouteInfo.fromJson(
        Map<String, dynamic>.from((json['audioRoute'] as Map?) ?? const {}),
      ),
      isCompleted: (json['isCompleted'] as bool?) ?? false,
      qualityFlags: flagsRaw
          .whereType<String>()
          .map(QualityFlag.fromJsonName)
          .whereType<QualityFlag>()
          .toSet(),
      trials: trialsRaw
          .whereType<Map>()
          .map((e) => TrialRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      thresholdResults: thresholdsRaw
          .whereType<Map>()
          .map((e) => ThresholdResult.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      noisePauseCount: (json['noisePauseCount'] as num?)?.toInt() ?? 0,
      devicePauseCount: (json['devicePauseCount'] as num?)?.toInt() ?? 0,
      screeningOutcome: outcomeRaw is Map
          ? SessionScreeningOutcome.fromJson(
              Map<String, dynamic>.from(outcomeRaw),
            )
          : null,
    );
  }
}
