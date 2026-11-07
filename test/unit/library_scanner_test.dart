import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/cover_cache.dart';
import 'package:sonar/data/datasources/folder_source.dart';
import 'package:sonar/data/datasources/media_store_source.dart';
import 'package:sonar/data/datasources/raw_audio.dart';
import 'package:sonar/data/datasources/tag_reader.dart';
import 'package:sonar/core/utils/bounded_isolate.dart';
import 'package:sonar/domain/entities/audio_format.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/services/library_scanner.dart';
import 'package:sonar/data/mappers/track_mapper.dart';
import 'package:sonar/data/repositories/library_repository_impl.dart';
import 'package:sonar/core/constants.dart';

class _FakeStore extends MediaStoreSource {
  List<RawAudio> files = [];
  @override
  Future<List<RawAudio>> enumerate() async => files;
  @override
  Future<void> notify(List<String> paths) async {}
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
  });

  test('skip signature uses size and modified time', () {
    expect(skipSignature(a), '${200 * 1024}:1000');
  });
}
