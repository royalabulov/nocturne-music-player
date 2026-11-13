import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/mappers/track_mapper.dart';
import 'package:nocturne/data/repositories/library_repository_impl.dart';
import 'package:nocturne/domain/entities/track_keys.dart';
import 'package:nocturne/domain/repositories/library_repository.dart';

/// SQLite's LIKE ignores case only for ASCII: "şəhər" didn't find "Şəhər", and % and _ in a
/// search acted as wildcards.
void main() {
  late AppDatabase db;
  late LibraryRepositoryImpl repo;

  Future<void> add(String title, {String artist = 'Someone', String album = 'Something', bool missing = false}) =>
      db.into(db.tracks).insert(TracksCompanion.insert(
            path: '/storage/emulated/0/Music/$title.mp3',
            title: title,
            artist: artist,
            album: album,
            format: 'mp3',
            durationMs: const Value(200000),
            fileSize: const Value(5000000),
            dateAdded: 1,
            dateModified: 1,
            isMissing: Value(missing),
          ));

  Future<List<String>> search(String q, {TrackSort sort = TrackSort.title}) async =>
      [for (final t in await repo.watchTracks(sort: sort, query: q).first) t.title];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepositoryImpl(db, TrackMapper(CoverCache()));
  });
  tearDown(() => db.close());

  group('Azerbaijani letters', () {
    test('any case finds any case', () async {
      await add('Şəhər');
      for (final q in ['şəhər', 'ŞƏHƏR', 'Şəhər', 'ƏHƏR', 'əhər']) {
        expect(await search(q), ['Şəhər'], reason: q);
      }
    });

    test('every letter that is not ASCII', () async {
      await add('ÇĞÖÜŞƏ');
      for (final q in ['çğöüşə', 'ÇğÖüŞə']) {
        expect(await search(q), ['ÇĞÖÜŞƏ'], reason: q);
      }
    });

    test('I and ı: "QIZ" and "qız" are the same word here', () async {
      await add('Qız');
      await add('QIZIL');
      expect(await search('qız'), ['QIZIL', 'Qız']);
      expect(await search('QIZ'), ['QIZIL', 'Qız']);
      expect(await search('qiz'), ['QIZIL', 'Qız']);
    });

    test('İ', () async {
      await add('İlqar');
      expect(await search('ilqar'), ['İlqar']);
      expect(await search('İLQAR'), ['İlqar']);
    });

    test('in the artist and the album too', () async {
      await add('A', artist: 'Şəbnəm');
      await add('B', album: 'Gözəl günlər');
      expect(await search('şəbnəm'), ['A']);
      expect(await search('GÖZƏL'), ['B']);
    });
  });

  group('the search itself', () {
    test('% and _ are plain characters', () async {
      await add('100% love');
      await add('a_b');
      await add('axb');
      expect(await search('%'), ['100% love']);
      expect(await search('a_b'), ['a_b']);
    });

    test('spaces around it do not count; nothing typed means everything', () async {
      await add('Rain');
      await add('Sun');
      expect(await search('  rain '), ['Rain']);
      expect(await search(''), ['Rain', 'Sun']);
      expect(await search('   '), ['Rain', 'Sun']);
    });

    test('the sort order stays', () async {
      await add('c rain');
      await add('a rain');
      await add('b rain');
      expect(await search('rain'), ['a rain', 'b rain', 'c rain']);
    });

    test('a hidden song is not found', () async {
      await add('Rain', missing: true);
      expect(await search('rain'), isEmpty);
    });

    test('no match is an empty list', () async {
      await add('Rain');
      expect(await search('zzz'), isEmpty);
    });

    test('the list follows the library while searching', () async {
      await add('Rain');
      final lists = repo.watchTracks(query: 'şəhər').map((l) => l.length);
      final seen = <int>[];
      final sub = lists.listen(seen.add);
      await pumpEventQueue();
      await add('Şəhər');
      await pumpEventQueue(times: 50);
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 1);
    });
  });

  group('names', () {
    test('compare the same way as the search', () {
      expect(normalizeName('QIZ'), normalizeName('qız'));
      expect(normalizeName(' Şəhər '), normalizeName('ŞƏHƏR'));
      expect(normalizeName('İLQAR'), normalizeName('ilqar'));
      expect(normalizeName('i\u0307lqar'), 'ilqar');
    });
  });
}
