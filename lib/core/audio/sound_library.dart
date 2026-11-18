import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/analysis/smooth_shuffle.dart';
import '../../domain/analysis/song_radio.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../di/providers.dart';
import 'nocturne_audio_handler.dart';

/// The analyzed songs as radio and smooth shuffle compare them: embedding, artist, tempo, key
/// and loudness, read from the database.
class SoundLibraryLoader {
  SoundLibraryLoader(this._analysis, this._library);

  final AnalysisRepository _analysis;
  final LibraryRepository _library;

  /// Every song with an embedding: trackId → packed embedding.
  Future<Map<int, Uint8List>> embeddings() => _analysis.embeddings();

  /// The songs of [embeddings] that are still in the library, and those tracks.
  Future<({List<RadioSong> songs, Map<int, Track> tracks})> songs(Map<int, Uint8List> embeddings) async {
    final vibes = {for (final d in await _analysis.watchVibeData().first) d.trackId: d};
    final tracks = {
      for (final t in await _library.getTracks(embeddings.keys.toList())) t.id: t,
    };
    return (
      songs: [
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
      ],
      tracks: tracks,
    );
  }

  /// Smooth shuffle for the audio handler (see smoothShuffleOrder). The whole library is
  /// loaded, not only the queue: songs are compared in the space of the listener's library, so
  /// a short playlist is ordered as well as a long one. The work runs off the UI thread.
  Future<List<int>?> smoothOrder(List<Track> queue, int first) async {
    final embeddings = await this.embeddings();
    final ids = [for (final t in queue) t.id];
    // Too little analyzed: not worth loading anything
    final analyzed = ids.where(embeddings.containsKey).length;
    if (analyzed < ids.length * smoothShuffleMinShare) return null;
    final (:songs, tracks: _) = await this.songs(embeddings);
    return compute(_order, (songs: songs, ids: ids, first: first));
  }
}

List<int>? _order(({List<RadioSong> songs, List<int> ids, int first}) a) =>
    smoothShuffleOrder(RadioLibrary(a.songs), a.ids, first: a.first);

final soundLibraryProvider = Provider<SoundLibraryLoader>(
  (ref) => SoundLibraryLoader(ref.watch(analysisRepositoryProvider), ref.watch(libraryRepositoryProvider)),
);

/// What the handler calls when smooth shuffle is on.
final smoothShuffleOrdererProvider = Provider<ShuffleOrderer>((ref) => ref.watch(soundLibraryProvider).smoothOrder);
