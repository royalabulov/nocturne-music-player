import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/constants.dart';
import '../../core/di/providers.dart';
import '../../core/diagnostics/crash_log.dart';
import '../../data/analysis/music_features.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../library_scan/scan_controller.dart';
import 'vibe_classifier.dart';
import 'vibe_review.dart';

// ───────────────────────── background analysis ─────────────────────────

/// Settings → "Smart groups analysis" (on by default).
const kSmartAnalysisKey = 'smartAnalysis';

/// Runs unanalyzed songs through the Kotlin AudioAnalyzer one by one.
/// The heavy work is on a native background thread; only the queue is managed here.
/// Starts on its own after a scan (new songs) and when the app opens.
class SmartAnalysisController extends Notifier<bool> {
  bool _stop = false;

  @override
  bool build() {
    ref.onDispose(() => _stop = true);
    // Scan finished → there may be new songs
    ref.listen(scanControllerProvider.select((s) => s.isRunning), (was, now) {
      if (was == true && !now) start();
    });
    return false; // running
  }

  Future<void> start() async {
    if (state) return;
    final source = ref.read(audioAnalyzerProvider);
    if (!source.supported) return;
    final enabled = await ref.read(libraryRepositoryProvider).getSetting(kSmartAnalysisKey);
    if (enabled == 'false') return;

    final repo = ref.read(analysisRepositoryProvider);
    _stop = false;
    state = true;
    try {
      while (!_stop) {
        final batch = await repo.pending(kVibeAnalysisVersion);
        if (batch.isEmpty) break;
        for (final p in batch) {
          if (_stop) break;
          try {
            final r = await source.analyze(p.path, p.durationMs);
            // Tempo / major-minor / brightness — heavy FFT work off the UI isolate
            final segments = r.segments;
            final features = await Isolate.run(() => extractMusicFeatures(segments));
            await repo.save(p.trackId, kVibeAnalysisVersion, scores: {...r.scores, ...features}, rmsDb: r.rmsDb);
          } catch (e) {
            // Corrupt/unreadable file: record it so it doesn't get stuck in the queue
            await repo.save(p.trackId, kVibeAnalysisVersion);
            CrashLog.add('vibe analysis failed: ${p.path}: $e');
          }
          // Breathing room for UI and playback: the native work is on its own thread, but the channel is on the UI isolate
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
    } finally {
      state = false;
    }
  }

  void stop() => _stop = true;

  Future<void> setEnabled(bool on) async {
    await ref.read(libraryRepositoryProvider).setSetting(kSmartAnalysisKey, '$on');
    on ? unawaited(start()) : stop();
  }
}

final smartAnalysisProvider = NotifierProvider<SmartAnalysisController, bool>(SmartAnalysisController.new);

final analysisProgressProvider = StreamProvider<AnalysisProgress>(
  (ref) => ref.watch(analysisRepositoryProvider).watchProgress(kVibeAnalysisVersion),
);

// ───────────────────────── groups ─────────────────────────

/// The classifier's raw prediction (no corrections) — "Check groups" compares against this.
final vibeDataProvider = StreamProvider<List<TrackVibeData>>(
  (ref) => ref
      .watch(analysisRepositoryProvider)
      .watchVibeData()
      .throttleTime(const Duration(seconds: 2), leading: true, trailing: true),
);

/// trackId → mood/genre. The DB changes after every song while analysis runs —
/// recomputed once every 2 s. Large libraries use a separate isolate.
final vibePredictionsProvider = FutureProvider<Map<int, VibeResult>>((ref) async {
  final data = await ref.watch(vibeDataProvider.future);
  return data.length > 1500 ? compute(classifyLibrary, data) : classifyLibrary(data);
});

final vibeLabelsProvider = StreamProvider<List<VibeLabel>>(
  (ref) => ref.watch(analysisRepositoryProvider).watchLabels(),
);

/// Prediction + the user's corrections (labels win). null = loading.
final vibeResultsProvider = Provider<Map<int, VibeResult>?>((ref) {
  final predicted = ref.watch(vibePredictionsProvider).value;
  final labels = ref.watch(vibeLabelsProvider).value;
  if (predicted == null || labels == null) return null;
  return applyLabels(predicted, labels);
});

enum SmartGroupKind { mood, genre }

class SmartGroup {
  const SmartGroup({required this.kind, required this.id, required this.title, required this.emoji, required this.tracks});
  final SmartGroupKind kind;
  final String id; // Mood.name / Genre.name
  final String title;
  final String emoji;
  final List<Track> tracks;

  String get key => '${kind.name}:$id';
}

class SmartGroups {
  const SmartGroups({required this.moods, required this.genres});
  final List<SmartGroup> moods;
  final List<SmartGroup> genres;
  bool get isEmpty => moods.isEmpty && genres.isEmpty;

  SmartGroup? byKey(String key) => [...moods, ...genres].where((g) => g.key == key).firstOrNull;
}

const _all = (sort: TrackSort.recentlyAdded, query: '');

/// null = still loading.
final smartGroupsProvider = Provider.autoDispose<SmartGroups?>((ref) {
  final tracks = ref.watch(tracksProvider(_all)).value;
  final vibes = ref.watch(vibeResultsProvider);
  if (tracks == null || vibes == null) return null;
  return buildSmartGroups(tracks, vibes);
});

@visibleForTesting
SmartGroups buildSmartGroups(List<Track> tracks, Map<int, VibeResult> vibes) {
  final byMood = <Mood, List<Track>>{};
  final byGenre = <Genre, List<Track>>{};
  for (final t in tracks) {
    final v = vibes[t.id];
    if (v == null) continue;
    if (v.mood != null) (byMood[v.mood!] ??= []).add(t);
    if (v.genre != null) (byGenre[v.genre!] ??= []).add(t);
  }
  return SmartGroups(
    moods: [
      for (final m in Mood.values)
        if (byMood[m] case final l?)
          SmartGroup(kind: SmartGroupKind.mood, id: m.name, title: m.label, emoji: m.emoji, tracks: l),
    ],
    // Largest genre first
    genres: [
      for (final e in byGenre.entries)
        SmartGroup(kind: SmartGroupKind.genre, id: e.key.name, title: e.key.label, emoji: e.key.emoji, tracks: e.value),
    ]..sort((a, b) => b.tracks.length.compareTo(a.tracks.length)),
  );
}

const kVibeReviewRoute = '/home/vibe-review';
const kVibesRoute = '/home/vibes';

String smartGroupRoute(String key) => '/home/vibe?k=${Uri.encodeQueryComponent(key)}';
