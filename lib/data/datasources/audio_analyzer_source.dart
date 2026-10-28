import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kotlin `AudioAnalyzer` (MainActivity "analyzeAudio") — YAMNet, tam offline.
class AudioAnalyzerSource {
  static const _ch = MethodChannel('com.royal.sonar/media_store');

  /// Analysis is only possible on Android (not in the web demo / tests).
  bool get supported => !kIsWeb && Platform.isAndroid;

  /// Throws [AudioAnalysisException] on error. [segments] — 16 kHz mono parts
  /// for tempo/key analysis (music_features.dart).
  Future<({Map<String, double> scores, double rmsDb, List<Float32List> segments})> analyze(
    String path,
    int durationMs,
  ) async {
    final r = await _ch.invokeMethod<Object?>('analyzeAudio', {'path': path, 'durationMs': durationMs});
    if (r is! Map) throw AudioAnalysisException('$r');
    final raw = r['scores'] as Map;
    return (
      scores: {for (final e in raw.entries) e.key as String: (e.value as num).toDouble()},
      rmsDb: (r['rmsDb'] as num).toDouble(),
      segments: [for (final s in (r['segments'] as List? ?? const [])) s as Float32List],
    );
  }
}

class AudioAnalysisException implements Exception {
  AudioAnalysisException(this.message);
  final String message;

  @override
  String toString() => 'AudioAnalysisException: $message';
}
