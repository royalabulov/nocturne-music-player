import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/wrapped.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';

Track _t(int id, {String artist = 'A'}) => Track(
      id: id,
      path: '/m/$id.mp3',
      title: 'Song $id',
      artist: artist,
      album: 'B',
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
    );

/// A play heard in full ([heard] null) or for [heard].
PlayRecord _p(int id, DateTime at, {Duration? heard = const Duration(minutes: 3)}) =>
    PlayRecord(trackId: id, playedAt: at, listened: heard, duration: const Duration(minutes: 3));

const _nov = WrappedPeriod.month(2026, 11);

/// [n] plays of each song in [ids], one a day from Nov [fromDay], at [hour].
List<PlayRecord> _each(List<int> ids, int n, {int fromDay = 1, int hour = 20}) => [
      for (final id in ids)
        for (var i = 0; i < n; i++) _p(id, DateTime(2026, 11, fromDay + i, hour)),
    ];

void main() {
  final tracks = {for (var i = 1; i <= 20; i++) i: _t(i)};

  group('WrappedPeriod', () {
    test('a month and a year cover their own days only', () {
      expect(_nov.contains(DateTime(2026, 11)), isTrue);
      expect(_nov.contains(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(_nov.contains(DateTime(2026, 12)), isFalse);
      expect(_nov.contains(DateTime(2026, 10, 31, 23, 59)), isFalse);
      const dec = WrappedPeriod.month(2026, 12);
      expect(dec.end, DateTime(2027), reason: 'December ends at the new year');
      expect(const WrappedPeriod.year(2026).contains(DateTime(2026, 12, 31)), isTrue);
    });

    test('ids go both ways; anything else is no period', () {
      expect(WrappedPeriod.parse('2026-11'), _nov);
      expect(WrappedPeriod.parse('2026'), const WrappedPeriod.year(2026));
      expect(WrappedPeriod.parse(_nov.id), _nov);
      for (final bad in ['2026-13', '2026-00', '26-11', 'nov', '', null]) {
        expect(WrappedPeriod.parse(bad), isNull, reason: '$bad');
      }
    });

    test('last month crosses into the year before in January', () {
      expect(WrappedPeriod.lastMonth(DateTime(2026, 12, 3)), _nov);
      expect(WrappedPeriod.lastMonth(DateTime(2027, 1, 2)), const WrappedPeriod.month(2026, 12));
    });
  });

  group('buildWrapped', () {
    test('too few plays or songs: no Wrapped yet', () {
      expect(buildWrapped(_nov, _each([1, 2, 3, 4, 5], 3), tracks), isNull, reason: '15 plays');
      expect(buildWrapped(_nov, _each([1, 2], 15), tracks), isNull, reason: '2 songs');
      expect(buildWrapped(_nov, _each([1, 2, 3, 4, 5], 4), tracks), isNotNull, reason: '20 plays, 5 songs');
    });

    test('top songs by plays; a skip neither counts as a play nor as a song', () {
      final plays = [
        ..._each([1], 9),
        ..._each([2], 6),
        ..._each([3, 4, 5, 6], 2),
        // 10 skips of song 7: heard 5 s each
        for (var i = 0; i < 10; i++) _p(7, DateTime(2026, 11, 5, 9, i), heard: const Duration(seconds: 5)),
      ];
      final w = buildWrapped(_nov, plays, tracks)!;
      expect(w.topSongs.map((s) => s.track.id), [1, 2, 3, 4, 5]);
      expect(w.topSongs.first.plays, 9);
      expect(w.plays, 23);
      expect(w.songCount, 6);
      // Listening time does include the skips: they were heard
      expect(w.listened, const Duration(minutes: 3) * 23 + const Duration(seconds: 50));
    });

    test('plays from before listening was measured count in full', () {
      final w = buildWrapped(_nov, [for (final p in _each([1, 2, 3, 4, 5], 4)) _p(p.trackId, p.playedAt, heard: null)], tracks)!;
      expect(w.plays, 20);
      expect(w.listened, const Duration(minutes: 60));
    });

    test('only the period is counted, but songs heard before it are not new', () {
      final plays = [
        _p(1, DateTime(2026, 10, 1)), // song 1 was already known in October
        ..._each([1, 2, 3, 4, 5], 4),
        _p(9, DateTime(2026, 12, 1)), // December doesn't count for November
      ];
      final w = buildWrapped(_nov, plays, tracks)!;
      expect(w.plays, 20);
      expect(w.discoveryCount, 4);
      expect(w.discoveries.map((s) => s.track.id), isNot(contains(1)));
      expect(w.discoveries, hasLength(3));
      expect(w.knowsDiscoveries, isTrue);
    });

    test('in the first weeks of the history nothing is called new: every song would be', () {
      // The history begins in this very month (the phone: a new install on Nov 3)
      final fresh = buildWrapped(_nov, _each([1, 2, 3, 4, 5], 4), tracks)!;
      expect(fresh.knowsDiscoveries, isFalse);
      expect(fresh.discoveryCount, 0);
      expect(fresh.discoveries, isEmpty);

      // Begun two weeks before: still too little to tell
      final short = buildWrapped(_nov, [_p(1, DateTime(2026, 10, 18)), ..._each([1, 2, 3, 4, 5], 4)], tracks)!;
      expect(short.knowsDiscoveries, isFalse);

      // Three weeks before: enough
      final long = buildWrapped(_nov, [_p(1, DateTime(2026, 10, 11)), ..._each([1, 2, 3, 4, 5], 4)], tracks)!;
      expect(long.knowsDiscoveries, isTrue);
      expect(long.discoveryCount, 4);
    });

    test('artists: a collab counts for both, unknown artists are left out', () {
      final t = {
        1: _t(1, artist: 'Yalın'),
        2: _t(2, artist: 'Yalın'),
        3: _t(3, artist: 'PASTER × RZZA'),
        4: _t(4, artist: kUnknownArtist),
        5: _t(5, artist: 'RZZA feat. Someone'),
      };
      final plays = [..._each([1, 2], 3), ..._each([3], 5), ..._each([4], 8), ..._each([5], 2)];
      final w = buildWrapped(_nov, plays, t)!;
      expect(w.topArtists.map((a) => a.name), ['RZZA', 'Yalın', 'PASTER']);
      expect(w.topArtists.first.plays, 7);
      expect(w.topArtists.first.cover.id, 3, reason: 'their most played song');
    });

    test('a song no longer in the library counts in the totals but is not shown', () {
      final plays = _each([1, 2, 3, 4, 5, 99], 4);
      final w = buildWrapped(_nov, plays, tracks)!;
      expect(w.plays, 24);
      expect(w.topSongs.map((s) => s.track.id), isNot(contains(99)));
    });

    test('moods weigh by listening time; shown only when half the time is analyzed', () {
      final plays = _each([1, 2, 3, 4, 5], 4);
      final mostly = buildWrapped(_nov, plays, tracks, moodOf: {1: 'sad', 2: 'sad', 3: 'calm', 4: null})!;
      expect(mostly.moodCoverage, closeTo(0.8, 1e-9));
      expect(mostly.moods.first.key, 'sad');
      expect(mostly.moods.first.value, closeTo(2 / 3, 1e-9), reason: 'of the songs with a mood');
      expect(mostly.showMoods, isTrue);

      final little = buildWrapped(_nov, plays, tracks, moodOf: {1: 'sad', 2: 'sad'})!;
      expect(little.moodCoverage, closeTo(0.4, 1e-9));
      expect(little.showMoods, isFalse);
    });

    test('the listening time of day goes by the hours with the most music', () {
      final evening = buildWrapped(_nov, _each([1, 2, 3, 4, 5], 4, hour: 19), tracks)!;
      expect(evening.time, ListeningTime.evening);
      expect(evening.peakHour, 19);
      final night = buildWrapped(_nov, [..._each([1, 2, 3], 4, hour: 2), ..._each([4, 5], 4, hour: 23)], tracks)!;
      expect(night.time, ListeningTime.night, reason: '02:00 and 23:00 are both night');
      expect(ListeningTime.of(5), ListeningTime.morning);
      expect(ListeningTime.of(4), ListeningTime.night);
      expect(ListeningTime.of(11), ListeningTime.afternoon);
      expect(ListeningTime.of(17), ListeningTime.evening);
      expect(ListeningTime.of(22), ListeningTime.night);
    });

    test('streak: the most days in a row with music', () {
      final days = [1, 2, 3, 5, 6, 7, 8, 9, 20];
      final plays = [
        for (final d in days)
          for (final id in [1, 2, 3, 4, 5]) _p(id, DateTime(2026, 11, d, 21)),
      ];
      final w = buildWrapped(_nov, plays, tracks)!;
      expect(w.longestStreak, 5);
      expect(w.activeDays, 9);
    });
  });

  group('wrappedPeriods', () {
    List<PlayRecord> month(int y, int m) => [
          for (var i = 0; i < 20; i++) _p(1 + i % 5, DateTime(y, m, 1 + i)),
        ];

    test('months with enough plays, newest first; a year once 3 of its months have one', () {
      expect(wrappedPeriods([...month(2026, 10), ...month(2026, 11)]),
          [_nov, const WrappedPeriod.month(2026, 10)]);
      final three = wrappedPeriods([...month(2026, 9), ...month(2026, 10), ...month(2026, 11)]);
      expect(three.first, _nov);
      expect(three.last, const WrappedPeriod.year(2026), reason: 'the year after its months');
    });

    test('a month with too few plays has none; how many it still needs', () {
      final few = _each([1, 2, 3, 4, 5], 3);
      expect(wrappedPeriods(few), isEmpty);
      expect(wrappedPlaysToGo(few, _nov), 5);
      expect(wrappedPlaysToGo(_each([1, 2, 3, 4, 5], 4), _nov), 0);
    });
  });
}
