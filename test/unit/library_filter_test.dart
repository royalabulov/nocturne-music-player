import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/cover_cache.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/mappers/track_mapper.dart';
import 'package:sonar/data/repositories/library_repository_impl.dart';
import 'package:sonar/domain/repositories/library_repository.dart';
import 'package:sonar/features/settings/library_filter_section.dart';

/// Settings → Library filter (size/length range) and Home sort.
void main() {
  late AppDatabase db;

  // (name, size KB, length s)
  const files = [
    ('voice note', 60, 12),
    ('ringtone', 400, 30),
    ('song', 5000, 200),
    ('long mix', 90000, 3600),
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.batch((b) => b.insertAll(db.tracks, [
          for (final (i, f) in files.indexed)
            TracksCompanion.insert(
              path: '/m/$i.mp3',
              title: f.$1,
              artist: 'A',
              album: 'B',
              format: 'mp3',
              durationMs: Value(f.$3 * 1000),
              fileSize: Value(f.$2 * 1024),
              dateAdded: i,
              dateModified: i,
            ),
        ]));
  });
  tearDown(() => db.close());

  Future<List<String>> titles(TrackFilter f, {TrackSort sort = TrackSort.title}) async {
    final repo = LibraryRepositoryImpl(db, TrackMapper(CoverCache()), filter: f);
    return [for (final t in await repo.watchTracks(sort: sort).first) t.title];
  }

  test('default filter hides voice notes and ringtones', () async {
    expect(await titles(TrackFilter.defaults), ['long mix', 'song']);
  });

  test('lowering the limits shows short files without a rescan', () async {
    expect(await titles(const TrackFilter(minBytes: 0, minMs: 0)), ['long mix', 'ringtone', 'song', 'voice note']);
  });

  test('an upper length limit hides long mixes', () async {
    expect(await titles(const TrackFilter(maxMs: 300000)), ['song']);
  });

  test('sort by length', () async {
    const all = TrackFilter(minBytes: 0, minMs: 0);
    expect(await titles(all, sort: TrackSort.longest), ['long mix', 'song', 'ringtone', 'voice note']);
    expect(await titles(all, sort: TrackSort.shortest), ['voice note', 'ringtone', 'song', 'long mix']);
  });

  test('slider ends mean "no limit"', () {
    final f = filterFromRanges(const RangeValues(100, 2000), const RangeValues(40, 300));
    expect(f, TrackFilter.defaults);
    final g = filterFromRanges(const RangeValues(0, 1000), const RangeValues(0, 120));
    expect(g.maxBytes, 1000 * 1024);
    expect(g.maxMs, 120000);
  });

  test('labels', () {
    expect(formatKb(100), '100 KB');
    expect(formatKb(1500), '1.5 MB');
    expect(formatKb(2000), 'No limit');
    expect(formatSec(40), '0:40');
    expect(formatSec(300), 'No limit');
  });
}
