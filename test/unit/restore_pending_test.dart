import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/services/backup_service.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';

/// Restoring right after a reinstall, before the first scan had found anything, dropped every
/// favorite, playlist entry and play for good: the report only counted them as "not found".
void main() {
  late AppDatabase source, phone;
  late BackupService backup;

  Future<int> song(AppDatabase db, String path) => db.into(db.tracks).insert(TracksCompanion.insert(
        path: path,
        title: path,
        artist: 'A',
        album: 'B',
        format: 'mp3',
        dateAdded: 1,
        dateModified: 1,
      ));

  /// A backup holding [paths] as favorites, each played once, all in the playlist "Mix".
  Future<String> backupOf(List<String> paths) async {
    final pl = await source.into(source.playlists).insert(PlaylistsCompanion.insert(name: 'Mix', createdAt: 1, updatedAt: 1));
    var pos = 0;
    for (final p in paths) {
      final id = await song(source, p);
      await source.into(source.favorites).insert(FavoritesCompanion.insert(trackId: Value(id), addedAt: 1));
      await source.into(source.playHistory).insert(PlayHistoryCompanion.insert(trackId: id, playedAt: 100));
      await source.into(source.playlistTracks).insert(PlaylistTracksCompanion.insert(playlistId: pl, trackId: id, position: pos++));
    }
    return BackupService(source).export();
  }

  setUp(() {
    source = AppDatabase(NativeDatabase.memory());
    phone = AppDatabase(NativeDatabase.memory());
    backup = BackupService(phone);
  });
  tearDown(() async {
    await source.close();
    await phone.close();
  });

  Future<String?> waiting() async =>
      (await (phone.select(phone.scanState)..where((s) => s.key.equals(SettingsKeys.restorePending))).getSingleOrNull())
          ?.value;

  test('songs not found yet wait, and arrive with the scan that finds them', () async {
    final json = await backupOf(['/m/a.mp3', '/m/b.mp3']);
    final report = await backup.restore(json); // nothing scanned yet
    expect(report.favorites, 0);
    expect(report.missingTracks, 2);
    expect(await waiting(), isNotNull);

    await song(phone, '/m/a.mp3'); // the first scan found one of them
    expect(await backup.applyPending(), 1);
    expect(await phone.select(phone.favorites).get(), hasLength(1));
    expect(await phone.select(phone.playHistory).get(), hasLength(1));
    expect(await phone.select(phone.playlistTracks).get(), hasLength(1));

    await song(phone, '/m/b.mp3');
    expect(await backup.applyPending(), 1);
    expect(await phone.select(phone.favorites).get(), hasLength(2));
    expect(await phone.select(phone.playHistory).get(), hasLength(2));
    final order = await (phone.select(phone.playlistTracks)..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
    expect(order.map((r) => r.position), [0, 1]);
    expect(await waiting(), isNull, reason: 'nothing left waiting');
  });

  test('applying twice adds nothing twice', () async {
    final json = await backupOf(['/m/a.mp3']);
    await backup.restore(json);
    await song(phone, '/m/a.mp3');
    await backup.applyPending();
    await backup.restore(json); // restored again, the song is there now
    await backup.applyPending();
    expect(await phone.select(phone.favorites).get(), hasLength(1));
    expect(await phone.select(phone.playHistory).get(), hasLength(1));
  });

  test('another SD card: the same folder and file name under another root still find the song', () async {
    final json = await backupOf(['/storage/1111-2222/Music/Album/song.mp3']);
    await song(phone, '/storage/3333-4444/Music/Album/song.mp3');
    final report = await backup.restore(json);
    expect(report.favorites, 1);
    expect(report.missingTracks, 0);
  });

  test('two songs with that folder and name: no guess, it waits', () async {
    final json = await backupOf(['/storage/1111-2222/Album/song.mp3']);
    await song(phone, '/storage/a/Album/song.mp3');
    await song(phone, '/storage/b/Album/song.mp3');
    final report = await backup.restore(json);
    expect(report.favorites, 0);
    expect(report.missingTracks, 1);
  });

  test('a playlist deleted after the restore isn\'t made again by a late song', () async {
    final json = await backupOf(['/m/a.mp3']);
    await backup.restore(json);
    await phone.delete(phone.playlists).go();
    await song(phone, '/m/a.mp3');
    await backup.applyPending();
    expect(await phone.select(phone.playlists).get(), isEmpty);
    expect(await phone.select(phone.favorites).get(), hasLength(1), reason: 'the rest still arrives');
  });

  test('a broken waiting list is dropped, not a crash', () async {
    await phone.into(phone.scanState).insert(ScanStateCompanion.insert(key: SettingsKeys.restorePending, value: '{oops'));
    expect(await backup.applyPending(), 0);
    expect(await waiting(), isNull);
  });
}
