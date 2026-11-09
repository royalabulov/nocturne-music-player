import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/service_release.dart';

/// The playback service kept the CPU awake while paused, and its notification after Stop
/// (seen on the phone: 6+ minutes with nothing playing). It is told each time.
void main() {
  PlaybackState state({required bool playing, AudioProcessingState p = AudioProcessingState.ready}) =>
      PlaybackState(playing: playing, processingState: p);

  test('each pause and each stop is told once; playing is left to audio_service', () async {
    final states = StreamController<PlaybackState>();
    final calls = <String>[];
    final sub = releaseServiceWhenIdle(
      states.stream,
      paused: () async => calls.add('paused'),
      stopped: () async => calls.add('stopped'),
    );
    for (final s in [
      state(playing: true),
      state(playing: true, p: AudioProcessingState.buffering),
      state(playing: false), // pause
      state(playing: false), // the same again: nothing new
      state(playing: true),
      state(playing: false, p: AudioProcessingState.completed), // end of the queue
      state(playing: false, p: AudioProcessingState.idle), // stop
      state(playing: true), // played again
      state(playing: false, p: AudioProcessingState.idle), // mini player closed while playing
    ]) {
      states.add(s);
    }
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['paused', 'paused', 'stopped', 'stopped']);
    await sub.cancel();
    await states.close();
  });
}
