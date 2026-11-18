import 'dart:math';

import '../entities/track.dart';
import '../entities/track_keys.dart';
import '../repositories/history_repository.dart';

/// Nocturne Wrapped: a month's or a year's listening, summed up from the play history on this
/// phone. Nothing leaves the phone; sharing the card is the user's own tap.
///
/// Counting follows the Recent screen (history_repository_impl.dart): a play counts once heard
/// for 30 s, or half of a shorter song; listening time is the time really heard, skips
/// included. Plays from before that was measured count in full.
///
/// Pure Dart: no Flutter, no database.

/// A calendar month ([month] 1..12) or a whole year ([month] null).
class WrappedPeriod implements Comparable<WrappedPeriod> {
  const WrappedPeriod.month(this.year, int this.month);
  const WrappedPeriod.year(this.year) : month = null;

  final int year;
  final int? month;

  bool get isYear => month == null;
  DateTime get start => DateTime(year, month ?? 1);
  DateTime get end => isYear ? DateTime(year + 1) : DateTime(year, month! + 1);
  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// "2026-11" or "2026": for a route and for settings.
  String get id => isYear ? '$year' : '$year-${month.toString().padLeft(2, '0')}';

  static WrappedPeriod? parse(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})(?:-(\d{2}))?$').firstMatch(s);
    if (m == null) return null;
    final year = int.parse(m[1]!);
    if (m[2] == null) return WrappedPeriod.year(year);
    final month = int.parse(m[2]!);
    return month >= 1 && month <= 12 ? WrappedPeriod.month(year, month) : null;
  }

  /// The month before [now]'s: the one a new month's banner offers.
  static WrappedPeriod lastMonth(DateTime now) {
    final d = DateTime(now.year, now.month - 1);
    return WrappedPeriod.month(d.year, d.month);
  }

  /// Newest first; a year after its own months.
  @override
  int compareTo(WrappedPeriod o) {
    if (year != o.year) return o.year.compareTo(year);
    if (isYear != o.isYear) return isYear ? 1 : -1;
    return (o.month ?? 0).compareTo(month ?? 0);
  }

  @override
  bool operator ==(Object other) => other is WrappedPeriod && other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(year, month);
  @override
  String toString() => 'WrappedPeriod($id)';
}

/// The least a period needs before it has a Wrapped: below this the top song is a coin toss.
const wrappedMinPlays = 20;
const wrappedMinSongs = 5;

/// A year has its own Wrapped once this many of its months have one.
const wrappedYearMinMonths = 3;

/// The mood slide shows only when at least this share of the listening time is analyzed.
const wrappedMinMoodCoverage = 0.5;

/// How far back the history must reach before a period for its new songs to mean anything.
const wrappedHistoryForNew = Duration(days: 21);

/// When the listener listens most: from the time of day with the most listening.
enum ListeningTime {
  /// 05:00–11:00
  morning,

  /// 11:00–17:00
  afternoon,

  /// 17:00–22:00
  evening,

  /// 22:00–05:00
  night;

  static ListeningTime of(int hour) => switch (hour) {
        >= 5 && < 11 => morning,
        >= 11 && < 17 => afternoon,
        >= 17 && < 22 => evening,
        _ => night,
      };
}

class WrappedSong {
  const WrappedSong({required this.track, required this.plays, required this.listened});
  final Track track;
  final int plays;
  final Duration listened;
}

class WrappedArtist {
  const WrappedArtist({required this.name, required this.plays, required this.listened, required this.cover});
  final String name;
  final int plays;
  final Duration listened;

  /// Their most played song in the period: its cover stands for them.
  final Track cover;
}

class Wrapped {
  const Wrapped({
    required this.period,
    required this.plays,
    required this.songCount,
    required this.listened,
    required this.topSongs,
    required this.topArtists,
    required this.moods,
    required this.moodCoverage,
    required this.byHour,
    required this.time,
    required this.discoveries,
    required this.discoveryCount,
    this.knowsDiscoveries = true,
    required this.longestStreak,
    required this.activeDays,
  });

  final WrappedPeriod period;

  /// Plays that count, and the different songs among them.
  final int plays;
  final int songCount;
  final Duration listened;

  /// Most played first, at most 5.
  final List<WrappedSong> topSongs;

  /// Most played first, at most 5.
  final List<WrappedArtist> topArtists;

  /// Mood id → share of the listening time of songs with a mood (adds up to 1), largest first.
  final List<MapEntry<String, double>> moods;

  /// Share of all listening time whose song is analyzed (with or without a clear mood).
  final double moodCoverage;
  bool get showMoods => moods.isNotEmpty && moodCoverage >= wrappedMinMoodCoverage;

  /// Listening time per hour of the day, 0..23.
  final List<Duration> byHour;
  int get peakHour {
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (byHour[h] > byHour[best]) best = h;
    }
    return best;
  }

  final ListeningTime time;

  /// Songs first heard in this period, most played first (at most 3), and how many in all.
  final List<WrappedSong> discoveries;
  final int discoveryCount;

  /// Whether the history reaches far enough back to tell what is new: in the first weeks of
  /// it every song would be "heard for the first time". False → no discoveries (empty).
  final bool knowsDiscoveries;

  /// Most days in a row with music, and days with any.
  final int longestStreak;
  final int activeDays;
}

/// Whether a play counts as heard (the Recent screen's 30 s rule).
bool wrappedCounts(PlayRecord p) {
  final heard = p.listened;
  if (heard == null) return true;
  final half = Duration(milliseconds: p.duration.inMilliseconds ~/ 2);
  final need = half < const Duration(seconds: 30) ? half : const Duration(seconds: 30);
  return heard >= need;
}

Duration _heard(PlayRecord p) => p.listened ?? p.duration;

/// The periods that have a Wrapped, newest first. [now]'s own month is in it too (a Wrapped
/// "so far"), as long as it has enough plays.
List<WrappedPeriod> wrappedPeriods(Iterable<PlayRecord> plays) {
  final playsByMonth = <WrappedPeriod, int>{};
  final songsByMonth = <WrappedPeriod, Set<int>>{};
  for (final p in plays) {
    if (!wrappedCounts(p)) continue;
    final m = WrappedPeriod.month(p.playedAt.year, p.playedAt.month);
    playsByMonth[m] = (playsByMonth[m] ?? 0) + 1;
    (songsByMonth[m] ??= {}).add(p.trackId);
  }
  final months = [
    for (final m in playsByMonth.keys)
      if (playsByMonth[m]! >= wrappedMinPlays && songsByMonth[m]!.length >= wrappedMinSongs) m,
  ];
  final perYear = <int, int>{};
  for (final m in months) {
    perYear[m.year] = (perYear[m.year] ?? 0) + 1;
  }
  return [
    ...months,
    for (final MapEntry(key: y, value: n) in perYear.entries)
      if (n >= wrappedYearMinMonths) WrappedPeriod.year(y),
  ]..sort();
}

/// How many more counted plays [period] needs before it has a Wrapped (0 = it has one).
int wrappedPlaysToGo(Iterable<PlayRecord> plays, WrappedPeriod period) {
  final counted = plays.where((p) => period.contains(p.playedAt) && wrappedCounts(p)).length;
  return max(0, wrappedMinPlays - counted);
}

/// The Wrapped of [period] from every play on the phone ([plays]: also earlier ones, to tell
/// which songs were new). [tracks]: the library's songs by id; plays of songs no longer in it
/// count toward the totals but can't be shown. [moodOf]: trackId → mood id, or null for an
/// analyzed song with no clear mood; songs not in it aren't analyzed. Null when the period
/// has too few plays.
Wrapped? buildWrapped(
  WrappedPeriod period,
  Iterable<PlayRecord> plays,
  Map<int, Track> tracks, {
  Map<int, String?> moodOf = const {},
}) {
  final firstHeard = <int, DateTime>{};
  final inPeriod = <PlayRecord>[];
  DateTime? historyStart;
  for (final p in plays) {
    if (historyStart == null || p.playedAt.isBefore(historyStart)) historyStart = p.playedAt;
    if (wrappedCounts(p)) {
      final f = firstHeard[p.trackId];
      if (f == null || p.playedAt.isBefore(f)) firstHeard[p.trackId] = p.playedAt;
    }
    if (period.contains(p.playedAt)) inPeriod.add(p);
  }

  final playsOf = <int, int>{};
  final heardOf = <int, Duration>{};
  final byHour = List.filled(24, Duration.zero);
  final days = <DateTime>{};
  var counted = 0;
  var listened = Duration.zero;
  var moodTotal = Duration.zero, analyzed = Duration.zero;
  final moodTime = <String, Duration>{};

  for (final p in inPeriod) {
    final heard = _heard(p);
    listened += heard;
    heardOf[p.trackId] = (heardOf[p.trackId] ?? Duration.zero) + heard;
    byHour[p.playedAt.hour] += heard;
    moodTotal += heard;
    if (moodOf.containsKey(p.trackId)) {
      analyzed += heard;
      final mood = moodOf[p.trackId];
      if (mood != null) moodTime[mood] = (moodTime[mood] ?? Duration.zero) + heard;
    }
    if (!wrappedCounts(p)) continue;
    counted++;
    playsOf[p.trackId] = (playsOf[p.trackId] ?? 0) + 1;
    days.add(DateTime(p.playedAt.year, p.playedAt.month, p.playedAt.day));
  }
  if (counted < wrappedMinPlays || playsOf.length < wrappedMinSongs) return null;

  int byPlays(int a, int b) {
    final c = playsOf[b]!.compareTo(playsOf[a]!);
    if (c != 0) return c;
    final d = heardOf[b]!.compareTo(heardOf[a]!);
    return d != 0 ? d : a.compareTo(b);
  }

  WrappedSong song(int id) => WrappedSong(track: tracks[id]!, plays: playsOf[id]!, listened: heardOf[id]!);
  final shown = [for (final id in playsOf.keys) if (tracks.containsKey(id)) id]..sort(byPlays);

  // Artists: every name on a song ("A × B" is both), unknown ones left out
  final artistPlays = <String, int>{}, artistNames = <String, String>{};
  final artistHeard = <String, Duration>{}, artistCover = <String, int>{};
  for (final id in shown) {
    final t = tracks[id]!;
    if (t.artist == kUnknownArtist || t.artist == kVariousArtists) continue;
    for (final name in artistsOf(t.artist)) {
      final key = normalizeName(name);
      if (key.isEmpty) continue;
      artistNames.putIfAbsent(key, () => name);
      artistPlays[key] = (artistPlays[key] ?? 0) + playsOf[id]!;
      artistHeard[key] = (artistHeard[key] ?? Duration.zero) + heardOf[id]!;
      artistCover.putIfAbsent(key, () => id); // [shown] is most played first
    }
  }
  final artists = artistPlays.keys.toList()
    ..sort((a, b) {
      final c = artistPlays[b]!.compareTo(artistPlays[a]!);
      if (c != 0) return c;
      final d = artistHeard[b]!.compareTo(artistHeard[a]!);
      return d != 0 ? d : a.compareTo(b);
    });

  final moods = moodTime.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final withMood = moods.fold(Duration.zero, (s, e) => s + e.value);

  // New songs only when the history began well before the period: in its first weeks every
  // song is "new" (on the phone, a whole first month said 148 of 148)
  final knows = historyStart != null && !historyStart.isAfter(period.start.subtract(wrappedHistoryForNew));
  bool isNew(int id) => knows && firstHeard[id] != null && period.contains(firstHeard[id]!);
  final newOnes = [for (final id in shown) if (isNew(id)) id];

  // The time of day with the most listening
  final perTime = <ListeningTime, Duration>{};
  for (var h = 0; h < 24; h++) {
    final t = ListeningTime.of(h);
    perTime[t] = (perTime[t] ?? Duration.zero) + byHour[h];
  }
  final time = ListeningTime.values.reduce((a, b) => perTime[b]! > perTime[a]! ? b : a);

  return Wrapped(
    period: period,
    plays: counted,
    songCount: playsOf.length,
    listened: listened,
    topSongs: [for (final id in shown.take(5)) song(id)],
    topArtists: [
      for (final key in artists.take(5))
        WrappedArtist(
          name: artistNames[key]!,
          plays: artistPlays[key]!,
          listened: artistHeard[key]!,
          cover: tracks[artistCover[key]]!,
        ),
    ],
    moods: withMood == Duration.zero
        ? const []
        : [for (final e in moods) MapEntry(e.key, e.value.inMilliseconds / withMood.inMilliseconds)],
    moodCoverage: moodTotal == Duration.zero ? 0 : analyzed.inMilliseconds / moodTotal.inMilliseconds,
    byHour: byHour,
    time: time,
    discoveries: [for (final id in newOnes.take(3)) song(id)],
    discoveryCount: playsOf.keys.where(isNew).length,
    knowsDiscoveries: knows,
    longestStreak: _longestRun(days),
    activeDays: days.length,
  );
}

/// The longest run of calendar days in a row in [days] (local midnights).
int _longestRun(Set<DateTime> days) {
  final sorted = days.toList()..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in sorted) {
    // Calendar days, not 24 h: a daylight-saving day is 23 or 25 hours long
    final next = prev == null ? null : DateTime(prev.year, prev.month, prev.day + 1);
    run = (next != null && d == next) ? run + 1 : 1;
    best = max(best, run);
    prev = d;
  }
  return best;
}
