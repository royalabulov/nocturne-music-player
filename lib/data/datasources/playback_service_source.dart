import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kotlin `PlaybackServiceControl`: the playback service lets go of the CPU (and, once
/// stopped, of the notification) while nothing plays. audio_service doesn't, with the
/// settings this app needs (see app_runner.dart).
class PlaybackServiceSource {
  static const _ch = MethodChannel('com.nocturne/playback_service');

  /// Paused: the notification stays, the CPU may sleep.
  Future<void> paused() => _call('paused');

  /// Stopped: the notification goes too.
  Future<void> stopped() => _call('stopped');

  /// Whether the phone can give a player a system equalizer (Kotlin `EqualizerProbe`). Asked
  /// before the players exist: one that can't make it would play nothing. Unknown counts as
  /// yes, as it always did.
  Future<bool> equalizerWorks() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _ch.invokeMethod<bool>('equalizerWorks') ?? true;
    } catch (e) {
      debugPrint('equalizer probe: $e');
      return true;
    }
  }

  Future<void> _call(String method) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _ch.invokeMethod<bool>(method);
    } catch (e) {
      // Nothing worse than before: the service keeps the CPU awake until it is destroyed
      debugPrint('playback service $method: $e');
    }
  }
}
