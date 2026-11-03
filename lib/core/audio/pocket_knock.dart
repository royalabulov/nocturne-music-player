import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sonar_audio_handler.dart';

/// Pocket knock: knock on the phone 2 times = next song, 3 times = previous song.
/// Detection is native (KnockDetector.kt, screen off only); here it is switched on only
/// while the setting is on AND music is playing, and the knocks are turned into skips.
class PocketKnock {
  PocketKnock(this._handler) {
    if (kIsWeb) return;
    _ch.setMethodCallHandler(_onCall);
    _sub = _handler.playbackState.map((s) => s.playing).distinct().listen((p) {
      _playing = p;
      _push();
    });
  }

  static const _ch = MethodChannel('com.nocturne/knock');
  final SonarAudioHandler _handler;
  StreamSubscription? _sub;
  bool _enabled = false, _playing = false;
  int _sensitivity = 1;

  /// sensitivity: 0 = low, 1 = medium, 2 = high.
  void configure({required bool enabled, required int sensitivity}) {
    _enabled = enabled;
    _sensitivity = sensitivity;
    _push();
  }

  void _push() {
    if (kIsWeb) return;
    _ch.invokeMethod('update', {'on': _enabled && _playing, 'sensitivity': _sensitivity}).catchError(
      (Object e) => debugPrint('pocket knock: $e'),
    );
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'knock' || !_enabled) return;
    switch (call.arguments) {
      case 2:
        await _handler.skipToNext();
      case 3:
        // Always the previous song (not "restart this one" like the headset button)
        await _handler.skipToPreviousTrack();
    }
  }

  void dispose() => _sub?.cancel();
}
