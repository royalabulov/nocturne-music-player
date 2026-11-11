import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/entities/scan_progress.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/datasources/folder_source.dart';
import 'package:nocturne/data/datasources/media_store_source.dart';
import 'package:nocturne/data/datasources/raw_audio.dart';
import 'package:nocturne/data/datasources/tag_reader.dart';
import 'package:nocturne/core/utils/bounded_isolate.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/services/backup_service.dart';
import 'package:nocturne/data/services/artist_overrides.dart';
import 'package:nocturne/data/services/library_scanner.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';
import 'package:nocturne/core/constants.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';

class _FakeStore extends MediaStoreSource {
  List<RawAudio> files = [];
  String? counter = 'v1;external_primary=5';
  @override
  Future<String?> generation() async => counter;
  bool broken = false;
  @override
  Future<List<RawAudio>> enumerate() async => broken ? throw StateError('MediaStore gone') : files;
  @override
  Future<void> notify(List<String> paths) async {}
}

/// Covers that land nowhere: [full] true = the disk is full and every write fails.
class _Covers extends CoverCache {
  _Covers(this.full);
  final bool Function() full;
  final given = <String?>[];

  @override
  Future<String> store(Uint8List bytes, {String? hash}) async {
    if (full()) throw const FileSystemException('No space left on device');
    given.add(hash);
    return hash ?? 'hash';
  }
}

/// A real cover folder in a temporary place.
class _CoversIn extends CoverCache {
  _CoversIn(this.dir);
  final Directory dir;
  @override
  Future<Directory> warmUp() async => dir;
}

class _NoFolders extends FolderSource {
  @override
  Future<List<RawAudio>> walk(Iterable<String> folders) async => const [];
}

/// "Adding new songs x/134" on every launch: files that didn't make it into the
/// library (short / unreadable) weren't in the DB → re-read on every scan.
void main() {
  late AppDatabase db;
  late _FakeStore store;
  late LibraryScanner scanner;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = _FakeStore();
    scanner = LibraryScanner(db: db, mediaStore: store, folders: _NoFolders(), covers: CoverCache());
  });
  tearDown(() => db.close());

  // Files that don't exist → tags can't be read, they don't enter the library (rejected)
  const a = RawAudio(path: '/nope/voice-note-1.ogg', size: 200 * 1024, dateModified: 1000);
  const b = RawAudio(path: '/nope/voice-note-2.ogg', size: 300 * 1024, dateModified: 2000);

  test('rejected files are not re-read on the next scan', () async {
    store.files = [a, b];
    final first = await scanner.scan();
    expect(first.total, 2);
    expect(await db.select(db.tracks).get(), isEmpty);

    final second = await scanner.scan();
    expect(second.total, 0);
  });

  group('a bad file must not stop the library', () {
    const poison = '/m/poison.mp3';
    late List<List<String>> calls;

    TagInfo tagOf(String path) => TagInfo(
          title: path.split('/').last,
          artist: 'A',
          album: 'B',
          durationMs: 100000,
          format: AudioFormat.mp3,
        );

    /// Like the real reader, except that a batch with the poison file blows up:
    /// its isolate ran out of memory or hung until the timeout.
    Future<Map<String, TagInfo?>> reader(List<String> paths) async {
      calls.add(paths);
      if (paths.contains(poison)) throw const IsolateFailed('out of memory');
      return {for (final p in paths) p: tagOf(p)};
    }

    RawAudio file(String path) => RawAudio(path: path, size: 500 * 1024, dateModified: 1);

    setUp(() {
      calls = [];
      scanner = LibraryScanner(
        db: db,
        mediaStore: store,
        folders: _NoFolders(),
        covers: CoverCache(),
        readTags: reader,
      );
    });

    Future<Set<String>> library() async => {for (final t in await db.select(db.tracks).get()) t.path};

    test('every other song still gets in, and the scan finishes', () async {
      store.files = [
        for (var i = 0; i < 30; i++) file('/m/$i.mp3'),
        file(poison),
        for (var i = 30; i < 60; i++) file('/m/$i.mp3'),
      ];

      final result = await scanner.scan();

      expect(result.phase, ScanPhase.done);
      final added = await library();
      expect(added, hasLength(60));
      expect(added, isNot(contains(poison)));
    });

    test('the bad file is not read again until it changes', () async {
      store.files = [file('/m/good.mp3'), file(poison)];
      await scanner.scan();

      calls.clear();
      final second = await scanner.scan();
      expect(second.total, 0);
      expect(calls, isEmpty);

      store.files = [file('/m/good.mp3'), const RawAudio(path: poison, size: 600 * 1024, dateModified: 2)];
      final third = await scanner.scan();
      expect(third.total, 1);
    });

    test('files in healthy batches are read only once', () async {
      store.files = [for (var i = 0; i < 30; i++) file('/m/$i.mp3')];
      await scanner.scan();
      expect(calls.expand((c) => c), hasLength(30));
    });
  });

  test('a rejected file is read again once it changes', () async {
    store.files = [a, b];
    await scanner.scan();

    // e.g. the download finished → the size changed
    store.files = [a, const RawAudio(path: '/nope/voice-note-2.ogg', size: 400 * 1024, dateModified: 3000)];
    final next = await scanner.scan();
    expect(next.total, 1);
  });

  group('artist fixes', () {
    // Tracks already in the DB and unchanged on disk → the scan only runs the artist pass
    Future<void> seed(List<(String, String, String)> rows) async {
      await db
          .into(db.scanState)
          .insert(const ScanStateCompanion(key: Value('tagReaderVersion'), value: Value('$kTagReaderVersion')));
      store.files = [for (final (i, _) in rows.indexed) RawAudio(path: '/m/$i.mp3', size: 1000, dateModified: i)];
      for (final (i, (artist, title, _)) in rows.indexed) {
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                path: '/m/$i.mp3',
                title: title,
                artist: artist,
                album: 'A',
                format: 'mp3',
                fileSize: const Value(1000),
                dateAdded: i,
                dateModified: i,
              ),
            );
      }
    }

    Future<List<(String, String)>> rows() async => [
      for (final t in await (db.select(db.tracks)..orderBy([(t) => OrderingTerm(expression: t.id)])).get())
        (t.artist, t.title),
    ];

    test('channel artist → artist from the title, remembered for new uploads', () async {
      await seed([
        ('Synaps Records', 'Paster — Bane', ''),
        ('Synaps Records', 'RIO — Təkərlər (Official Music Video)', ''),
        ('Ezhel', 'Felaket', ''),
      ]);
      await scanner.scan();
      expect(await rows(), [('Paster', 'Bane'), ('RIO', 'Təkərlər'), ('Ezhel', 'Felaket')]);

      // a later single download from the same channel
      store.files = [...store.files, const RawAudio(path: '/m/9.mp3', size: 1000, dateModified: 9)];
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              path: '/m/9.mp3',
              title: 'DREK — PAPA (audio)',
              artist: 'Synaps Records',
              album: 'A',
              format: 'mp3',
              fileSize: const Value(1000),
              dateAdded: 9,
              dateModified: 9,
            ),
          );
      await scanner.scan();
      expect((await rows()).last, ('DREK', 'PAPA'));
    });

    test('Edit artist survives rescans', () async {
      await seed([('101 Moon Ave.', 'Lofi Night Drive', '')]);
      final repo = LibraryRepositoryImpl(db, TrackMapper(CoverCache()));
      final id = (await db.select(db.tracks).getSingle()).id;
      await repo.setArtist(id, 'Moon Lofi');
      // the tag is read again (file changed) → the tag artist comes back, then the edit wins
      await (db.update(db.tracks)).write(const TracksCompanion(artist: Value('101 Moon Ave.')));
      await scanner.scan();
      expect(await rows(), [('Moon Lofi', 'Lofi Night Drive')]);
    });

    test('a name restored from a backup reaches a song scanned later', () async {
      await BackupService(db).restore(jsonEncode({
        'format': BackupService.format,
        'artistOverrides': [{'path': '/m/0.mp3', 'artist': 'Moon Lofi'}],
      }));
      await seed([('101 Moon Ave.', 'Lofi Night Drive', '')]);
      await scanner.scan();
      expect(await rows(), [('Moon Lofi', 'Lofi Night Drive')]);
    });

    test('broken saved names do not stop the scan', () async {
      await seed([('Ezhel', 'Felaket', '')]);
      await db.into(db.scanState).insert(
            ScanStateCompanion.insert(key: SettingsKeys.artistOverrides, value: '{"/m/0.mp3":5}'),
          );
      final result = await scanner.scan();
      expect(result.phase, ScanPhase.done);
      expect(await rows(), [('Ezhel', 'Felaket')]);
    });
  });

  group('songs that are not listed', () {
    late Set<String> onDisk;
    late bool coversFail;

    TagInfo tagOf(String path) => TagInfo(
          title: path.split('/').last,
          artist: 'A',
          album: 'B',
          durationMs: 100000,
          format: AudioFormat.mp3,
          cover: Uint8List.fromList([1, 2, 3]),
        );

    RawAudio file(String path) => RawAudio(path: path, size: 500 * 1024, dateModified: 1);

    setUp(() {
      onDisk = {};
      coversFail = false;
      scanner = LibraryScanner(
        db: db,
        mediaStore: store,
        folders: _NoFolders(),
        covers: _Covers(() => coversFail),
        readTags: (paths) async => {for (final p in paths) p: tagOf(p)},
        fileExists: (path) async => onDisk.contains(path),
      );
    });

    Future<Set<String>> visible() async =>
        {for (final t in await (db.select(db.tracks)..where((t) => t.isMissing.not())).get()) t.path};

    // After a system update MediaStore rebuilds its index and answers with nothing for a while
    test('an empty MediaStore answer hides nothing that is still on disk', () async {
      final songs = [for (var i = 0; i < 5; i++) '/m/$i.mp3'];
      store.files = [for (final s in songs) file(s)];
      onDisk = songs.toSet();
      await scanner.scan();

      store.files = [];
      final result = await scanner.scan();

      expect(result.phase, ScanPhase.done);
      expect(await visible(), songs.toSet());
    });

    test('a song whose file is really gone is still hidden', () async {
      store.files = [file('/m/kept.mp3'), file('/m/deleted.mp3')];
      onDisk = {'/m/kept.mp3', '/m/deleted.mp3'};
      await scanner.scan();

      store.files = [file('/m/kept.mp3')];
      onDisk = {'/m/kept.mp3'};
      await scanner.scan();

      expect(await visible(), {'/m/kept.mp3'});
    });

    // A full disk: before, the first cover that couldn't be written stopped the whole scan
    test('a cover that cannot be saved does not stop the scan', () async {
      coversFail = true;
      store.files = [file('/m/a.mp3'), file('/m/b.mp3')];

      final result = await scanner.scan();

      expect(result.phase, ScanPhase.done);
      final rows = await db.select(db.tracks).get();
      expect(rows.map((t) => t.path).toSet(), {'/m/a.mp3', '/m/b.mp3'});
      expect(rows.map((t) => t.coverHash), everyElement(isNull));
    });
  });

  // Returning to the app rescanned everything every time: ~0.4 s of the UI thread for 725 songs
  group('a scan is needed only when something changed', () {
    late Directory music;

    setUp(() async {
      music = Directory.systemTemp.createTempSync('nocturne_music');
      await db.delete(db.scanFolders).go();
      await db.into(db.scanFolders).insert(ScanFoldersCompanion.insert(path: music.path));
      scanner = LibraryScanner(db: db, mediaStore: store, folders: FolderSource(), covers: CoverCache());
    });
    tearDown(() => music.deleteSync(recursive: true));

    test('nothing changed: no scan', () async {
      Directory('${music.path}/Album').createSync();
      await scanner.scan();
      expect(await scanner.changedSinceLastScan(), isFalse);
    });

    test('before the first scan nobody knows', () async {
      expect(await scanner.changedSinceLastScan(), isTrue);
    });

    test('the media index changed', () async {
      await scanner.scan();
      store.counter = 'v1;external_primary=6';
      expect(await scanner.changedSinceLastScan(), isTrue);
    });

    test('a phone without the counter (Android 10) always scans', () async {
      store.counter = null;
      await scanner.scan();
      expect(await scanner.changedSinceLastScan(), isTrue);
    });

    test('a file landed in a subfolder MediaStore was not told about', () async {
      final album = Directory('${music.path}/Album')..createSync();
      await scanner.scan();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      File('${album.path}/new.mp3').writeAsBytesSync([1, 2, 3]);
      expect(await scanner.changedSinceLastScan(), isTrue);
    });

    test('a scan folder was added', () async {
      await scanner.scan();
      await db.into(db.scanFolders).insert(ScanFoldersCompanion.insert(path: '/elsewhere'));
      expect(await scanner.changedSinceLastScan(), isTrue);
    });

    test('after a failed scan the next return scans again', () async {
      await scanner.scan();
      store.broken = true;
      expect((await scanner.scan()).phase, ScanPhase.error);
      store.broken = false;
      expect(await scanner.changedSinceLastScan(), isTrue);
    });
  });

  test('a scan that changes nothing writes nothing to scan state but the time', () async {
    await scanner.scan();
    final writes = <Set<TableUpdate>>[];
    final sub = db.tableUpdates().listen(writes.add);
    await scanner.scan();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(writes, hasLength(1)); // lastScanAt + reader version + skipped list, one batch
  });

  // A moved or renamed file became a new song: the favorite, playlists, history, analysis and
  // lyrics stayed on the vanished one
  group('a moved song keeps what it had', () {
    late Set<String> onDisk;
    late Map<String, String> titles;

    setUp(() {
      onDisk = {};
      titles = {};
      scanner = LibraryScanner(
        db: db,
        mediaStore: store,
        folders: _NoFolders(),
        covers: CoverCache(),
        readTags: (paths) async => {
          for (final p in paths)
            p: TagInfo(title: titles[p] ?? 'Song', artist: 'A', album: 'B', durationMs: 200000, format: AudioFormat.mp3),
        },
        fileExists: (path) async => onDisk.contains(path),
      );
    });

    Future<void> at(List<String> paths, {int size = 5000000}) async {
      store.files = [for (final p in paths) RawAudio(path: p, size: size, dateModified: 1)];
      onDisk = paths.toSet();
      await scanner.scan();
    }

    Future<int> idOf(String path) async =>
        (await (db.select(db.tracks)..where((t) => t.path.equals(path))).getSingle()).id;

    Future<int> favoriteAndPlay(String path) async {
      final id = await idOf(path);
      await db.into(db.favorites).insert(FavoritesCompanion.insert(trackId: Value(id), addedAt: 1));
      await db.into(db.playHistory).insert(PlayHistoryCompanion.insert(trackId: id, playedAt: 1));
      return id;
    }

    test('moved to another folder', () async {
      await at(['/m/Download/song.mp3']);
      final id = await favoriteAndPlay('/m/Download/song.mp3');

      await at(['/m/Music/song.mp3']);

      final rows = await db.select(db.tracks).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, id);
      expect(rows.single.path, '/m/Music/song.mp3');
      expect(rows.single.isMissing, isFalse);
      expect(await db.select(db.favorites).get(), hasLength(1));
      expect(await db.select(db.playHistory).get(), hasLength(1));
    });

    test('renamed: same song, other file name', () async {
      titles = {'/m/a.mp3': 'Night', '/m/Night - A.mp3': 'Night'};
      await at(['/m/a.mp3']);
      final id = await favoriteAndPlay('/m/a.mp3');

      await at(['/m/Night - A.mp3']);
      expect(await idOf('/m/Night - A.mp3'), id);
    });

    test('moved while the app was closed, after a scan had already marked it missing', () async {
      await at(['/m/Download/song.mp3']);
      final id = await favoriteAndPlay('/m/Download/song.mp3');
      await at([]);
      expect((await db.select(db.tracks).getSingle()).isMissing, isTrue);

      await at(['/sd/Music/song.mp3']);
      expect(await idOf('/sd/Music/song.mp3'), id);
      expect((await db.select(db.tracks).getSingle()).isMissing, isFalse);
    });

    test('an edited artist name goes along', () async {
      await at(['/m/Download/song.mp3']);
      await db.into(db.scanState).insertOnConflictUpdate(ArtistOverrides.row({'/m/Download/song.mp3': 'Mine'}));
      await at(['/m/Download/song.mp3']); // the name is applied

      await at(['/m/Music/song.mp3']);
      expect((await db.select(db.tracks).getSingle()).artist, 'Mine');
    });

    test('a different song of the same size is a new song', () async {
      titles = {'/m/a.mp3': 'One', '/m/b.mp3': 'Two'};
      await at(['/m/a.mp3']);
      final id = await favoriteAndPlay('/m/a.mp3');

      await at(['/m/b.mp3']);
      expect(await idOf('/m/b.mp3'), isNot(id));
    });

    test('two equal copies gone at once can\'t be told apart: no guess', () async {
      await at(['/m/1/song.mp3', '/m/2/song.mp3']);
      await at(['/m/3/song.mp3']);
      final rows = await db.select(db.tracks).get();
      expect(rows, hasLength(3));
      expect(rows.where((r) => !r.isMissing).single.path, '/m/3/song.mp3');
    });

    test('a copy whose original is still there is a new song', () async {
      await at(['/m/a/song.mp3']);
      await at(['/m/a/song.mp3', '/m/b/song.mp3']);
      expect(await db.select(db.tracks).get(), hasLength(2));
    });
  });

  // The covers folder only ever grew: re-tagged and deleted songs left their pictures behind
  test('covers no song uses any more are removed, the rest stay', () async {
    final dir = Directory.systemTemp.createTempSync('nocturne_covers');
    addTearDown(() => dir.deleteSync(recursive: true));
    var coverOfB = Uint8List.fromList([2, 2, 2]);
    TagInfo tagOf(String path) {
      final cover = path.endsWith('a.mp3') ? Uint8List.fromList([1, 1, 1]) : coverOfB;
      return TagInfo(
        title: path,
        artist: 'A',
        album: 'B',
        durationMs: 100000,
        format: AudioFormat.mp3,
        cover: cover,
        coverHash: coverHashOf(cover),
      );
    }

    scanner = LibraryScanner(
      db: db,
      mediaStore: store,
      folders: _NoFolders(),
      covers: _CoversIn(dir),
      readTags: (paths) async => {for (final p in paths) p: tagOf(p)},
    );
    store.files = [
      const RawAudio(path: '/m/a.mp3', size: 1, dateModified: 1),
      const RawAudio(path: '/m/b.mp3', size: 1, dateModified: 1),
    ];
    await scanner.scan();
    final oldB = coverHashOf(coverOfB);
    expect(dir.listSync(), hasLength(2));

    // b gets a new picture
    coverOfB = Uint8List.fromList([3, 3, 3]);
    store.files = [store.files.first, const RawAudio(path: '/m/b.mp3', size: 1, dateModified: 2)];
    await scanner.scan();

    final names = {for (final f in dir.listSync()) f.uri.pathSegments.last};
    expect(names, {coverHashOf(Uint8List.fromList([1, 1, 1])), coverHashOf(coverOfB)});
    expect(names, isNot(contains(oldB)));
  });

  // What a restore kept waiting is applied once a scan has found the songs
  test('the after-scan step runs after every finished scan, and can\'t fail the scan', () async {
    var runs = 0;
    scanner = LibraryScanner(
      db: db,
      mediaStore: store,
      folders: _NoFolders(),
      covers: CoverCache(),
      afterScan: () async {
        runs++;
        throw StateError('database busy');
      },
    );
    expect((await scanner.scan()).phase, ScanPhase.done);
    expect((await scanner.scan()).phase, ScanPhase.done);
    expect(runs, 2);
  });

  test('the cover is stored under the name the reading isolate worked out', () async {
    final covers = _Covers(() => false);
    scanner = LibraryScanner(
      db: db,
      mediaStore: store,
      folders: _NoFolders(),
      covers: covers,
      readTags: (paths) async => {
        for (final p in paths)
          p: TagInfo(
            title: 't',
            artist: 'A',
            album: 'B',
            durationMs: 100000,
            format: AudioFormat.mp3,
            cover: Uint8List.fromList([1, 2, 3]),
            coverHash: 'from-isolate',
          ),
      },
    );
    store.files = [const RawAudio(path: '/m/a.mp3', size: 1, dateModified: 1)];
    await scanner.scan();
    expect(covers.given, ['from-isolate']);
    expect((await db.select(db.tracks).getSingle()).coverHash, 'from-isolate');
  });

  test('skip signature uses size and modified time', () {
    expect(skipSignature(a), '${200 * 1024}:1000');
  });
}
