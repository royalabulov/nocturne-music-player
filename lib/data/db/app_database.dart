import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Default scan folders. Written to the DB on first launch;
/// the user can change them in Settings.
const kDefaultScanFolders = <String>[
  '/storage/emulated/0/Music',
  '/storage/emulated/0/Download',
  '/storage/emulated/0/snaptube/download',
  '/storage/emulated/0/Telegram/Telegram Audio',
];

@DriftDatabase(tables: [
  Tracks, Playlists, PlaylistTracks, Favorites, PlayHistory, ScanState, ScanFolders, TrackAnalyses, VibeLabels,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(
        name: 'sonar',
        native: const DriftNativeOptions(shareAcrossIsolates: true),
      );

  @override
  int get schemaVersion => 4;

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
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
