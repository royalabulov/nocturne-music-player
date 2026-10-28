import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/data/db/app_database.dart';
import 'package:sonar/data/repositories/analysis_repository_impl.dart';
import 'package:sonar/domain/repositories/analysis_repository.dart';
import 'package:sonar/features/smart_groups/smart_groups.dart';
import 'package:sonar/features/smart_groups/vibe_classifier.dart';

void main() {
  moodV2Tests();

  group('genreFromTag', () {
    test('common tags map to the right group', () {
      expect(genreFromTag('Hip-Hop'), Genre.hipHop);
      expect(genreFromTag('Rap/Hip Hop'), Genre.hipHop);
      expect(genreFromTag('Pop Rock'), Genre.rock);
      expect(genreFromTag('Synthpop'), Genre.electronic);
      expect(genreFromTag('K-Pop'), Genre.pop);
      expect(genreFromTag('Pop'), Genre.pop);
      expect(genreFromTag('Muğam'), Genre.eastern);
      expect(genreFromTag('Azeri Pop'), Genre.eastern);
      expect(genreFromTag('Deep House'), Genre.electronic);
      expect(genreFromTag('R&B'), Genre.rnb);
      expect(genreFromTag('OST'), Genre.soundtrack);
    });

    test('ID3v1 numeric genres', () {
      expect(genreFromTag('(7)'), Genre.hipHop);
      expect(genreFromTag('17'), Genre.rock);
      expect(genreFromTag('(12)'), isNull); // Other
    });

    test('junk and short-word false positives are ignored', () {
      expect(genreFromTag(null), isNull);
      expect(genreFromTag(''), isNull);
      expect(genreFromTag('Other'), isNull);
      expect(genreFromTag('www.mp3site.com'), isNull);
      expect(genreFromTag('Therapy'), isNull); // "rap" inside a word
      expect(genreFromTag('Demo'), isNull); // "emo" inside a word
    });
  });

  test('genreFromAudio: rapping vocals win; weak scores stay ungrouped', () {
    expect(genreFromAudio({'Rapping': .2, 'Pop music': .1}), Genre.hipHop);
    expect(genreFromAudio({'Middle Eastern music': .1, 'Pop music': .05}), Genre.eastern);
    expect(genreFromAudio({'Pop music': .01}), isNull);
  });

  test('mostly-speech audio (podcast) gets no group', () {
    final r = classifyLibrary([
      const TrackVibeData(trackId: 1, genreTag: 'Pop', scores: {'Speech': .9, 'Music': .05}),
    ]);
    expect(r[1], isNull);
  });

  test('moods are assigned relative to the library', () {
    // 12 neutral songs + one song that clearly stands out in each mood
    const base = {'Music': .8, 'Sad music': .002, 'Tender music': .002, 'Happy music': .002, 'Exciting music': .002};
    final inputs = [
      for (var i = 0; i < 12; i++) TrackVibeData(trackId: i, scores: base, rmsDb: -14),
      TrackVibeData(trackId: 100, scores: {...base, 'Sad music': .08}, rmsDb: -18),
      TrackVibeData(trackId: 101, scores: {...base, 'Happy music': .08}, rmsDb: -12),
      TrackVibeData(trackId: 102, scores: {...base, 'Exciting music': .08, 'Angry music': .03}, rmsDb: -8),
      TrackVibeData(trackId: 103, scores: {...base, 'Ambient music': .1, 'Tender music': .04}, rmsDb: -24),
    ];
    final r = classifyLibrary(inputs);
    expect(r[100]?.mood, Mood.sad);
    expect(r[101]?.mood, Mood.happy);
    expect(r[102]?.mood, Mood.energetic);
    expect(r[103]?.mood, Mood.calm);
    expect(r[0]?.mood, isNull); // neutral — stands out in no mood
  });

  test('few analyzed songs → no moods yet, but tag genres still work', () {
    final r = classifyLibrary([
      const TrackVibeData(trackId: 1, genreTag: 'Rock', scores: {'Sad music': .2}),
      const TrackVibeData(trackId: 2, genreTag: 'Jazz'),
    ]);
    expect(r[1]?.mood, isNull);
    expect(r[1]?.genre, Genre.rock);
    expect(r[2]?.genre, Genre.jazz);
  });

  test('buildSmartGroups: moods in fixed order, genres by size', () {
    final tracks = DemoLibrary.tracks().take(5).toList();
    final g = buildSmartGroups(tracks, {
      tracks[0].id: const VibeResult(mood: Mood.happy, genre: Genre.pop),
      tracks[1].id: const VibeResult(mood: Mood.sad, genre: Genre.rock),
      tracks[2].id: const VibeResult(genre: Genre.rock),
    });
    expect(g.moods.map((m) => m.id), ['sad', 'happy']);
    expect(g.genres.first.id, 'rock');
    expect(g.genres.first.tracks.length, 2);
    expect(g.byKey('mood:sad')?.tracks.single.id, tracks[1].id);
  });

  group('AnalysisRepositoryImpl', () {
    late AppDatabase db;
    late AnalysisRepositoryImpl repo;

    Future<int> addTrack(String title, {String? genre, int dateAdded = 1}) =>
        db.into(db.tracks).insert(TracksCompanion.insert(
              path: '/x/$title.mp3',
              title: title,
              artist: 'A',
              album: 'B',
              genre: Value(genre),
              format: 'mp3',
              durationMs: const Value(200000),
              fileSize: const Value(4000000),
              dateAdded: dateAdded,
              dateModified: 1,
            ));

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = AnalysisRepositoryImpl(db);
    });
    tearDown(() => db.close());

    test('pending → save → progress; failed songs are not retried; version bump re-queues', () async {
      final a = await addTrack('a', dateAdded: 1);
      final b = await addTrack('b', genre: 'Rap', dateAdded: 2);

      expect((await repo.pending(1)).map((p) => p.trackId), [b, a]); // newest first
      await repo.save(a, 1, scores: {'Sad music': .0123456, 'Pop music': .00001}, rmsDb: -12);
      await repo.save(b, 1); // failed
      expect(await repo.pending(1), isEmpty);
      expect(await repo.watchProgress(1).first, isA<AnalysisProgress>().having((p) => p.done, 'done', 2));

      final data = await repo.watchVibeData().first;
      final da = data.firstWhere((d) => d.trackId == a);
      expect(da.scores, {'Sad music': .0123}); // rounded, the tiny score dropped
      expect(da.rmsDb, -12);
      expect(data.firstWhere((d) => d.trackId == b).genreTag, 'Rap');

      expect((await repo.pending(2)).length, 2);
    });

    test('deleting a track removes its analysis', () async {
      final a = await addTrack('a');
      await repo.save(a, 1, scores: {'Music': .5});
      await db.customStatement('PRAGMA foreign_keys = ON');
      await (db.delete(db.tracks)..where((t) => t.id.equals(a))).go();
      expect(await db.select(db.trackAnalyses).get(), isEmpty);
    });
  });
}

void moodV2Tests() {
  test('genre fix: rap over an "African/Reggae"-sounding beat stays rap; ballads → pop', () {
    expect(genreFromAudio({'Rapping': .03, 'Hip hop music': .02, 'Music of Africa': .06, 'Reggae': .05}), Genre.hipHop);
    expect(genreFromAudio({'Christian music': .06, 'Rhythm and blues': .02}), Genre.pop);
  });

  test('mood v2: energy × major/minor', () {
    TrackVibeData row(int id, {required double rms, required double beat, required double bpm, required double mode}) =>
        TrackVibeData(trackId: id, rmsDb: rms, scores: {
          'Music': .8,
          '_beat': beat,
          '_bpm': bpm,
          '_mode': mode,
          '_centroid': 1500,
        });
    final rows = [
      for (var i = 0; i < 10; i++) row(i, rms: -14, beat: .2, bpm: 110, mode: 0), // neytral fon
      row(100, rms: -7, beat: .6, bpm: 150, mode: -.05), // high energy, minor
      row(101, rms: -7, beat: .6, bpm: 140, mode: .4), // high energy, clear major
      row(102, rms: -20, beat: .05, bpm: 80, mode: -.3), // sakit, minor
      row(103, rms: -20, beat: .05, bpm: 80, mode: .2), // sakit, major
    ];
    final r = classifyLibrary(rows);
    expect(r[100]?.mood, Mood.energetic);
    expect(r[101]?.mood, Mood.happy);
    expect(r[102]?.mood, Mood.sad);
    expect(r[103]?.mood, Mood.calm);
  });
}
