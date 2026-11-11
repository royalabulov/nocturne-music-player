import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/nocturne_audio_handler.dart';
import 'package:nocturne/core/audio/player_providers.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/domain/entities/scan_progress.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/device_files.dart';
import 'package:nocturne/features/import/audio_import.dart';
import 'package:nocturne/features/library_scan/permission_gate.dart';
import 'package:nocturne/features/library_scan/scan_controller.dart';

/// "Open with Nocturne", Share and "Import files" when things work: a file the library
/// already has is not copied again, a file on the phone is used in place, only another
/// app's private file is copied — and the songs come back in the order they were sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _Files files;
  late _Handler handler;
  late _Scan scan;
  late ProviderContainer c;
  AudioImport importer() => c.read(audioImportProvider);

  const music = '/storage/emulated/0/Music';

  Future<int> addTrack(String path, {int size = 100}) => db.into(db.tracks).insert(TracksCompanion.insert(
        path: path,
        title: path.split('/').last,
        artist: 'A',
        album: 'B',
        format: 'mp3',
        fileSize: Value(size),
        dateAdded: 1,
        dateModified: 1,
      ));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    files = _Files();
    handler = _Handler();
    scan = _Scan(addTrack);
    c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceFilesProvider.overrideWithValue(files),
      audioHandlerProvider.overrideWithValue(handler),
      scanControllerProvider.overrideWith(() => scan),
    ]);
  });

  tearDown(() async {
    await pumpEventQueue(); // the library filter loads its setting in the background
    c.dispose();
    await db.close();
  });

  group('ingest', () {
    test('a song the library already has: no copy, no scan', () async {
      await addTrack('$music/a.mp3');
      files.known['a'] = (path: '$music/a.mp3', name: 'a.mp3', size: 100);

      final r = await importer().ingest(['a']);

      expect(r.tracks.map((t) => t.path), ['$music/a.mp3']);
      expect(r.copied, 0);
      expect(r.failed, 0);
      expect(files.copies, isEmpty);
      expect(scan.scans, 0);
    });

    test('a messenger\'s copy of a song the library has (same name and size): not copied again', () async {
      await addTrack('$music/a.mp3', size: 4242);
      files.known['content://chat/1'] = (path: null, name: 'a.mp3', size: 4242);

      final r = await importer().ingest(['content://chat/1']);

      expect(r.tracks.map((t) => t.path), ['$music/a.mp3']);
      expect(files.copies, isEmpty);
    });

    test('a file elsewhere on the phone is used in place: scanned, not copied', () async {
      files.known['d'] = (path: '/storage/emulated/0/Download/d.mp3', name: 'd.mp3', size: 100);
      scan.finds.add('/storage/emulated/0/Download/d.mp3');

      final r = await importer().ingest(['d']);

      expect(r.tracks.map((t) => t.path), ['/storage/emulated/0/Download/d.mp3']);
      expect(r.copied, 0);
      expect(files.copies, isEmpty);
      expect(files.scanned, ['/storage/emulated/0/Download/d.mp3']);
    });

    test("another app's private file is copied to Music/Nocturne first", () async {
      files.known['content://chat/2'] = (path: '/data/user/0/com.chat/files/v.mp3', name: 'v.mp3', size: 100);
      scan.finds.add('$music/Nocturne/v.mp3');

      final r = await importer().ingest(['content://chat/2']);

      expect(files.copies, ['content://chat/2']);
      expect(r.copied, 1);
      expect(r.tracks.map((t) => t.path), ['$music/Nocturne/v.mp3']);
    });

    test('a scan already running may miss the new file: a second scan finds it', () async {
      files.known['d'] = (path: '$music/new.mp3', name: 'new.mp3', size: 100);
      scan.finds.add('$music/new.mp3');
      scan.missFirst = true;

      final r = await importer().ingest(['d']);

      expect(scan.scans, 2);
      expect(r.tracks, hasLength(1));
      expect(r.failed, 0);
    });

    test('a file no scan takes (corrupt, too short) counts as failed, not as added', () async {
      files.known['bad'] = (path: '$music/bad.mp3', name: 'bad.mp3', size: 100);

      final r = await importer().ingest(['bad']);

      expect(r.tracks, isEmpty);
      expect(r.failed, 1);
    });

    test('the songs come back in the order they were sent', () async {
      await addTrack('$music/known.mp3');
      files.known['new'] = (path: '$music/new.mp3', name: 'new.mp3', size: 100);
      files.known['known'] = (path: '$music/known.mp3', name: 'known.mp3', size: 100);
      scan.finds.add('$music/new.mp3');

      final r = await importer().ingest(['new', 'known']);

      expect(r.tracks.map((t) => t.path), ['$music/new.mp3', '$music/known.mp3']);
    });
  });

  group('handleOpened', () {
    test('the opened songs play', () async {
      await addTrack('$music/a.mp3');
      files.known['a'] = (path: '$music/a.mp3', name: 'a.mp3', size: 100);
      files.opened.add(['a']);

      await importer().handleOpened();

      expect(handler.played, [
        ['$music/a.mp3'],
      ]);
    });

    test('a file sent while the first is still being opened is played after it, not lost', () async {
      await addTrack('$music/a.mp3');
      await addTrack('$music/b.mp3');
      files.known['a'] = (path: '$music/a.mp3', name: 'a.mp3', size: 100);
      files.known['b'] = (path: '$music/b.mp3', name: 'b.mp3', size: 100);
      files.opened.add(['a']);
      files.gate = Completer<void>();

      final first = importer().handleOpened(); // waits inside, on the slow provider
      await pumpEventQueue();
      files.opened.add(['b']);
      await importer().handleOpened(); // busy: only remembered
      files.gate!.complete();
      await first;
      await pumpEventQueue();

      expect(handler.played, [
        ['$music/a.mp3'],
        ['$music/b.mp3'],
      ]);
    });

    test('nothing could be opened: nothing plays (an error toast instead)', () async {
      files.opened.add(['gone']); // resolveAudio throws for unknown sources

      await importer().handleOpened();

      expect(handler.played, isEmpty);
    });
  });
}

class _Files implements DeviceFiles {
  final known = <String, ({String? path, String name, int size})>{};
  final opened = <List<String>>[];
  final copies = <String>[];
  final scanned = <String>[];
  Completer<void>? gate;

  @override
  Future<({String? path, String name, int size})> resolveAudio(String source) async {
    await gate?.future;
    return known[source] ?? (throw StateError('no such file: $source'));
  }

  @override
  Future<String> importAudio(String source) async {
    copies.add(source);
    return '/storage/emulated/0/Music/Nocturne/${known[source]!.name}';
  }

  @override
  Future<void> scanAndWait(List<String> paths) async => scanned.addAll(paths);

  @override
  Future<List<String>> takeOpenedUris() async => opened.isEmpty ? const [] : opened.removeAt(0);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The library scan: adds the files in [finds] to the library (the second time only,
/// with [missFirst]).
class _Scan extends ScanController {
  _Scan(this._add);
  final Future<int> Function(String path) _add;
  final finds = <String>{};
  bool missFirst = false;
  int scans = 0;

  @override
  LibraryScanState build() =>
      const LibraryScanState(permission: MediaPermission.granted, progress: ScanProgress.idle);

  @override
  Future<void> requestAndScan() async {
    scans++;
    if (missFirst && scans == 1) return;
    for (final p in finds) {
      await _add(p);
    }
    finds.clear();
  }
}

class _Handler implements NocturneAudioHandler {
  final played = <List<String>>[];

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) async =>
      played.add([for (final t in tracks) t.path]);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
