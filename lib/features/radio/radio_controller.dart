import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/nocturne_audio_handler.dart';
import '../../core/audio/player_providers.dart';
import '../../core/di/providers.dart';
import '../../core/diagnostics/crash_log.dart';
import '../../domain/analysis/song_radio.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../smart_groups/smart_groups.dart';
import 'radio_session.dart';

/// How starting a radio went.
enum RadioStart {
  started,

  /// The song couldn't be analyzed (no analyzer here, or the file can't be read).
  notAnalyzed,

  /// Too few songs analyzed yet for a radio worth hearing.
  notReady,

  /// A radio was already starting: this tap is ignored.
  busy,
}

/// The radio playing now, if any — the queue sheet shows it.
class RadioState {
  const RadioState({this.seed, this.starting = false});

  /// The song the radio started from; null = no radio.
  final Track? seed;
  final bool starting;
}

class RadioController extends Notifier<RadioState> {
  RadioSession? _session;

  /// A radio needs at least this many analyzed songs besides the first.
  static const minSongs = 8;

  @override
  RadioState build() {
    ref.onDispose(() {
      // Unset first: the session's onEnded must not touch state while disposing
      final s = _session;
      _session = null;
      s?.stop();
    });
    return const RadioState();
  }

  /// Plays [seed] and the songs that sound like it. The queue is replaced only when a radio
  /// really starts.
  Future<RadioStart> start(Track seed) async {
    if (state.starting) return RadioStart.busy;
    state = RadioState(seed: state.seed, starting: true);
    try {
      return await _start(seed);
    } finally {
      if (state.starting) state = RadioState(seed: _session?.seed);
    }
  }

  Future<RadioStart> _start(Track seed) async {
    final analysis = ref.read(analysisRepositoryProvider);
    var embeddings = await analysis.embeddings();
    if (!embeddings.containsKey(seed.id) && ref.read(audioAnalyzerProvider).supported) {
      // The background analysis hasn't reached it yet: this one song now
      try {
        await analyzeAndSave(
          ref,
          PendingAnalysis(trackId: seed.id, path: seed.path, durationMs: seed.duration.inMilliseconds),
        );
        embeddings = await analysis.embeddings();
      } catch (e) {
        CrashLog.add('radio: analysis failed: ${seed.path.split('/').last}: $e');
      }
    }
    if (!embeddings.containsKey(seed.id)) return RadioStart.notAnalyzed;
    if (embeddings.length - 1 < minSongs) return RadioStart.notReady;

    final vibes = {for (final d in await analysis.watchVibeData().first) d.trackId: d};
    final tracks = {
      for (final t in await ref.read(libraryRepositoryProvider).getTracks(embeddings.keys.toList())) t.id: t,
    };
    final songs = [
      for (final MapEntry(key: id, value: embedding) in embeddings.entries)
        if (tracks[id] case final t?)
          RadioSong(
            trackId: id,
            artist: t.artist,
            embedding: embedding,
            bpm: vibes[id]?.scores?['_bpm'],
            key: vibes[id]?.scores?['_key']?.round(),
            keyClarity: vibes[id]?.scores?['_keyClarity'],
            rmsDb: vibes[id]?.rmsDb,
          ),
    ];
    final lib = await compute(_buildLibrary, songs);
    final now = DateTime.now();
    final plays = await ref.read(historyRepositoryProvider).playsSince(now.subtract(const Duration(days: 90)));

    late final RadioSession session;
    session = RadioSession(
      player: _HandlerPlayer(ref.read(audioHandlerProvider)),
      lib: lib,
      tracks: tracks,
      seed: seed,
      penalty: radioPenalties(plays, now: now),
      together: CoListening.fromPlays(plays),
      onEnded: () {
        if (_session != session) return;
        _session = null;
        state = const RadioState();
      },
    );
    if (!await session.start()) return RadioStart.notReady;
    _session?.stop();
    _session = session;
    state = RadioState(seed: seed);
    return RadioStart.started;
  }

  void stop() => _session?.stop();

  /// Whether "less like this" fits [trackId] in the radio playing (see RadioSession.canDislike).
  bool canDislike(int trackId) => _session?.canDislike(trackId) ?? false;

  /// "Less like this" on the song playing.
  Future<void> lessLikeThis() async => _session?.lessLikeThis();
}

RadioLibrary _buildLibrary(List<RadioSong> songs) => RadioLibrary(songs);

class _HandlerPlayer implements RadioPlayer {
  _HandlerPlayer(this._h);
  final NocturneAudioHandler _h;

  @override
  Stream<Track?> get currentTrack => _h.currentTrack;
  @override
  Stream<List<Track>> get trackQueue => _h.trackQueue;
  @override
  Stream<Duration> get position => _h.position;
  @override
  int get queueGeneration => _h.queueGeneration;
  @override
  Future<void> playTracks(List<Track> tracks) => _h.playTracks(tracks);
  @override
  Future<void> enqueue(List<Track> tracks) => _h.enqueue(tracks);
  @override
  Future<void> removeTrack(int trackId) => _h.removeTrack(trackId);
  @override
  Future<void> skipToNext() => _h.skipToNext();
}

final radioProvider = NotifierProvider<RadioController, RadioState>(RadioController.new);
