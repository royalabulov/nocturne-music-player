import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Default scan folders. Written to the DB on first launch;
/// the user can change them in Settings. No folder named after a video downloader app (it was
/// snaptube's): the Play listing and a public repo should not read as pointing users to one.
/// Phones that already have it keep it until the user removes it.
const kDefaultScanFolders = <String>[
  '/storage/emulated/0/Music',
  '/storage/emulated/0/Download',
  '/storage/emulated/0/Telegram/Telegram Audio',
];

@DriftDatabase(tables: [
  Tracks, Playlists, PlaylistTracks, Favorites, PlayHistory, ScanState, ScanFolders, TrackAnalyses, VibeLabels,
  TrackLyrics,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// The file is `<app documents>/<fileName>.sqlite`, drift_flutter's default place.
  static const fileName = 'sonar';

  static QueryExecutor _open() => driftDatabase(
        // The app's old name, on every installed phone: renaming the file loses the library
        name: fileName,
        native: const DriftNativeOptions(shareAcrossIsolates: true),
      );

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX idx_tracks_title ON tracks(title)');
          await customStatement('CREATE INDEX idx_tracks_artist ON tracks(artist)');
          await customStatement('CREATE INDEX idx_tracks_album ON tracks(album)');
          await customStatement('CREATE INDEX idx_history_played ON play_history(played_at DESC)');
          await customStatement('CREATE INDEX idx_history_track ON play_history(track_id)');
          await batch((b) {
            b.insertAll(scanFolders, [
              for (final p in kDefaultScanFolders) ScanFoldersCompanion.insert(path: p),
            ]);
          });
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(tracks, tracks.replayGainDb);
          if (from < 3) await m.createTable(trackAnalyses);
          if (from < 4) await m.createTable(vibeLabels);
          if (from < 5) await m.createTable(trackLyrics);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
