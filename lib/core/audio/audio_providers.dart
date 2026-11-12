import 'package:echo_hearing/core/audio/android_audio_bridge.dart';
import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Chooses the native Android bridge when running on Android, and falls back to
/// deterministic fakes on host desktop/test environments where no native plugin exists.
final androidAudioBridgeProvider = Provider<AndroidAudioBridge?>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final bridge = AndroidAudioBridge();
    ref.onDispose(bridge.dispose);
    return bridge;
  }
  return null;
});

final _hostFallbackCoordinatorProvider = Provider<_HostAudioFallback?>((ref) {
  final bridge = ref.watch(androidAudioBridgeProvider);
  if (bridge != null) return null;
  final stimulus = FakeStimulusEngine();
  final noise = FakeNoiseMonitor();
  final detector = FakeDeviceCapabilityManager();
  final monitor = FakeLiveMonitorEngine();
  final coordinator = FakeAudioSessionCoordinator(
    stimulusEngine: stimulus,
    noiseMonitor: noise,
    liveMonitorEngine: monitor,
  );
  ref.onDispose(() {
    stimulus.dispose();
    noise.dispose();
    detector.dispose();
    monitor.dispose();
  });
  return _HostAudioFallback(
    coordinator: coordinator,
    detector: detector,
    noiseMonitor: noise,
    stimulusEngine: stimulus,
    liveMonitorEngine: monitor,
  );
});

class _HostAudioFallback {
  const _HostAudioFallback({
    required this.coordinator,
    required this.detector,
    required this.noiseMonitor,
    required this.stimulusEngine,
    required this.liveMonitorEngine,
  });

  final AudioSessionCoordinator coordinator;
  final ScreeningDeviceDetector detector;
  final NoiseMonitor noiseMonitor;
  final StimulusEngine stimulusEngine;
  final LiveMonitorEngine liveMonitorEngine;
}

final audioCoordinatorProvider = Provider<AudioSessionCoordinator>((ref) {
  return ref.watch(androidAudioBridgeProvider) ??
      ref.watch(_hostFallbackCoordinatorProvider)!.coordinator;
});

final screeningDeviceDetectorProvider = Provider<ScreeningDeviceDetector>((
  ref,
) {
  return ref.watch(androidAudioBridgeProvider) ??
      ref.watch(_hostFallbackCoordinatorProvider)!.detector;
});

final noiseMonitorProvider = Provider<NoiseMonitor>((ref) {
  return ref.watch(androidAudioBridgeProvider) ??
      ref.watch(_hostFallbackCoordinatorProvider)!.noiseMonitor;
});

final stimulusEngineProvider = Provider<StimulusEngine>((ref) {
  return ref.watch(androidAudioBridgeProvider) ??
      ref.watch(_hostFallbackCoordinatorProvider)!.stimulusEngine;
});

final liveMonitorEngineProvider = Provider<LiveMonitorEngine>((ref) {
  return ref.watch(androidAudioBridgeProvider) ??
      ref.watch(_hostFallbackCoordinatorProvider)!.liveMonitorEngine;
});
