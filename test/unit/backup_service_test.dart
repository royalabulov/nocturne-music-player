import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/services/artist_overrides.dart';
import 'package:nocturne/data/services/backup_service.dart';

/// Backup → new (reinstalled) DB → restore: data comes back by file path
/// even though the track ids differ.
void main() {
  Future<int> addTrack(AppDatabase db, String name) => db.into(db.tracks).insert(TracksCompanion.insert(
        path: '/music/$name.mp3',
        title: name,
        artist: 'A',
        album: 'B',
        format: 'mp3',
        durationMs: const Value(200000),
        fileSize: const Value(4000000),
        dateAdded: 1,
        dateModified: 1,
      ));

  test('export → fresh install → restore keeps favorites, playlists, history', () async {
    final oldDb = AppDatabase(NativeDatabase.memory());
    final a = await addTrack(oldDb, 'a');
    final b = await addTrack(oldDb, 'b');
    await addTrack(oldDb, 'gone');
    await oldDb.into(oldDb.favorites).insert(FavoritesCompanion.insert(trackId: Value(b), addedAt: 5));
    final pl = await oldDb.into(oldDb.playlists).insert(PlaylistsCompanion.insert(name: 'Mix', createdAt: 1, updatedAt: 1));
    await oldDb.into(oldDb.playlistTracks).insert(PlaylistTracksCompanion.insert(playlistId: pl, trackId: b, position: 0));
    await oldDb.into(oldDb.playlistTracks).insert(PlaylistTracksCompanion.insert(playlistId: pl, trackId: a, position: 1));
    await oldDb.into(oldDb.playHistory).insert(PlayHistoryCompanion.insert(trackId: a, playedAt: 100));
    await oldDb.into(oldDb.scanState).insert(ScanStateCompanion.insert(key: 'audioSettings', value: '{"crossfade":true}'));
    final json = await BackupService(oldDb).export();
    await oldDb.close();

    // New install: scanned in a different order, the 'gone' file doesn't exist
    final newDb = AppDatabase(NativeDatabase.memory());
    await addTrack(newDb, 'b');
    await addTrack(newDb, 'a');
    final svc = BackupService(newDb);
    final r = await svc.restore(json);
    expect(r.favorites, 1);
    expect(r.playlists, 1);
    expect(r.playlistTracks, 2);
    expect(r.plays, 1);

    final favPaths = [
      for (final f in await newDb.select(newDb.favorites).get())
        (await (newDb.select(newDb.tracks)..where((t) => t.id.equals(f.trackId))).getSingle()).path,
    ];
    expect(favPaths, ['/music/b.mp3']);
    final order = await (newDb.select(newDb.playlistTracks)..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
    final paths = {for (final t in await newDb.select(newDb.tracks).get()) t.id: t.path};
    expect(order.map((r) => paths[r.trackId]), ['/music/b.mp3', '/music/a.mp3']);
    final s = await (newDb.select(newDb.scanState)..where((s) => s.key.equals('audioSettings'))).getSingle();
    expect(s.value, contains('crossfade'));

    // A second restore duplicates nothing
    final again = await svc.restore(json);
    expect(again.favorites + again.playlists + again.playlistTracks + again.plays, 0);
    await newDb.close();
  });

  test('rejects non-backup files', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(() => BackupService(db).restore('{"hello":1}'), throwsFormatException);
    await db.close();
  });

  // A backup is a file from outside the app: it may be corrupt, edited or made by someone else.
  group('restore does not trust the file', () {
    late AppDatabase db;
    late BackupService svc;

    const song = '/music/a.mp3';
    const validPlaylist = {'name': 'Mix', 'createdAt': 1, 'updatedAt': 1, 'tracks': [song]};
    const validPlay = {'path': song, 'playedAt': 100};
    const validLabel = {
      'path': song,
      'mood': 'happy',
      'genre': 'pop',
      'predictedMood': 'sad',
      'predictedGenre': 'rock',
      'labeledAt': 1,
    };

    String backup([Map<String, Object?> fields = const {}]) =>
        jsonEncode({'format': BackupService.format, 'version': BackupService.version, ...fields});

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await addTrack(db, 'a');
      svc = BackupService(db);
    });
    tearDown(() => db.close());

    final malformed = <String, Map<String, Object?>>{
      'favorites is not a list': {'favorites': 'x'},
      'a favorite is not an object': {'favorites': [1]},
      'a favorite path is not text': {'favorites': [{'path': 1, 'addedAt': 1}]},
      'a favorite without a date': {'favorites': [{'path': song}]},
      'a favorite date is text': {'favorites': [{'path': song, 'addedAt': '1'}]},
      'a favorite date is negative': {'favorites': [{'path': song, 'addedAt': -1}]},
      'a playlist is not an object': {'playlists': ['x']},
      'a playlist name is not text': {'playlists': [{...validPlaylist, 'name': 1}]},
      'a playlist name is absurdly long': {'playlists': [{...validPlaylist, 'name': 'x' * 100000}]},
      'a playlist description is not text': {'playlists': [{...validPlaylist, 'description': 1}]},
      'a playlist date is negative': {'playlists': [{...validPlaylist, 'createdAt': -5}]},
      'playlist tracks is not a list': {'playlists': [{...validPlaylist, 'tracks': 'x'}]},
      'a playlist track is not text': {'playlists': [{...validPlaylist, 'tracks': [1]}]},
      'a play is not an object': {'history': [1]},
      'a play date is text': {'history': [{...validPlay, 'playedAt': 'x'}]},
      'a play date is negative': {'history': [{...validPlay, 'playedAt': -1}]},
      'a play position is negative': {'history': [{...validPlay, 'positionMs': -1}]},
      'a play flag is text': {'history': [{...validPlay, 'completed': 'yes'}]},
      'a label is not an object': {'vibeLabels': [1]},
      'a label value is not text': {'vibeLabels': [{...validLabel, 'mood': 1}]},
      'a label value is absurdly long': {'vibeLabels': [{...validLabel, 'genre': 'x' * 1000}]},
      'a label date is missing': {'vibeLabels': [{...validLabel}..remove('labeledAt')]},
      'settings is not an object': {'settings': []},
      'scan folders is not a list': {'scanFolders': 'x'},
      'a scan folder is not an object': {'scanFolders': [1]},
      'a scan folder path is not text': {'scanFolders': [{'path': 1}]},
      'edited artists is not a list': {'artistOverrides': {'/music/a.mp3': 'X'}},
      'an edited artist is not an object': {'artistOverrides': ['X']},
      'an edited artist name is not text': {'artistOverrides': [{'path': song, 'artist': 5}]},
      'an edited artist name is empty': {'artistOverrides': [{'path': song, 'artist': '  '}]},
      'an edited artist name is absurdly long': {'artistOverrides': [{'path': song, 'artist': 'x' * 100000}]},
      'an edited artist has no path': {'artistOverrides': [{'artist': 'X'}]},
    };
    for (final MapEntry(key: what, value: fields) in malformed.entries) {
      test('refused: $what', () async {
        await expectLater(svc.restore(backup(fields)), throwsFormatException);
      });
    }

    test('one bad value refuses the whole file: nothing is half-written', () async {
      final json = backup({
        'favorites': [{'path': song, 'addedAt': 1}],
        'playlists': [validPlaylist],
        'history': [{...validPlay, 'playedAt': 'broken'}],
      });
      await expectLater(svc.restore(json), throwsFormatException);
      expect(await db.select(db.favorites).get(), isEmpty);
      expect(await db.select(db.playlists).get(), isEmpty);
    });

    test('a file from a newer app version is refused, not misread', () async {
      final json = jsonEncode({
        'format': BackupService.format,
        'version': BackupService.version + 1,
        'favorites': [{'path': song, 'addedAt': 1}],
      });
      await expectLater(svc.restore(json), throwsFormatException);
      expect(await db.select(db.favorites).get(), isEmpty);
    });

    test('a version that is not a number is refused', () async {
      final json = jsonEncode({'format': BackupService.format, 'version': 'two'});
      await expectLater(svc.restore(json), throwsFormatException);
    });

    test('a file over the size limit is refused before parsing', () async {
      final small = BackupService(db, maxBytes: 100);
      await expectLater(small.restore(backup({'padding': 'x' * 200})), throwsFormatException);
    });

    test('not JSON at all, or JSON of the wrong shape, is refused', () async {
      await expectLater(svc.restore('not json'), throwsFormatException);
      await expectLater(svc.restore('[]'), throwsFormatException);
      await expectLater(svc.restore('null'), throwsFormatException);
    });

    test('only folders on shared storage become scan folders', () async {
      await svc.restore(backup({
        'scanFolders': [
          {'path': '/storage/emulated/0/My Music'},
          {'path': '/storage/1234-ABCD/Audio', 'enabled': false},
          {'path': '/data/user/0/com.nocturne/databases'},
          {'path': '/'},
          {'path': 'relative/folder'},
          {'path': '/storage/emulated/0/../../../data/user/0/com.nocturne'},
          {'path': '/storage/emulated/0/Android/data/com.nocturne/files'},
        ],
      }));
      final folders = {for (final f in await db.select(db.scanFolders).get()) f.path: f.enabled};
      expect(folders['/storage/emulated/0/My Music'], isTrue);
      expect(folders['/storage/1234-ABCD/Audio'], isFalse);
      expect(folders.keys.where((p) => !kDefaultScanFolders.contains(p)), hasLength(2));
    });

    test('only settings meant for backups are restored', () async {
      await svc.restore(backup({
        'settings': {
          'autoScan': 'false',
          'onlineMode': 'true',
          'tagReaderVersion': '0',
          'audioSettings': 5,
        },
      }));
      final saved = {for (final s in await db.select(db.scanState).get()) s.key: s.value};
      expect(saved, {'autoScan': 'false'});
    });

    test('the user\'s choices come back', () async {
      const choices = {
        'language': 'az',
        'lyricsOnline': 'false',
        'smartAnalysis': 'false',
        'librarySort': 'title',
        'groupSort': 'mostSongs',
        'favoritesSort': 'artist',
        'filterMinBytes': '358400',
        'filterMaxBytes': '',
        'filterMinMs': '45000',
        'filterMaxMs': '',
        'forgottenMinPlays': '3',
        'forgottenDays': '30',
      };
      await svc.restore(backup({'settings': choices}));
      expect({for (final s in await db.select(db.scanState).get()) s.key: s.value}, choices);
    });

    test('what belongs to this phone stays out, in both directions', () async {
      for (final e in const {
        'onlineMode': 'true',
        'forgottenRemind': 'true',
        'resumeTrackId': '1',
        'lastScanAt': '1',
        'artistOverrides': '{"/music/a.mp3":"X"}',
      }.entries) {
        await db.into(db.scanState).insert(ScanStateCompanion.insert(key: e.key, value: e.value));
      }
      final file = jsonDecode(await svc.export()) as Map<String, dynamic>;
      expect(file['settings'], isEmpty);

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await BackupService(other).restore(backup({
        'settings': {'onlineMode': 'true', 'forgottenRemind': 'true', 'resumeTrackId': '1', 'artistOverrides': '{}'},
      }));
      expect(await other.select(other.scanState).get(), isEmpty);
    });

    test('a number setting that is not a number is ignored', () async {
      await svc.restore(backup({
        'settings': {'filterMinBytes': 'x; DROP TABLE tracks', 'filterMinMs': '-5', 'forgottenDays': '30'},
      }));
      expect({for (final s in await db.select(db.scanState).get()) s.key: s.value}, {'forgottenDays': '30'});
    });

    group('edited artist names', () {
      const edited = {'path': song, 'artist': 'Xpert'};

      Future<String> artistOf(String path) async =>
          (await (db.select(db.tracks)..where((t) => t.path.equals(path))).getSingle()).artist;

      test('are saved in the backup and come back after a reinstall', () async {
        await db.into(db.scanState).insert(ArtistOverrides.row({song: 'Xpert'}));
        final json = await svc.export();

        final fresh = AppDatabase(NativeDatabase.memory());
        addTearDown(fresh.close);
        await addTrack(fresh, 'a');
        await BackupService(fresh).restore(json);

        expect(await ArtistOverrides.load(fresh), {song: 'Xpert'});
        final track = await (fresh.select(fresh.tracks)..where((t) => t.path.equals(song))).getSingle();
        expect(track.artist, 'Xpert');
      });

      test('the song on screen changes right away', () async {
        await svc.restore(backup({'artistOverrides': [edited]}));
        expect(await artistOf(song), 'Xpert');
      });

      test('a song not on this phone keeps its name for later and is not "missing"', () async {
        final r = await svc.restore(backup({
          'artistOverrides': [{'path': '/music/later.mp3', 'artist': 'Later'}],
        }));
        expect(r.missingTracks, 0);
        expect(await ArtistOverrides.load(db), {'/music/later.mp3': 'Later'});
      });

      test('merge: other edits stay, the backup wins for the same file', () async {
        await db.into(db.scanState).insert(ArtistOverrides.row({song: 'Old', '/music/b.mp3': 'Kept'}));
        await svc.restore(backup({'artistOverrides': [edited]}));
        expect(await ArtistOverrides.load(db), {song: 'Xpert', '/music/b.mp3': 'Kept'});
      });

      test('an old backup without them leaves the edits alone', () async {
        await db.into(db.scanState).insert(ArtistOverrides.row({song: 'Kept'}));
        await svc.restore(backup({'favorites': [{'path': song, 'addedAt': 1}]}));
        expect(await ArtistOverrides.load(db), {song: 'Kept'});
      });

      test('adding them did not raise the version: older apps refuse newer versions', () {
        expect(BackupService.version, 1);
      });
    });

    test('an old backup without the newer sections still restores', () async {
      final r = await svc.restore(jsonEncode({
        'format': BackupService.format,
        'version': 1,
        'favorites': [{'path': song, 'addedAt': 5}],
        'playlists': [{'name': 'Old', 'createdAt': 1, 'updatedAt': 2, 'tracks': [song]}],
        'history': [{'path': song, 'playedAt': 9}],
      }));
      expect(r.favorites, 1);
      expect(r.playlists, 1);
      expect(r.playlistTracks, 1);
      expect(r.plays, 1);
      final play = (await db.select(db.playHistory).get()).single;
      expect(play.completed, isFalse);
      expect(play.positionMs, 0);
    });

    test('songs that are not on this phone are counted, not an error', () async {
      final r = await svc.restore(backup({
        'favorites': [{'path': '/music/gone.mp3', 'addedAt': 1}],
      }));
      expect(r.favorites, 0);
      expect(r.missingTracks, 1);
    });

    test('labels and all optional fields come back typed', () async {
      await svc.restore(backup({
        'playlists': [{...validPlaylist, 'description': 'desc'}],
        'history': [{...validPlay, 'completed': true, 'positionMs': 7}],
        'vibeLabels': [validLabel],
      }));
      expect((await db.select(db.playlists).get()).single.description, 'desc');
      final play = (await db.select(db.playHistory).get()).single;
      expect(play.completed, isTrue);
      expect(play.positionMs, 7);
      final label = (await db.select(db.vibeLabels).get()).single;
      expect(label.mood, 'happy');
      expect(label.predictedGenre, 'rock');
    });
  });
}
