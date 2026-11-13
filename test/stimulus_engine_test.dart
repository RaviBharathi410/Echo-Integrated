import 'package:echo_hearing/core/audio/audio_contracts.dart';
import 'package:echo_hearing/core/audio/fake_audio_engines.dart';
import 'package:echo_hearing/core/domain/models/hearing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake stimulus engine tracks played tones and stops cleanly', () async {
    final engine = FakeStimulusEngine();
    addTearDown(engine.dispose);

    final events = <ToneEvent>[];
    final sub = engine.toneEvents.listen(events.add);
    addTearDown(sub.cancel);

    final token = await engine.playTone(
      frequencyHz: 1000,
      levelDb: 40,
      ear: Ear.left,
      durationMs: 1200,
    );
    expect(token, isNotEmpty);
    expect(engine.isPlaying(), isTrue);
    expect(engine.lastPlayedFrequency, 1000);
    expect(engine.lastPlayedLevelDb, 40);
    expect(engine.lastPlayedEar, Ear.left);
    expect(engine.playCount, 1);

    await engine.stopTone();
    expect(engine.isPlaying(), isFalse);
    expect(engine.stopCount, 1);

    await pumpEventQueue();
    expect(events.map((e) => e.state), contains(ToneEventState.started));
    expect(events.map((e) => e.state), contains(ToneEventState.interrupted));
  });

  test('fake stimulus engine emits finished on completion', () async {
    final engine = FakeStimulusEngine();
    addTearDown(engine.dispose);

    final events = <ToneEvent>[];
    final sub = engine.toneEvents.listen(events.add);
    addTearDown(sub.cancel);

    await engine.playTone(frequencyHz: 2000, levelDb: 35, ear: Ear.right);
    engine.finishCurrentTone();

    await pumpEventQueue();
    expect(engine.isPlaying(), isFalse);
    expect(events.last.state, ToneEventState.finished);
  });
}

