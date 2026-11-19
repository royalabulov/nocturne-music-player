import 'dart:typed_data';

import '../entities/track.dart';
import '../entities/track_keys.dart';
import 'song_radio.dart';

/// Duplicate finder: the same song in more than one file ("Keşke.mp3" and "Keşke (1).mp3",
/// a 128 kbps download next to the 320 kbps one).
///
/// Two files are the same song when their lengths are within [duplicateLengthSlack] and
/// * they sound the same: radio's centered embedding at [duplicateSoundMin] or closer (on FMA
///   small, 8000 different songs, 31 pairs reach 0.97 and 28 of them are one artist's same
///   song uploaded twice: tool/duplicates_eval/nearest.dart), or
/// * their tags say so: the same title once copy marks are taken off, by the same artist.
///
/// Pure Dart: no Flutter, no database.

const duplicateLengthSlack = Duration(seconds: 2);
const duplicateSoundMin = 0.97;

/// Below this two analyzed files are different songs even with the same title (FMA small: the
/// median song's nearest other song is 0.79).
const duplicateSoundFar = 0.8;

/// Groups of two or more files of one song. In each group the file to keep comes first (the
/// best quality: lossless, then bitrate, then size, then one with a cover, then the oldest);
/// groups with the most copies first. [sound] compares analyzed songs by sound; without it, or
/// for songs not analyzed, the tags decide. [ignored]: groups the user said aren't the same
/// song (their sorted ids), never shown again.
List<List<Track>> findDuplicates(
  List<Track> tracks, {
  RadioLibrary? sound,
  Set<String> ignored = const {},
}) {
  final list = [for (final t in tracks) if (!t.isMissing) t]..sort((a, b) => a.duration.compareTo(b.duration));
  final parent = List.generate(list.length, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  final titles = [for (final t in list) duplicateTitleKey(t.title)];
  final artists = [for (final t in list) _artistKeys(t)];
  final vectors = <int, Float64List?>{};
  Float64List? vector(int i) => vectors.putIfAbsent(i, () => sound?.vector(list[i].id));

  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      if (list[j].duration - list[i].duration > duplicateLengthSlack) break;
      if (_sameSong(titles[i], titles[j], artists[i], artists[j], vector(i), vector(j))) {
        parent[root(j)] = root(i);
      }
    }
  }

  final groups = <int, List<Track>>{};
  for (var i = 0; i < list.length; i++) {
    (groups[root(i)] ??= []).add(list[i]);
  }
  final out = [
    for (final g in groups.values)
      if (g.length > 1 && !ignored.contains(duplicateGroupKey(g))) g..sort(_betterFirst),
  ]..sort((a, b) {
      final c = b.length.compareTo(a.length);
      return c != 0 ? c : a.first.title.compareTo(b.first.title);
    });
  return out;
}

/// A group's lasting name: its ids, sorted ("12,40,77").
String duplicateGroupKey(List<Track> group) => ([for (final t in group) t.id]..sort()).join(',');

bool _sameSong(String ta, String tb, Set<String> aa, Set<String> ab, Float64List? va, Float64List? vb) {
  if (va != null && vb != null) {
    var d = 0.0;
    for (var k = 0; k < va.length; k++) {
      d += va[k] * vb[k];
    }
    if (d >= duplicateSoundMin) return true;
    // Clearly different sound: different songs, whatever the tags say ("Intro" by one artist
    // on two albums). In between (another master, a rip with a second of noise), the tags decide.
    if (d < duplicateSoundFar) return false;
  }
  if (ta.isEmpty || ta != tb) return false;
  // Same title: the same artist too, or one of them without a known artist
  return aa.isEmpty || ab.isEmpty || aa.intersection(ab).isNotEmpty;
}

Set<String> _artistKeys(Track t) =>
    t.artist == kUnknownArtist || t.artist == kVariousArtists ? const {} : artistKeysOf(t);

final _trackNo = RegExp(r'^\s*\d{1,3}\s*[-._)]\s*');
// Not a bare trailing number: "Part 1" and "Part 2" are two songs
final _copyMark = RegExp(r'\s*(\(\d{1,2}\)|\[\d{1,2}\]|[-_ ]copy( \d+)?|[-_ ]kopya)\s*$', caseSensitive: false);
final _noise = RegExp(
  r'[\(\[][^\)\]]*(official|video|audio|lyric|lyrics|klip|hd|hq|4k|mp3|320k|128k|visualizer)[^\)\]]*[\)\]]',
  caseSensitive: false,
);
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// A title as the duplicate finder compares it: no track number, no "(1)" / "copy" a copy
/// got, no "(Official Video)", lower case. What tells versions apart stays: "(Remix)",
/// "(Live)", "(Slowed)".
String duplicateTitleKey(String title) {
  var s = title.replaceFirst(_trackNo, '');
  s = s.replaceAll(_noise, ' ');
  for (var i = 0; i < 2; i++) {
    s = s.replaceFirst(_copyMark, '');
  }
  return normalizeName(s).replaceAll(_nonWord, ' ').trim();
}

/// Better quality first, the oldest file on a tie.
int _betterFirst(Track a, Track b) {
  int pick(bool x, bool y) => x == y ? 0 : (x ? -1 : 1);
  var c = pick(a.format.isLossless, b.format.isLossless);
  if (c != 0) return c;
  c = (b.bitrateKbps ?? 0).compareTo(a.bitrateKbps ?? 0);
  if (c != 0) return c;
  c = b.fileSize.compareTo(a.fileSize);
  if (c != 0) return c;
  c = pick(a.coverPath != null, b.coverPath != null);
  if (c != 0) return c;
  final da = a.dateAdded, db = b.dateAdded;
  if (da != null && db != null && da != db) return da.compareTo(db);
  return a.id.compareTo(b.id);
}
