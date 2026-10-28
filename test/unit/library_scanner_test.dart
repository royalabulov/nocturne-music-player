import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/cover_cache.dart';
import 'package:sonar/data/datasources/folder_source.dart';
import 'package:sonar/data/datasources/media_store_source.dart';
import 'package:sonar/data/datasources/raw_audio.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/services/library_scanner.dart';

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

  test('skip signature uses size and modified time', () {
    expect(skipSignature(a), '${200 * 1024}:1000');
  });
}
