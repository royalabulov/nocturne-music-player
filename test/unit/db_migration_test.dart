import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:nocturne/data/db/app_database.dart';

// The schema each released version really had. These strings are frozen on purpose:
// never edit one, it describes databases that already exist on phones.
//
// When a table changes:
//   1. bump schemaVersion and add the step to onUpgrade,
//   2. add the new version to _schemas below,
//   3. seed its new data in _seed and check it in _expectUserData.

const _tracksV1 = 'CREATE TABLE "tracks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    '"path" TEXT NOT NULL UNIQUE, "title" TEXT NOT NULL, "artist" TEXT NOT NULL, "album" TEXT NOT NULL, '
    '"album_artist" TEXT NULL, "genre" TEXT NULL, "track_no" INTEGER NULL, "disc_no" INTEGER NULL, '
    '"year" INTEGER NULL, "duration_ms" INTEGER NOT NULL DEFAULT 0, "format" TEXT NOT NULL, '
    '"bitrate_kbps" INTEGER NULL, "sample_rate_hz" INTEGER NULL, "bit_depth" INTEGER NULL, '
    '"file_size" INTEGER NOT NULL DEFAULT 0, "cover_hash" TEXT NULL, "date_added" INTEGER NOT NULL, '
    '"date_modified" INTEGER NOT NULL, '
    '"is_missing" INTEGER NOT NULL DEFAULT 0 CHECK ("is_missing" IN (0, 1)))';

/// A fresh install at v2 or later has replay_gain_db in the middle of the table;
/// one upgraded from v1 has it at the end. Both occur in the wild.
const _tracksV2 = 'CREATE TABLE "tracks" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    '"path" TEXT NOT NULL UNIQUE, "title" TEXT NOT NULL, "artist" TEXT NOT NULL, "album" TEXT NOT NULL, '
    '"album_artist" TEXT NULL, "genre" TEXT NULL, "track_no" INTEGER NULL, "disc_no" INTEGER NULL, '
    '"year" INTEGER NULL, "duration_ms" INTEGER NOT NULL DEFAULT 0, "format" TEXT NOT NULL, '
    '"bitrate_kbps" INTEGER NULL, "sample_rate_hz" INTEGER NULL, "bit_depth" INTEGER NULL, '
    '"file_size" INTEGER NOT NULL DEFAULT 0, "cover_hash" TEXT NULL, "date_added" INTEGER NOT NULL, '
    '"date_modified" INTEGER NOT NULL, "replay_gain_db" REAL NULL, '
    '"is_missing" INTEGER NOT NULL DEFAULT 0 CHECK ("is_missing" IN (0, 1)))';

const _commonTables = [
  'CREATE TABLE "playlists" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, '
      '"description" TEXT NOT NULL DEFAULT \'\', "cover_hash" TEXT NULL, "created_at" INTEGER NOT NULL, '
      '"updated_at" INTEGER NOT NULL)',
  'CREATE TABLE "playlist_tracks" ("playlist_id" INTEGER NOT NULL REFERENCES playlists (id) ON DELETE CASCADE, '
      '"track_id" INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE, "position" INTEGER NOT NULL, '
      'PRIMARY KEY ("playlist_id", "track_id"))',
  'CREATE TABLE "favorites" ("track_id" INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE, '
      '"added_at" INTEGER NOT NULL, PRIMARY KEY ("track_id"))',
  'CREATE TABLE "play_history" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"track_id" INTEGER NOT NULL REFERENCES tracks (id) ON DELETE CASCADE, "played_at" INTEGER NOT NULL, '
      '"completed" INTEGER NOT NULL DEFAULT 0 CHECK ("completed" IN (0, 1)), '
      '"position_ms" INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE "scan_state" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'CREATE TABLE "scan_folders" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "path" TEXT NOT NULL UNIQUE, '
      '"enabled" INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)))',
  'CREATE INDEX idx_tracks_title ON tracks(title)',
  'CREATE INDEX idx_tracks_artist ON tracks(artist)',
  'CREATE INDEX idx_tracks_album ON tracks(album)',
  'CREATE INDEX idx_history_played ON play_history(played_at DESC)',
  'CREATE INDEX idx_history_track ON play_history(track_id)',
];

const _trackAnalyses = 'CREATE TABLE "track_analyses" ("track_id" INTEGER NOT NULL REFERENCES tracks (id) '
    'ON DELETE CASCADE, "version" INTEGER NOT NULL, "scores" TEXT NULL, "rms_db" REAL NULL, '
    '"analyzed_at" INTEGER NOT NULL, PRIMARY KEY ("track_id"))';

const _vibeLabels = 'CREATE TABLE "vibe_labels" ("track_id" INTEGER NOT NULL REFERENCES tracks (id) '
    'ON DELETE CASCADE, "mood" TEXT NOT NULL, "genre" TEXT NOT NULL, "predicted_mood" TEXT NOT NULL, '
    '"predicted_genre" TEXT NOT NULL, "labeled_at" INTEGER NOT NULL, PRIMARY KEY ("track_id"))';

const _trackLyrics = 'CREATE TABLE "track_lyrics" ("track_id" INTEGER NOT NULL REFERENCES tracks (id) '
    'ON DELETE CASCADE, "found" INTEGER NOT NULL CHECK ("found" IN (0, 1)), "synced" TEXT NULL, "plain" TEXT NULL, '
    '"instrumental" INTEGER NOT NULL DEFAULT 0 CHECK ("instrumental" IN (0, 1)), "fetched_at" INTEGER NOT NULL, '
    'PRIMARY KEY ("track_id"))';

const _schemas = <int, List<String>>{
  1: [_tracksV1, ..._commonTables],
  2: [_tracksV2, ..._commonTables],
  3: [_tracksV2, ..._commonTables, _trackAnalyses],
  4: [_tracksV2, ..._commonTables, _trackAnalyses, _vibeLabels],
  5: [_tracksV2, ..._commonTables, _trackAnalyses, _vibeLabels, _trackLyrics],
};

/// Builds a database the way version [version] left it, with one user's data in it.
void _seed(int version, void Function(String sql) execute) {
  _schemas[version]!.forEach(execute);
  execute("INSERT INTO tracks (id, path, title, artist, album, format, date_added, date_modified, file_size, duration_ms) "
      "VALUES (1, '/storage/emulated/0/Music/a.mp3', 'Üç Kalp', 'Sənətçi', 'Albom', 'mp3', 1000, 1100, 5000000, 180000), "
      "(2, '/storage/emulated/0/Music/b.flac', 'Second', 'Other', 'Other album', 'flac', 2000, 2100, 9000000, 240000)");
  execute("INSERT INTO playlists (id, name, description, created_at, updated_at) VALUES (1, 'Yol üçün', 'qeyd', 10, 20)");
  execute('INSERT INTO playlist_tracks (playlist_id, track_id, position) VALUES (1, 2, 0), (1, 1, 1)');
  execute('INSERT INTO favorites (track_id, added_at) VALUES (1, 30)');
  execute('INSERT INTO play_history (track_id, played_at, completed, position_ms) '
      'VALUES (1, 100, 1, 180000), (2, 200, 0, 30000)');
  execute("INSERT INTO scan_state (key, value) VALUES ('audioSettings', '{\"crossfade\":true}'), ('resumeTrackId', '2')");
  execute("INSERT INTO scan_folders (path, enabled) VALUES ('/storage/emulated/0/Music', 1), ('/storage/emulated/0/Other', 0)");
  if (version >= 2) execute('UPDATE tracks SET replay_gain_db = -7.35 WHERE id = 1');
  if (version >= 3) {
    execute("INSERT INTO track_analyses (track_id, version, scores, rms_db, analyzed_at) "
        "VALUES (1, 2, '{\"Pop music\":0.5}', -14.5, 300)");
  }
  if (version >= 4) {
    execute("INSERT INTO vibe_labels (track_id, mood, genre, predicted_mood, predicted_genre, labeled_at) "
        "VALUES (1, 'happy', 'pop', 'sad', 'rock', 400)");
  }
  if (version >= 5) {
    execute("INSERT INTO track_lyrics (track_id, found, plain, fetched_at) VALUES (1, 1, 'Söz', 500)");
  }
  execute('PRAGMA user_version = $version');
}

/// An existing database at [version], opened by the current code.
AppDatabase _upgradedFrom(int version) =>
    AppDatabase(NativeDatabase.memory(setup: (raw) => _seed(version, raw.execute)));

Future<List<String>> _column(AppDatabase db, String sql) async => [
      for (final row in await db.customSelect(sql).get()) '${row.data.values.first}',
    ];

/// Tables and indexes in a form that ignores column order and how they were created.
Future<Map<String, Object>> _describe(AppDatabase db) async {
  final out = <String, Object>{};
  final objects = await db
      .customSelect("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name")
      .get();
  for (final o in objects) {
    final name = o.read<String>('name');
    final sql = o.read<String>('sql');
    if (o.read<String>('type') == 'index') {
      out['index $name'] = sql;
      continue;
    }
    final columns = await db.customSelect('SELECT name, type, "notnull", dflt_value, pk FROM pragma_table_info(\'$name\')').get();
    final keys = await db.customSelect('SELECT "table", "from", "to", on_delete FROM pragma_foreign_key_list(\'$name\')').get();
    out['table $name'] = {
      'columns': {for (final c in columns) '${c.data}'},
      'foreign keys': {for (final k in keys) '${k.data}'},
      'checks': {for (final m in RegExp(r'CHECK \("\w+" IN \(0, 1\)\)').allMatches(sql)) m.group(0)},
    };
  }
  return out;
}

/// Everything the user would miss if a migration lost it.
Future<void> _expectUserData(AppDatabase db, {required int from}) async {
  final tracks = await (db.select(db.tracks)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
  expect(tracks.map((t) => t.path), ['/storage/emulated/0/Music/a.mp3', '/storage/emulated/0/Music/b.flac']);
  expect(tracks.first.title, 'Üç Kalp');
  expect(tracks.first.artist, 'Sənətçi');
  expect(tracks.first.durationMs, 180000);
  expect(tracks.first.fileSize, 5000000);
  expect(tracks.first.isMissing, isFalse);
  expect(tracks.first.replayGainDb, from >= 2 ? -7.35 : isNull);

  final playlist = (await db.select(db.playlists).get()).single;
  expect(playlist.name, 'Yol üçün');
  expect(playlist.description, 'qeyd');
  final order = await _column(db, 'SELECT track_id FROM playlist_tracks WHERE playlist_id = 1 ORDER BY position');
  expect(order, ['2', '1']);

  expect((await db.select(db.favorites).get()).single.trackId, 1);

  final plays = await (db.select(db.playHistory)..orderBy([(h) => OrderingTerm.asc(h.playedAt)])).get();
  expect(plays.map((h) => h.trackId), [1, 2]);
  expect(plays.first.completed, isTrue);
  expect(plays.last.positionMs, 30000);

  final settings = {for (final s in await db.select(db.scanState).get()) s.key: s.value};
  expect(settings, {'audioSettings': '{"crossfade":true}', 'resumeTrackId': '2'});

  final folders = {for (final f in await db.select(db.scanFolders).get()) f.path: f.enabled};
  expect(folders, {'/storage/emulated/0/Music': true, '/storage/emulated/0/Other': false});

  final analyses = await db.select(db.trackAnalyses).get();
  if (from >= 3) {
    expect(analyses.single.rmsDb, -14.5);
    expect(analyses.single.scores, '{"Pop music":0.5}');
  } else {
    expect(analyses, isEmpty);
  }

  final labels = await db.select(db.vibeLabels).get();
  if (from >= 4) {
    expect(labels.single.mood, 'happy');
    expect(labels.single.predictedGenre, 'rock');
  } else {
    expect(labels, isEmpty);
  }
}

Future<void> _expectHealthy(AppDatabase db) async {
  expect(await _column(db, 'PRAGMA integrity_check'), ['ok']);
  expect(await _column(db, 'PRAGMA foreign_key_check'), isEmpty);
  expect(await _column(db, 'PRAGMA foreign_keys'), ['1']);
}

void main() {
  final latest = _schemas.keys.last;

  group('fresh install', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('schema is exactly the frozen latest version', () async {
      expect(
        db.schemaVersion,
        latest,
        reason: 'schemaVersion changed: add the new version to _schemas in this file',
      );
      final actual = await _column(db, "SELECT sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'");
      expect(
        actual.toSet(),
        _schemas[latest]!.toSet(),
        reason: 'The tables changed without a migration: bump schemaVersion, add the onUpgrade '
            'step, then freeze the new schema in this file',
      );
    });

    test('starts with the default scan folders', () async {
      final folders = await db.select(db.scanFolders).get();
      expect(folders.map((f) => f.path), unorderedEquals(kDefaultScanFolders));
    });

    test('is healthy', () => _expectHealthy(db));
  });

  group('upgrade', () {
    for (var from = 1; from < latest; from++) {
      group('from v$from', () {
        late AppDatabase db;

        setUp(() => db = _upgradedFrom(from));
        tearDown(() => db.close());

        test('reaches the latest version', () async {
          expect(await _column(db, 'PRAGMA user_version'), ['$latest']);
        });

        test('keeps all user data', () => _expectUserData(db, from: from));

        test('ends with the same schema as a fresh install', () async {
          final fresh = AppDatabase(NativeDatabase.memory());
          addTearDown(fresh.close);
          expect(await _describe(db), await _describe(fresh));
        });

        test('is healthy', () => _expectHealthy(db));

        test('new tables work and deleting a song still cleans up after it', () async {
          await db.customStatement("INSERT OR REPLACE INTO track_lyrics (track_id, found, plain, fetched_at) VALUES (1, 1, 'x', 1)");
          await db.customStatement('DELETE FROM tracks WHERE id = 1');
          for (final table in ['track_lyrics', 'vibe_labels', 'track_analyses', 'favorites']) {
            expect(await _column(db, 'SELECT track_id FROM $table'), isEmpty, reason: table);
          }
          expect(await _column(db, 'SELECT track_id FROM playlist_tracks'), ['2']);
          expect(await _column(db, 'SELECT track_id FROM play_history'), ['2']);
        });
      });
    }

    test('adding a song works on a database upgraded from the oldest version', () async {
      final db = _upgradedFrom(1);
      addTearDown(db.close);
      await db.customStatement(
        "INSERT INTO tracks (path, title, artist, album, format, date_added, date_modified, replay_gain_db) "
        "VALUES ('/storage/emulated/0/Music/c.mp3', 'Third', 'A', 'B', 'mp3', 1, 1, -3.5)",
      );
      final added = await (db.select(db.tracks)..where((t) => t.title.equals('Third'))).getSingle();
      expect(added.replayGainDb, -3.5);
    });
  });

  group('on disk', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nocturne_migration');
      file = File(p.join(dir.path, 'sonar.sqlite'));
    });
    tearDown(() => dir.delete(recursive: true));

    test('an upgraded database survives closing and reopening the app', () async {
      final previous = latest - 1;
      final first = AppDatabase(NativeDatabase(file, setup: (raw) => _seed(previous, raw.execute)));
      await _expectUserData(first, from: previous);
      await first.customStatement("INSERT INTO scan_state (key, value) VALUES ('afterUpgrade', '1')");
      await first.close();

      // Second launch: nothing to migrate, nothing lost
      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      expect(await _column(second, 'PRAGMA user_version'), ['$latest']);
      expect(await _column(second, "SELECT value FROM scan_state WHERE key = 'afterUpgrade'"), ['1']);
      await _expectHealthy(second);
    });
  });
}
