import 'dart:async';

import 'package:audio_service/audio_service.dart';

/// Tells the playback service each time playback stops being heard: [paused] when it pauses
/// (the notification stays, so play can come back after a call), [stopped] when it stops
/// for good. Without this the service kept the CPU awake and its notification up until
/// Android destroyed it (PlaybackServiceControl.kt).
StreamSubscription<void> releaseServiceWhenIdle(
  Stream<PlaybackState> states, {
  required Future<void> Function() paused,
  required Future<void> Function() stopped,
}) {
  return states
      .map((s) => s.processingState == AudioProcessingState.idle
          ? _Heard.stopped
          : s.playing
              ? _Heard.playing
              : _Heard.paused)
      .distinct()
      .listen((h) {
    switch (h) {
      case _Heard.paused:
        unawaited(paused());
      case _Heard.stopped:
        unawaited(stopped());
      case _Heard.playing:
        break; // audio_service takes the CPU and the foreground itself
    }
  });
}

enum _Heard { playing, paused, stopped }
