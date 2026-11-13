import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/db/database_rescue.dart';

/// A damaged database made the first query fail before anything was drawn: the app hung on
/// its start screen for good, and clearing its data (and losing everything) was the only way out.
void main() {
  late Directory dir;
  late String file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nocturne_db');
    file = '${dir.path}/sonar.sqlite';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AppDatabase open() => AppDatabase(NativeDatabase(File(file)));

  Future<void> library(int songs) async {
    final db = open();
    for (var i = 0; i < songs; i++) {
      await db.into(db.tracks).insert(TracksCompanion.insert(
            path: '/m/$i.mp3',
            title: 'Song $i ${'x' * 200}',
            artist: 'A',
            album: 'B',
            format: 'mp3',
            dateAdded: 1,
            dateModified: 1,
          ));
    }
    await db.close();
  }

  List<String> setAside() => [
        for (final f in dir.listSync()) f.uri.pathSegments.last,
      ].where((n) => n.contains('.damaged-')).toList();

  test('a healthy database is left alone', () async {
    await library(3);
    final db = open();
    expect(await DatabaseRescue.setAsideIfDamaged(db, file), isFalse);
    expect(await db.select(db.tracks).get(), hasLength(3));
    await db.close();
    expect(setAside(), isEmpty);
  });

  test('a file that is no database at all is set aside, and a new one opens', () async {
    File(file).writeAsBytesSync(List.generate(8192, (i) => i % 251));
    expect(await DatabaseRescue.setAsideIfDamaged(open(), file), isTrue);
    expect(setAside(), hasLength(1), reason: 'kept, not deleted');

    final fresh = open();
    expect(await fresh.select(fresh.tracks).get(), isEmpty);
    await fresh.close();
  });

  test('a database with damaged pages is set aside', () async {
    await library(300);
    final bytes = File(file).readAsBytesSync();
    final noise = Random(1);
    // Leave the header (first page) so it still opens, scramble the table pages
    for (var i = 4096 * 2; i < bytes.length; i++) {
      bytes[i] = noise.nextInt(256);
    }
    File(file).writeAsBytesSync(bytes);

    expect(await DatabaseRescue.setAsideIfDamaged(open(), file), isTrue);
    final fresh = open();
    expect(await fresh.select(fresh.tracks).get(), isEmpty);
    await fresh.close();
  });

  // Damage that doesn't stop the check from running: SQLite lists what it found instead of "ok"
  test('a check that lists problems instead of "ok" is damage too', () async {
    await library(1);
    final db = AppDatabase(NativeDatabase(File(file)).interceptWith(_Verdict('*** in database main ***\nPage 7: never used')));
    expect(await DatabaseRescue.setAsideIfDamaged(db, file), isTrue);
    expect(setAside(), contains(startsWith('sonar.sqlite.damaged-')));
  });

  // A bug in a future migration must not cost the user their data: that stays an error
  test('any other failure is not taken for damage', () async {
    await library(1);
    final broken = AppDatabase(NativeDatabase(File(file), setup: (_) => throw StateError('migration bug')));
    await expectLater(DatabaseRescue.setAsideIfDamaged(broken, file), throwsA(anything));
    expect(setAside(), isEmpty);
    await broken.close().catchError((_) {});
  });

  test('damage is recognised in SQLite\'s own words', () {
    expect(DatabaseRescue.isDamage(Exception('SqliteException(11): database disk image is malformed')), isTrue);
    expect(DatabaseRescue.isDamage(Exception('SqliteException(26): file is not a database')), isTrue);
    expect(DatabaseRescue.isDamage(Exception('SqliteException(13): database or disk is full')), isFalse);
    expect(DatabaseRescue.isDamage(StateError('migration bug')), isFalse);
  });
}

/// Answers the database check with [verdict], everything else as usual.
class _Verdict extends QueryInterceptor {
  _Verdict(this.verdict);
  final String verdict;

  @override
  Future<List<Map<String, Object?>>> runSelect(QueryExecutor executor, String statement, List<Object?> args) async {
    if (statement.contains('quick_check')) return [{'quick_check': verdict}];
    return super.runSelect(executor, statement, args);
  }
}
