import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/audio_analyzer_source.dart';
import '../../data/datasources/cover_cache.dart';
import '../../data/datasources/folder_source.dart';
import '../../data/datasources/media_store_source.dart';
import '../../data/db/app_database.dart';
import '../../data/mappers/track_mapper.dart';
import '../../data/repositories/analysis_repository_impl.dart';
import '../../data/repositories/history_repository_impl.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../data/repositories/playlist_repository_impl.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/library_scanner.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/playlist_repository.dart';

// ── infrastructure singletons ─────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Warmed up in main() so cover paths can be resolved synchronously.
final coverCacheProvider = Provider<CoverCache>((_) => CoverCache());

final libraryScannerProvider = Provider<LibraryScanner>((ref) {
  final s = LibraryScanner(
    db: ref.watch(databaseProvider),
    mediaStore: MediaStoreSource(),
    folders: FolderSource(),
    covers: ref.watch(coverCacheProvider),
  );
  ref.onDispose(s.dispose);
  return s;
});

// ── repositories ──────────────────────────────────────────

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepositoryImpl(
    ref.watch(databaseProvider),
    TrackMapper(ref.watch(coverCacheProvider)),
    filter: ref.watch(trackFilterProvider),
  ),
);

// ── library streams (watched by the UI) ───────────────

final libraryStatsProvider = StreamProvider<LibraryStats>(
  (ref) => ref.watch(libraryRepositoryProvider).watchStats(),
);

final recentlyAddedProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchRecentlyAdded(limit: 10),
);

/// (sort, query) → track list. Home's Library section + search.
final tracksProvider = StreamProvider.autoDispose.family<List<Track>, ({TrackSort sort, String query})>(
  (ref, args) => ref.watch(libraryRepositoryProvider).watchTracks(sort: args.sort, query: args.query),
);

final favoritesProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFavorites(),
);

final favoriteIdsProvider = StreamProvider<Set<int>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFavoriteIds(),
);

final scanFoldersProvider = StreamProvider<List<ScanFolder>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchScanFolders(),
);

/// Bool setting in scan_state ("autoScan" ...). Default true.
final boolSettingProvider = StreamProvider.family<bool, String>(
  (ref, key) => ref.watch(libraryRepositoryProvider).watchSetting(key).map((v) => v != 'false'),
);

// ── history / playlists ───────────────────────────────────

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepositoryImpl(
    ref.watch(databaseProvider),
    TrackMapper(ref.watch(coverCacheProvider)),
    filter: ref.watch(trackFilterProvider),
  ),
);

/// Smart groups: YAMNet analysis results.
final analysisRepositoryProvider = Provider<AnalysisRepository>(
  (ref) => AnalysisRepositoryImpl(ref.watch(databaseProvider), filter: ref.watch(trackFilterProvider)),
);

final audioAnalyzerProvider = Provider<AudioAnalyzerSource>((_) => AudioAnalyzerSource());

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepositoryImpl(
    ref.watch(databaseProvider),
    TrackMapper(ref.watch(coverCacheProvider)),
    ref.watch(coverCacheProvider),
  ),
);

final recentlyPlayedProvider = StreamProvider<List<PlayedTrack>>(
  (ref) => ref.watch(historyRepositoryProvider).watchRecentlyPlayed(),
);

final mostPlayedProvider = StreamProvider<List<PlayedTrack>>(
  (ref) => ref.watch(historyRepositoryProvider).watchMostPlayed(),
);

final recommendedProvider = StreamProvider<List<PlayedTrack>>(
  (ref) => ref.watch(historyRepositoryProvider).watchRecommended(limit: 5),
);

final weekStatsProvider = StreamProvider<WeekStats>(
  (ref) => ref.watch(historyRepositoryProvider).watchWeekStats(),
);

final resumePointProvider = StreamProvider<ResumePoint?>(
  (ref) => ref.watch(historyRepositoryProvider).watchResumePoint(),
);

final playlistsProvider = StreamProvider<List<Playlist>>(
  (ref) => ref.watch(playlistRepositoryProvider).watchPlaylists(),
);

final playlistProvider = StreamProvider.autoDispose.family<Playlist?, int>(
  (ref, id) => ref.watch(playlistRepositoryProvider).watchPlaylist(id),
);

final playlistTracksProvider = StreamProvider.autoDispose.family<List<Track>, int>(
  (ref, id) => ref.watch(playlistRepositoryProvider).watchTracks(id),
);

final playlistIdsContainingProvider = StreamProvider.autoDispose.family<Set<int>, int>(
  (ref, trackId) => ref.watch(playlistRepositoryProvider).watchPlaylistIdsContaining(trackId),
);

// ── backup (Settings → Data) ──────────────────────────────

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));

// ── library filter (Settings → Library filter) ────────────

/// Size/length range of visible songs. When it changes, the repositories are
/// rebuilt → every list (Home, Recent, Vibes...) updates immediately.
final trackFilterProvider = NotifierProvider<TrackFilterController, TrackFilter>(TrackFilterController.new);

class TrackFilterController extends Notifier<TrackFilter> {
  static const _keys = (minBytes: 'filterMinBytes', maxBytes: 'filterMaxBytes', minMs: 'filterMinMs', maxMs: 'filterMaxMs');

  @override
  TrackFilter build() {
    _load();
    return TrackFilter.defaults;
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final rows = [for (final r in await db.select(db.scanState).get()) if (r.key.startsWith('filter')) r];
    if (rows.isEmpty) return;
    final v = {for (final r in rows) r.key: int.tryParse(r.value)};
    state = TrackFilter(
      minBytes: v[_keys.minBytes] ?? TrackFilter.defaults.minBytes,
      maxBytes: v[_keys.maxBytes],
      minMs: v[_keys.minMs] ?? TrackFilter.defaults.minMs,
      maxMs: v[_keys.maxMs],
    );
  }

  /// New range; null max = no limit (stored as an empty string).
  Future<void> set(TrackFilter f) async {
    state = f;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.setSetting(_keys.minBytes, '${f.minBytes}');
    await repo.setSetting(_keys.maxBytes, f.maxBytes == null ? '' : '${f.maxBytes}');
    await repo.setSetting(_keys.minMs, '${f.minMs}');
    await repo.setSetting(_keys.maxMs, f.maxMs == null ? '' : '${f.maxMs}');
  }

  Future<void> reset() => set(TrackFilter.defaults);
}
