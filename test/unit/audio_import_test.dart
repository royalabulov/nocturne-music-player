import 'package:nocturne/core/utils/shared_storage.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';

void main() {
  group('which files are used in place instead of being copied', () {
    test('a song on shared storage', () {
      expect(isSharedStoragePath('/storage/emulated/0/Music/song.mp3'), isTrue);
      expect(isSharedStoragePath('/storage/1234-ABCD/Music/song.mp3'), isTrue);
    });

    test('not app-private folders', () {
      expect(isSharedStoragePath('/data/user/0/com.nocturne/cache/song.mp3'), isFalse);
      expect(isSharedStoragePath('/storage/emulated/0/Android/data/com.other/cache/song.mp3'), isFalse);
    });

    test('not a path that only looks public', () {
      expect(isSharedStoragePath('/storage/emulated/0/../../../data/user/0/com.nocturne/databases/x'), isFalse);
      expect(isSharedStoragePath('/storage/emulated/0/Music/../secret.mp3'), isFalse);
    });
  });

  group('finding a file already in the library by name and size', () {
    late AppDatabase db;
    late LibraryRepositoryImpl repo;

    Future<void> add(String path, int size) => db.into(db.tracks).insert(TracksCompanion.insert(
          path: path,
          title: 'T',
          artist: 'A',
          album: 'B',
          format: 'mp3',
          fileSize: Value(size),
          dateAdded: 1,
          dateModified: 1,
        ));

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = LibraryRepositoryImpl(db, TrackMapper(CoverCache()));
    });
    tearDown(() => db.close());

    test('finds the same name and size', () async {
      await add('/storage/emulated/0/Music/a_b.mp3', 100);
      expect((await repo.findTrackByFile('a_b.mp3', 100))?.path, '/storage/emulated/0/Music/a_b.mp3');
    });

    test('another size is another file', () async {
      await add('/storage/emulated/0/Music/song.mp3', 100);
      expect(await repo.findTrackByFile('song.mp3', 200), isNull);
    });

    // The name comes from another app: % and _ must not act as wildcards
    test('an underscore in the name matches only an underscore', () async {
      await add('/storage/emulated/0/Music/axb.mp3', 100);
      expect(await repo.findTrackByFile('a_b.mp3', 100), isNull);
    });

    test('a percent sign in the name matches only a percent sign', () async {
      await add('/storage/emulated/0/Music/secret song.mp3', 100);
      expect(await repo.findTrackByFile('%.mp3', 100), isNull);
      expect(await repo.findTrackByFile('%', 100), isNull);
    });

    test('names with these characters are still found', () async {
      await add('/storage/emulated/0/Music/100%_love.mp3', 100);
      expect(await repo.findTrackByFile('100%_love.mp3', 100), isNotNull);
    });
  });
}
