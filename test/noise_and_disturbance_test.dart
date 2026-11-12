import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake noise monitor injects states accurately', () {
    final monitor = FakeNoiseMonitor()
      ..injectAssessment(NoiseAssessment.valid, -60.0);
    addTearDown(monitor.dispose);

    expect(monitor.latestReading.assessment, NoiseAssessment.valid);
    expect(monitor.latestReading.isDisturbance, isFalse);

    monitor.injectAssessment(NoiseAssessment.invalid, -20.0, quietSeconds: 0);
    expect(monitor.latestReading.assessment, NoiseAssessment.invalid);
    expect(monitor.latestReading.isDisturbance, isTrue);
    expect(monitor.latestReading.levelDbFs, closeTo(-20.0, 0.01));
  });

  test('recovery check fails when noise is invalid or quiet window is insufficient', () {
    final monitor = FakeNoiseMonitor();
    addTearDown(monitor.dispose);

    monitor.injectAssessment(NoiseAssessment.invalid, -25.0, quietSeconds: 0);
    expect(monitor.checkRecovery(requiredQuietSeconds: 3), isFalse);

    monitor.injectAssessment(NoiseAssessment.valid, -55.0, quietSeconds: 1);
    expect(monitor.checkRecovery(requiredQuietSeconds: 3), isFalse);

    monitor.injectAssessment(NoiseAssessment.valid, -55.0, quietSeconds: 4);
    expect(monitor.checkRecovery(requiredQuietSeconds: 3), isTrue);
  });

  test('unavailable sensor reported when microphone permission missing', () async {
    final monitor = FakeNoiseMonitor()..sensorAvailable = false;
    addTearDown(monitor.dispose);
    await monitor.startMonitoring();

    expect(monitor.latestReading.assessment, NoiseAssessment.unavailable);
    expect(monitor.latestReading.isDisturbance, isTrue);
  });
}
