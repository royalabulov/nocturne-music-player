import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/services/backup_service.dart';

/// Backup → new (reinstalled) DB → restore: data comes back by file path
/// even though the track ids differ.
void main() {
  Future<int> addTrack(AppDatabase db, String name) => db.into(db.tracks).insert(TracksCompanion.insert(
        path: '/music/$name.mp3',
        title: name,
        artist: 'A',
        album: 'B',
        format: 'mp3',
        durationMs: const Value(200000),
        fileSize: const Value(4000000),
        dateAdded: 1,
        dateModified: 1,
      ));

  test('export → fresh install → restore keeps favorites, playlists, history', () async {
    final oldDb = AppDatabase(NativeDatabase.memory());
    final a = await addTrack(oldDb, 'a');
    final b = await addTrack(oldDb, 'b');
    await addTrack(oldDb, 'gone');
    await oldDb.into(oldDb.favorites).insert(FavoritesCompanion.insert(trackId: Value(b), addedAt: 5));
    final pl = await oldDb.into(oldDb.playlists).insert(PlaylistsCompanion.insert(name: 'Mix', createdAt: 1, updatedAt: 1));
    await oldDb.into(oldDb.playlistTracks).insert(PlaylistTracksCompanion.insert(playlistId: pl, trackId: b, position: 0));
    await oldDb.into(oldDb.playlistTracks).insert(PlaylistTracksCompanion.insert(playlistId: pl, trackId: a, position: 1));
    await oldDb.into(oldDb.playHistory).insert(PlayHistoryCompanion.insert(trackId: a, playedAt: 100));
    await oldDb.into(oldDb.scanState).insert(ScanStateCompanion.insert(key: 'audioSettings', value: '{"crossfade":true}'));
    final json = await BackupService(oldDb).export();
    await oldDb.close();

    // New install: scanned in a different order, the 'gone' file doesn't exist
    final newDb = AppDatabase(NativeDatabase.memory());
    await addTrack(newDb, 'b');
    await addTrack(newDb, 'a');
    final svc = BackupService(newDb);
    final r = await svc.restore(json);
    expect(r.favorites, 1);
    expect(r.playlists, 1);
    expect(r.playlistTracks, 2);
    expect(r.plays, 1);

    final favPaths = [
      for (final f in await newDb.select(newDb.favorites).get())
        (await (newDb.select(newDb.tracks)..where((t) => t.id.equals(f.trackId))).getSingle()).path,
    ];
    expect(favPaths, ['/music/b.mp3']);
    final order = await (newDb.select(newDb.playlistTracks)..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
    final paths = {for (final t in await newDb.select(newDb.tracks).get()) t.id: t.path};
    expect(order.map((r) => paths[r.trackId]), ['/music/b.mp3', '/music/a.mp3']);
    final s = await (newDb.select(newDb.scanState)..where((s) => s.key.equals('audioSettings'))).getSingle();
    expect(s.value, contains('crossfade'));

    // A second restore duplicates nothing
    final again = await svc.restore(json);
    expect(again.favorites + again.playlists + again.playlistTracks + again.plays, 0);
    await newDb.close();
  });

  test('rejects non-backup files', () async {
    final db = AppDatabase(NativeDatabase.memory());
    expect(() => BackupService(db).restore('{"hello":1}'), throwsFormatException);
    await db.close();
  });
}
