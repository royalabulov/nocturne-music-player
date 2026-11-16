import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One song's analysis from [AudioAnalyzerSource.analyze].
typedef AnalyzedAudio = ({Map<String, double> scores, double rmsDb, List<Float32List> segments, Float32List? embedding});

/// Kotlin `AudioAnalyzer` (MainActivity "analyzeAudio") — YAMNet, fully offline.
class AudioAnalyzerSource {
  static const _ch = MethodChannel('com.nocturne/audio_analysis');

  /// Analysis is only possible on Android (not in the web demo / tests).
  bool get supported => !kIsWeb && Platform.isAndroid;

  /// Throws [AudioAnalysisException] on error. [segments] — 16 kHz mono parts
  /// for tempo/key analysis (music_features.dart). [embedding] — YAMNet's 1024 numbers
  /// for song radio; null when the model doesn't output it.
  Future<AnalyzedAudio> analyze(String path, int durationMs) async {
    final Map<Object?, Object?>? r;
    try {
      r = await _ch.invokeMapMethod<Object?, Object?>('analyzeAudio', {'path': path, 'durationMs': durationMs});
    } on PlatformException catch (e) {
      throw AudioAnalysisException(e.message ?? e.code);
    }
    if (r == null) throw AudioAnalysisException('no result');
    final raw = r['scores']! as Map;
    return (
      scores: {for (final e in raw.entries) e.key as String: (e.value as num).toDouble()},
      rmsDb: (r['rmsDb'] as num).toDouble(),
      segments: [for (final s in (r['segments'] as List? ?? const [])) s as Float32List],
      embedding: r['embedding'] as Float32List?,
    );
  }
}

class AudioAnalysisException implements Exception {
  AudioAnalysisException(this.message);
  final String message;

  @override
  String toString() => 'AudioAnalysisException: $message';
}
