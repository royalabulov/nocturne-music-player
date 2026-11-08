import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/utils/shared_storage.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/repositories/device_files.dart';
import 'package:nocturne/features/import/audio_import.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';

/// Another app's provider: it answers late, or not at all.
class _Files implements DeviceFiles {
  _Files({this.resolveHangs = const {}, this.importHangs = const {}});
  final Set<String> resolveHangs, importHangs;

  @override
  Future<({String? path, String name, int size})> resolveAudio(String source) async {
    if (resolveHangs.contains(source)) await Completer<void>().future;
    return (path: null, name: '$source.mp3', size: 100);
  }

  @override
  Future<String> importAudio(String source) async {
    if (importHangs.contains(source)) await Completer<void>().future;
    throw const FormatException('nothing to copy in this test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('a provider that never answers', () {
    late AppDatabase db;
    const fast = Duration(milliseconds: 20);

    AudioImport importer(_Files files) {
      final impl = Provider<AudioImport>((ref) => AudioImport(ref, resolveTimeout: fast, importTimeout: fast));
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        deviceFilesProvider.overrideWithValue(files),
      ]);
      addTearDown(c.dispose);
      return c.read(impl);
    }

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('asking about the file: it counts as failed, and the call comes back', () async {
      final r = await importer(_Files(resolveHangs: {'stuck'})).ingest(['stuck']);
      expect(r.failed, 1);
      expect(r.tracks, isEmpty);
    });

    test('copying the file: the same', () async {
      final r = await importer(_Files(importHangs: {'stuck'})).ingest(['stuck']);
      expect(r.failed, 1);
    });

    test('the other files are still handled', () async {
      final r = await importer(_Files(resolveHangs: {'stuck'})).ingest(['stuck', 'next']);
      expect(r.failed, 2); // "next" reached the copy, which this fake refuses
    });

    test('the waits are long enough for real work', () {
      final real = Provider<AudioImport>(AudioImport.new);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(real).resolveTimeout, greaterThanOrEqualTo(const Duration(seconds: 10)));
      expect(c.read(real).importTimeout, greaterThanOrEqualTo(const Duration(minutes: 10)));
    });
  });

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
