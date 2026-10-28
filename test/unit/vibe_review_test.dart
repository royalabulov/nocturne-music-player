import 'dart:math';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/repositories/analysis_repository_impl.dart';
import 'package:sonar/data/services/backup_service.dart';
import 'package:sonar/domain/repositories/analysis_repository.dart';
import 'package:sonar/features/smart_groups/vibe_classifier.dart';
import 'package:sonar/features/smart_groups/vibe_export.dart';
import 'package:sonar/features/smart_groups/vibe_review.dart';

VibeLabel label(int id, String mood, String genre, String pMood, String pGenre) => VibeLabel(
      trackId: id,
      mood: mood,
      genre: genre,
      predictedMood: pMood,
      predictedGenre: pGenre,
      labeledAt: DateTime(2026),
    );

void main() {
  currentAccuracyTests();

  test('labels override predictions; "none" removes the song from groups', () {
    final r = applyLabels(
      {
        1: const VibeResult(mood: Mood.calm, genre: Genre.pop),
        2: const VibeResult(mood: Mood.happy),
      },
      [label(1, 'sad', 'eastern', 'calm', 'pop'), label(2, kNone, kNone, 'happy', kNone), label(3, 'energetic', kNone, kNone, kNone)],
    );
    expect(r[1]?.mood, Mood.sad);
    expect(r[1]?.genre, Genre.eastern);
    expect(r.containsKey(2), false);
    expect(r[3]?.mood, Mood.energetic);
  });

  test('accuracy report counts hits and ranks the most common mistakes', () {
    final rep = accuracyOf([
      label(1, 'sad', 'pop', 'sad', 'pop'),
      label(2, 'sad', 'pop', 'calm', 'pop'),
      label(3, 'sad', 'rock', 'calm', 'pop'),
      label(4, 'happy', 'pop', 'energetic', 'pop'),
    ]);
    expect(rep.total, 4);
    expect(rep.moodCorrect, 1);
    expect(rep.genreAccuracy, .75);
    expect(rep.moodErrors.first.predicted, 'calm');
    expect(rep.moodErrors.first.actual, 'sad');
    expect(rep.moodErrors.first.count, 2);
    expect(accuracyOf(const []).moodAccuracy, 0);
  });

  test('review sample covers every predicted group and skips answered / unanalyzed songs', () {
    const scores = {'Music': .8};
    final data = [
      for (var i = 0; i < 30; i++) TrackVibeData(trackId: i, scores: scores), // all "calm"
      const TrackVibeData(trackId: 100, scores: scores), // sad
      const TrackVibeData(trackId: 101, scores: scores), // qrupsuz
      const TrackVibeData(trackId: 102), // not analyzed
      const TrackVibeData(trackId: 103, scores: {'Speech': .9, 'Music': .01}), // podkast
    ];
    final predicted = {
      for (var i = 0; i < 30; i++) i: const VibeResult(mood: Mood.calm),
      100: const VibeResult(mood: Mood.sad),
    };
    final s = pickReviewSample(data, predicted, {5}, count: 6, random: Random(1));
    expect(s.length, 6);
    expect(s, containsAll([100, 101])); // small groups get picked too
    expect(s, isNot(contains(5)));
    expect(s, isNot(contains(102)));
    expect(s, isNot(contains(103)));
  });

  test('CSV export escapes commas/quotes and lists every score column', () {
    final t = DemoLibrary.tracks().first;
    final csv = buildVibeCsv(
      tracks: [t],
      data: [TrackVibeData(trackId: t.id, genreTag: 'Rap, "Trap"', scores: const {'Sad music': .01, 'Pop music': .2}, rmsDb: -12.345)],
      predicted: {t.id: const VibeResult(genre: Genre.hipHop)},
      labels: [label(t.id, 'sad', 'hipHop', kNone, 'hipHop')],
    );
    final lines = csv.split('\r\n');
    expect(lines.first, endsWith(',Pop music,Sad music'));
    expect(lines[1], contains('"Rap, ""Trap"""'));
    expect(lines[1], contains(',-12.35,none,hipHop,sad,hipHop,none,hipHop,0.2,0.01'));
  });

  group('labels in DB', () {
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

    test('save / update / delete', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AnalysisRepositoryImpl(db);
      final a = await addTrack(db, 'a');
      await repo.saveLabel(label(a, 'sad', 'pop', 'calm', 'pop'));
      await repo.saveLabel(label(a, 'happy', 'pop', 'calm', 'pop')); // changed their mind
      final ls = await repo.watchLabels().first;
      expect(ls.single.mood, 'happy');
      expect(ls.single.moodCorrect, false);
      await repo.deleteLabel(a);
      expect(await repo.watchLabels().first, isEmpty);
    });

    test('answers survive backup → fresh install → restore', () async {
      final oldDb = AppDatabase(NativeDatabase.memory());
      final a = await addTrack(oldDb, 'a');
      await AnalysisRepositoryImpl(oldDb).saveLabel(label(a, 'sad', 'eastern', 'calm', 'pop'));
      final json = await BackupService(oldDb).export();
      await oldDb.close();

      final newDb = AppDatabase(NativeDatabase.memory());
      addTearDown(newDb.close);
      await addTrack(newDb, 'other');
      final a2 = await addTrack(newDb, 'a');
      await BackupService(newDb).restore(json);
      final ls = await AnalysisRepositoryImpl(newDb).watchLabels().first;
      expect(ls.single.trackId, a2);
      expect(ls.single.genre, 'eastern');
      expect(ls.single.predictedMood, 'calm');
    });
  });
}

void currentAccuracyTests() {
  test('current accuracy compares answers with today’s predictions, not the old ones', () {
    final labels = [label(1, 'sad', 'pop', 'happy', 'rnb'), label(2, 'calm', 'hipHop', 'calm', 'latin')];
    expect(accuracyOf(labels).moodCorrect, 1);
    final now = currentAccuracy(labels, {
      1: const VibeResult(mood: Mood.sad, genre: Genre.pop),
      2: const VibeResult(mood: Mood.calm, genre: Genre.hipHop),
    });
    expect(now.moodCorrect, 2);
    expect(now.genreCorrect, 2);
  });
}
