import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/datasources/audio_analyzer_source.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/repositories/analysis_repository.dart';
import 'package:nocturne/features/library_scan/permission_gate.dart';
import 'package:nocturne/features/library_scan/scan_controller.dart';
import 'package:nocturne/domain/entities/scan_progress.dart';
import 'package:nocturne/features/smart_groups/smart_groups.dart';

/// audio_service can start the app with no window; the analyzer's channel used to be set up
/// by the window, so every waiting song was recorded as "analysis failed" and left out of
/// smart groups for good.
void main() {
  test('no analyzer channel: no song is recorded as failed', () async {
    final repo = _Pending();
    final c = ProviderContainer(overrides: [
      audioAnalyzerProvider.overrideWithValue(_NoChannel()),
      analysisRepositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(DemoSettingsRepository()),
      scanControllerProvider.overrideWith(_Idle.new),
    ]);
    addTearDown(c.dispose);

    await c.read(smartAnalysisProvider.notifier).start();
    expect(repo.saved, isEmpty);
    expect(c.read(smartAnalysisProvider), isFalse, reason: 'it stops and can start again later');
  });

  test('a file the analyzer can\'t read is still recorded, so it doesn\'t block the queue', () async {
    final repo = _Pending();
    final c = ProviderContainer(overrides: [
      audioAnalyzerProvider.overrideWithValue(_Broken()),
      analysisRepositoryProvider.overrideWithValue(repo),
      settingsRepositoryProvider.overrideWithValue(DemoSettingsRepository()),
      scanControllerProvider.overrideWith(_Idle.new),
    ]);
    addTearDown(c.dispose);

    await c.read(smartAnalysisProvider.notifier).start();
    expect(repo.saved, [1, 2]);
  });
}

class _Pending extends DemoAnalysisRepository {
  _Pending() : super(DemoLibraryRepository());
  final saved = <int>[];

  @override
  Future<List<PendingAnalysis>> pending(int version, {int limit = 20}) async => [
        for (final id in [1, 2])
          if (!saved.contains(id)) PendingAnalysis(trackId: id, path: '/m/$id.mp3', durationMs: 200000),
      ];

  @override
  Future<void> save(int trackId, int version, {Map<String, double>? scores, double? rmsDb}) async => saved.add(trackId);
}

class _NoChannel extends AudioAnalyzerSource {
  @override
  bool get supported => true;

  @override
  Future<({Map<String, double> scores, double rmsDb, List<Float32List> segments})> analyze(String path, int durationMs) =>
      throw MissingPluginException('No implementation found for method analyzeAudio');
}

class _Broken extends _NoChannel {
  @override
  Future<({Map<String, double> scores, double rmsDb, List<Float32List> segments})> analyze(String path, int durationMs) =>
      throw AudioAnalysisException('no audio decoded');
}

class _Idle extends ScanController {
  @override
  LibraryScanState build() => const LibraryScanState(permission: MediaPermission.granted, progress: ScanProgress.idle);
}
