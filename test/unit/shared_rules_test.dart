import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/utils/shared_storage.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/datasources/folder_source.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';
import 'package:nocturne/data/repositories/lyrics_repository_impl.dart';
import 'package:nocturne/data/repositories/settings_repository_impl.dart';
import 'package:nocturne/data/repositories/track_filter_sql.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/repositories/library_repository.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';

/// Rules that used to be written several times, and could quietly drift apart.
void main() {
  group('shared storage', () {
    test('another app\'s private folders are out, including obb', () {
      expect(isSharedStoragePath('/storage/emulated/0/Music'), isTrue);
      expect(isSharedStoragePath('/storage/emulated/0/Android/data/com.x/a.mp3'), isFalse);
      expect(isSharedStoragePath('/storage/emulated/0/Android/obb/com.x/a.mp3'), isFalse);
      expect(isSharedStoragePath('/storage/emulated/0/../../data/a.mp3'), isFalse);
      expect(isSharedStoragePath('/data/user/0/com.nocturne'), isFalse);
    });
  });

  group('first artist for a lyrics search', () {
    test('every way of naming a guest ends at the main artist', () {
      expect(LyricsRepositoryImpl.firstArtist('A (feat. B)'), 'A');
      expect(LyricsRepositoryImpl.firstArtist('A featuring B'), 'A');
      expect(LyricsRepositoryImpl.firstArtist('A ft B'), 'A');
    });

    test('a name that only looks like a list stays whole', () {
      expect(LyricsRepositoryImpl.firstArtist('Tyler, The Creator'), 'Tyler, The Creator');
    });
  });

  group('audio file types', () {
    Set<String> kotlinList() {
      final source = File('android/app/src/main/kotlin/com/nocturne/AudioImporter.kt').readAsStringSync();
      final list = RegExp(r'AUDIO_EXTENSIONS = setOf\(([^)]*)\)').firstMatch(source)![1]!;
      return {for (final m in RegExp('"([^"]+)"').allMatches(list)) m[1]!};
    }

    // The two lists differ on purpose: an incoming file is checked by its content too, so the
    // importer also takes mp4 or webm, while a folder walk has only the name to go on.
    test('whatever a folder scan finds can also be opened from another app', () {
      final scanned = {for (final e in FolderSource.audioExtensions) e.substring(1)};
      expect(kotlinList(), containsAll(scanned));
    });

    test('every format with a name of its own can be found by a folder scan', () {
      for (final f in AudioFormat.values) {
        if (f == AudioFormat.unknown || f == AudioFormat.alac) continue; // ALAC is in .m4a
        expect(FolderSource.audioExtensions, contains('.${f.name}'), reason: f.name);
      }
    });
  });

  group('visible tracks', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      Future<void> add(String name, {required int bytes, required int ms, String format = 'mp3', bool missing = false}) =>
          db.into(db.tracks).insert(TracksCompanion.insert(
                path: '/m/$name.$format',
                title: name,
                artist: 'A',
                album: 'B',
                format: format,
                durationMs: Value(ms),
                fileSize: Value(bytes),
                isMissing: Value(missing),
                dateAdded: 1,
                dateModified: 1,
              ));
      await add('small', bytes: 1000, ms: 200000);
      await add('short', bytes: 500000, ms: 1000);
      await add('song', bytes: 500000, ms: 200000);
      await add('big', bytes: 900000, ms: 200000, format: 'flac');
      await add('long', bytes: 500000, ms: 900000, format: 'wav');
      await add('gone', bytes: 500000, ms: 200000, missing: true);
    });
    tearDown(() => db.close());

    LibraryRepositoryImpl repo(TrackFilter f) => LibraryRepositoryImpl(db, TrackMapper(CoverCache()), filter: f);

    Future<Set<String>> shown(TrackFilter f) async => {for (final t in await repo(f).watchTracks().first) t.title};

    /// The same rule through the SQL the history and analysis screens use.
    Future<Set<String>> viaSql(TrackFilter f) async {
      final rows = await db.customSelect('SELECT t.title FROM tracks t WHERE ${f.sqlOn('t')}').get();
      return {for (final r in rows) r.read<String>('title')};
    }

    final filters = <String, (TrackFilter, Set<String>)>{
      'defaults': (TrackFilter.defaults, {'song', 'big', 'long'}),
      'max size': (const TrackFilter(maxBytes: 600000), {'song', 'long'}),
      'max length': (const TrackFilter(maxMs: 300000), {'song', 'big'}),
      'no lower limit': (const TrackFilter(minBytes: 0, minMs: 0), {'small', 'short', 'song', 'big', 'long'}),
    };

    for (final MapEntry(key: name, value: (filter, expected)) in filters.entries) {
      test('$name: lists and SQL agree', () async {
        expect(await shown(filter), expected);
        expect(await viaSql(filter), expected);
      });
    }

    test('stats count only what is visible, and only real lossless as lossless', () async {
      final stats = await repo(TrackFilter.defaults).watchStats().first;
      expect(stats.trackCount, 3);
      expect(stats.losslessCount, 2);
      expect(stats.totalDuration, const Duration(milliseconds: 1300000));
    });
  });

  group('EnumSetting', () {
    NotifierProvider<EnumSetting<TrackSort>, TrackSort> provider() =>
        NotifierProvider(() => EnumSetting(SettingsKeys.librarySort, TrackSort.values, TrackSort.title));

    late DemoSettingsRepository repo;
    late ProviderContainer c;
    setUp(() {
      repo = DemoSettingsRepository();
      c = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
    });

    test('never chosen → the default', () async {
      final p = provider();
      c.listen(p, (_, _) {});
      await pumpEventQueue();
      expect(c.read(p), TrackSort.title);
    });

    test('a choice survives a restart', () async {
      final p = provider();
      c.listen(p, (_, _) {});
      await c.read(p.notifier).set(TrackSort.album);
      expect(await repo.getSetting(SettingsKeys.librarySort), 'album');

      final next = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(next.dispose);
      next.listen(p, (_, _) {});
      await pumpEventQueue();
      expect(next.read(p), TrackSort.album);
    });

    test('a restored backup shows at once on a screen that is open', () async {
      final p = provider();
      c.listen(p, (_, _) {});
      await pumpEventQueue();
      await repo.setSetting(SettingsKeys.librarySort, 'longest');
      await pumpEventQueue();
      expect(c.read(p), TrackSort.longest);
    });

    test('a value this version does not know keeps the current choice', () async {
      await repo.setSetting(SettingsKeys.librarySort, 'something-new');
      final p = provider();
      c.listen(p, (_, _) {});
      await pumpEventQueue();
      expect(c.read(p), TrackSort.title);
    });

    test('with the real database too', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final real = ProviderContainer(overrides: [settingsRepositoryProvider.overrideWithValue(SettingsRepositoryImpl(db))]);
      addTearDown(real.dispose);
      final p = provider();
      real.listen(p, (_, _) {});
      await real.read(p.notifier).set(TrackSort.shortest);
      await pumpEventQueue();
      expect(real.read(p), TrackSort.shortest);
    });
  });
}
