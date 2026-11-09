import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';

/// The stored play queue is read back by id; it can hold thousands of songs.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  Future<int> add(int n, {bool missing = false}) => db.into(db.tracks).insert(TracksCompanion.insert(
        path: '/storage/emulated/0/Music/$n.mp3',
        title: 'Song $n',
        artist: 'A',
        album: 'B',
        format: 'mp3',
        durationMs: const Value(200000),
        fileSize: const Value(5000000),
        dateAdded: 1,
        dateModified: 1,
        isMissing: Value(missing),
      ));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(db, TrackMapper(CoverCache()));
  });
  tearDown(() => db.close());

  test('a queue longer than one query may hold comes back whole', () async {
    final ids = <int>[];
    await db.transaction(() async {
      for (var i = 0; i < 1200; i++) {
        ids.add(await add(i));
      }
    });
    final found = await repo.getTracks(ids);
    expect(found.map((t) => t.id).toSet(), ids.toSet());
  });

  test('songs gone from the library or from disk are left out', () async {
    final kept = await add(1);
    final gone = await add(2, missing: true);
    final found = await repo.getTracks([kept, gone, 999]);
    expect(found.map((t) => t.id), [kept]);
  });
}
