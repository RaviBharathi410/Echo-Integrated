import 'dart:convert';
import 'dart:io';

import 'package:echo_hearing/core/data/session_repository.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('in memory repository stores and retrieves sessions without loss', () async {
    final repo = InMemorySessionRepository();

    const route = AudioRouteInfo(
      routeType: AudioRouteType.wiredHeadphones,
      deviceName: 'Sony WH-1000XM4 (3.5mm)',
      isStereoCapable: true,
      sampleRateHz: 44100,
      calibrationInfo: CalibrationInfo(
        deviceModel: 'Pixel 8',
        routeType: AudioRouteType.wiredHeadphones,
        provenance: CalibrationProvenance.fixtureDefault,
        isOfficiallySupported: true,
      ),
    );

    final session = HearingSessionRecord(
      sessionId: 'session-123',
      startedAt: 1700000000000,
      completedAt: 1700000060000,
      deviceModel: 'Pixel 8',
      androidVersion: 34,
      audioRoute: route,
      isCompleted: true,
      qualityFlags: const {QualityFlag.uncalibratedHardware},
      trials: [
        TrialRecord(
          trialNumber: 1,
          ear: Ear.left,
          frequencyHz: 1000,
          levelDb: 40,
          outcome: TrialOutcome.heard,
          latencyMs: 450,
        ),
        TrialRecord(
          trialNumber: 2,
          ear: Ear.left,
          frequencyHz: 1000,
          levelDb: 30,
          outcome: TrialOutcome.notHeard,
        ),
      ],
      thresholdResults: [
        ThresholdResult(
          ear: Ear.left,
          frequencyHz: 1000,
          thresholdDb: 35,
          validAscendingResponses: 2,
          totalTrialsForTarget: 2,
        ),
      ],
    );

    final saved = await repo.saveSession(session);
    expect(saved, isTrue);

    final retrieved = await repo.getSession(session.sessionId);
    expect(retrieved, isNotNull);
    expect(retrieved!.sessionId, session.sessionId);
    expect(retrieved.trials.length, 2);
    expect(retrieved.thresholdResults.length, 1);
    expect(
      retrieved.qualityFlags,
      contains(QualityFlag.uncalibratedHardware),
    );
  });

  test('privacy guarantee - zero raw audio stored in serialized session JSON', () {
    final trial = TrialRecord(
      trialNumber: 1,
      ear: Ear.left,
      frequencyHz: 1000,
      levelDb: 40,
      outcome: TrialOutcome.heard,
      latencyMs: 380,
      ambientNoiseLevelDbFs: -52.4,
    );

    final trialKeys = trial.toJson().keys.toSet();
    expect(trialKeys, isNot(contains('pcm')));
    expect(trialKeys, isNot(contains('audioBytes')));
    expect(trialKeys, isNot(contains('samples')));
    expect(
      trialKeys,
      containsAll([
        'trialNumber',
        'ear',
        'frequencyHz',
        'levelDb',
        'outcome',
        'latencyMs',
        'ambientNoiseLevelDbFs',
        'timestamp',
      ]),
    );
  });

  test('simulated sessions carry simulation flag explicitly', () {
    const route = AudioRouteInfo(
      routeType: AudioRouteType.wiredHeadphones,
      deviceName: 'Virtual Route',
      isStereoCapable: true,
      sampleRateHz: 44100,
      calibrationInfo: CalibrationInfo(
        deviceModel: 'Virtual',
        routeType: AudioRouteType.wiredHeadphones,
        provenance: CalibrationProvenance.simulatedProfile,
        isOfficiallySupported: true,
      ),
    );

    const session = HearingSessionRecord(
      sessionId: 'sim-123',
      startedAt: 1700000000000,
      deviceModel: 'Simulation Emulator',
      androidVersion: 34,
      audioRoute: route,
      qualityFlags: {
        QualityFlag.simulationOnly,
        QualityFlag.uncalibratedHardware,
      },
    );

    expect(session.qualityFlags, contains(QualityFlag.simulationOnly));
    expect(session.qualityFlags, contains(QualityFlag.uncalibratedHardware));
  });

  test(
    'LocalJsonSessionRepository migrates and reads legacy Kotlin session JSON schema verbatim',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('echo_legacy_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final repo = LocalJsonSessionRepository(
        directoryResolver: () async => tempDir,
      );

      final legacyJson = {
        'sessionId': 'kotlin-legacy-01',
        'startedAt': 1710000000000,
        'completedAt': 1710000090000,
        'appVersion': '1.0.0-poc',
        'protocolVersion': 'HW-2026-v1',
        'strategyType': 'MODIFIED_HUGHSON_WESTLAKE',
        'deviceModel': 'Pixel 8',
        'androidVersion': 34,
        'audioRoute': {
          'routeType': 'WIRED_HEADPHONES',
          'deviceName': 'Wired Headset',
          'isStereoCapable': true,
          'sampleRateHz': 44100,
          'calibrationInfo': {
            'deviceModel': 'Pixel 8',
            'routeType': 'WIRED_HEADPHONES',
            'provenance': 'UNCALIBRATED',
            'isOfficiallySupported': true,
            'profileVersion': 'v0.1-provisional',
            'notes': 'Legacy record',
          },
        },
        'isCompleted': true,
        'qualityFlags': ['UNCALIBRATED_HARDWARE'],
        'trials': [
          {
            'trialNumber': 1,
            'ear': 'LEFT',
            'frequencyHz': 1000,
            'levelDb': 25,
            'outcome': 'HEARD',
            'latencyMs': 390,
            'ambientNoiseLevelDbFs': -58.2,
            'timestamp': 1710000010000,
          },
        ],
        'thresholdResults': [
          {
            'ear': 'LEFT',
            'frequencyHz': 1000,
            'thresholdDb': 25,
            'validAscendingResponses': 2,
            'totalTrialsForTarget': 5,
            'method': 'MODIFIED_HUGHSON_WESTLAKE',
            'confidence': 'UNVALIDATED_POC_ESTIMATE',
            'timestamp': 1710000050000,
          },
        ],
        'noisePauseCount': 0,
        'devicePauseCount': 0,
        'screeningOutcome': {
          'overallClassification': 'PASS',
          'leftEarSummary': {
            'ear': 'LEFT',
            'classification': 'PASS',
            'thresholds': [],
            'averageLevelDb': 25.0,
            'isComplete': true,
            'summaryNotes': 'Legacy ok',
          },
          'rightEarSummary': {
            'ear': 'RIGHT',
            'classification': 'PASS',
            'thresholds': [],
            'averageLevelDb': 20.0,
            'isComplete': true,
            'summaryNotes': 'Legacy ok',
          },
          'totalTrials': 10,
          'contaminatedTrials': 0,
          'isCalibrated': false,
          'advisoryNotes': ['Screening only'],
        },
      };

      final sessionsDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}echo_sessions',
      )..createSync(recursive: true);
      File(
        '${sessionsDir.path}${Platform.pathSeparator}session_kotlin-legacy-01.json',
      ).writeAsStringSync(jsonEncode(legacyJson));

      final loaded = await repo.loadAllSessions();
      expect(loaded.length, 1);
      expect(loaded.first.sessionId, 'kotlin-legacy-01');
      expect(loaded.first.audioRoute.routeType, AudioRouteType.wiredHeadphones);
      expect(loaded.first.trials.single.outcome, TrialOutcome.heard);
      expect(
        loaded.first.screeningOutcome?.overallClassification,
        ScreeningOutcomeClassification.pass,
      );
    },
  );
}
