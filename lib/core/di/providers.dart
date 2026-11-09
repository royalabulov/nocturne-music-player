import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/audio_analyzer_source.dart';
import '../../data/datasources/cover_cache.dart';
import '../../data/datasources/folder_source.dart';
import '../../data/datasources/media_store_source.dart';
import '../../data/datasources/playback_service_source.dart';
import '../../data/mappers/track_mapper.dart';
import '../../data/repositories/analysis_repository_impl.dart';
import '../../data/repositories/history_repository_impl.dart';
import '../../data/repositories/library_repository_impl.dart';
import '../../data/repositories/lyrics_repository_impl.dart';
import '../../data/repositories/playlist_repository_impl.dart';
import '../../data/services/backup_service.dart';
import '../../data/services/library_scanner.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/device_files.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import 'settings_providers.dart';

export 'settings_providers.dart';

// ── infrastructure singletons ─────────────────────────────

/// The phone's files as the features see them ("Open with", import, saving to Download).
final deviceFilesProvider = Provider<DeviceFiles>((_) => MediaStoreSource());

/// Lets the playback service release the CPU and its notification while nothing plays.
final playbackServiceProvider = Provider<PlaybackServiceSource>((_) => PlaybackServiceSource());

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
  (ref, key) => ref.watch(settingsRepositoryProvider).watchSetting(key).map((v) => v != 'false'),
);

final stringSettingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(settingsRepositoryProvider).watchSetting(key),
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

/// Lyrics: the song file, saved LRCLIB answers, LRCLIB.
final lyricsRepositoryProvider = Provider<LyricsRepository>(
  (ref) => LyricsRepositoryImpl(ref.watch(databaseProvider)),
);

final audioAnalyzerProvider = Provider<AudioAnalyzerSource>((_) => AudioAnalyzerSource());

final playlistRepositoryProvider = Provider<PlaylistRepository>(
  (ref) => PlaylistRepositoryImpl(
    ref.watch(databaseProvider),
    TrackMapper(ref.watch(coverCacheProvider)),
    ref.watch(coverCacheProvider),
  ),
);

// Period start is taken when the provider is created; autoDispose → a new
// "today" when the Recent screen is left and opened again.
final recentlyPlayedProvider = StreamProvider.autoDispose.family<List<PlayedTrack>, PlayPeriod>(
  (ref, period) =>
      ref.watch(historyRepositoryProvider).watchRecentlyPlayed(since: period.start(DateTime.now())),
);

final mostPlayedProvider = StreamProvider.autoDispose.family<List<PlayedTrack>, PlayPeriod>(
  (ref, period) => ref.watch(historyRepositoryProvider).watchMostPlayed(since: period.start(DateTime.now())),
);

final recommendedProvider = StreamProvider<List<PlayedTrack>>(
  (ref) => ref.watch(historyRepositoryProvider).watchRecommended(limit: 5),
);

final playStatsProvider = StreamProvider.autoDispose.family<PlayStats, PlayPeriod>(
  (ref, period) => ref.watch(historyRepositoryProvider).watchPlayStats(since: period.start(DateTime.now())),
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

