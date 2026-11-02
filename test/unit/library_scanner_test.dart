import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/cover_cache.dart';
import 'package:sonar/data/datasources/folder_source.dart';
import 'package:sonar/data/datasources/media_store_source.dart';
import 'package:sonar/data/datasources/raw_audio.dart';
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
