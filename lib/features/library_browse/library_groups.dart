import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/datasources/tag_reader.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/library_repository.dart';
import '../../l10n/l10n.dart';

/// Album / artist views. There's no separate DB table — grouped from the
/// in-memory library (a few ms even for 2000+ tracks).
class AlbumGroup {
  AlbumGroup({required this.key, required this.title, required this.artist, required this.tracks});

  /// Normalised album name (route parameter).
  final String key;
  final String title;

  /// The artist's name if there's one, "Various Artists" if several.
  final String artist;

  /// Disc order (trackNo), then name.
  final List<Track> tracks;

  bool get isUnknown => title == TagReader.unknownAlbum;
  String? get coverPath => tracks.map((t) => t.coverPath).nonNulls.firstOrNull;
  int? get year => tracks.map((t) => t.year).nonNulls.fold<int?>(null, (a, b) => a == null || b > a ? b : a);
  Duration get totalDuration => tracks.fold(Duration.zero, (a, t) => a + t.duration);
}

class ArtistGroup {
  ArtistGroup({required this.key, required this.name, required this.tracks});

  final String key;
  final String name;

  /// Album, then disc order.
  final List<Track> tracks;

  bool get isUnknown => name == TagReader.unknownArtist;
  String? get coverPath => tracks.map((t) => t.coverPath).nonNulls.firstOrNull;
  int get albumCount => {
    for (final t in tracks)
      if (t.album != TagReader.unknownAlbum) _norm(t.album),
  }.length;
}

String _norm(String s) => s.trim().toLowerCase();

/// "Artist feat. X" → "Artist": features don't create separate artists.
/// Names like "Simon & Garfunkel", "AC/DC" aren't split.
final _feat = RegExp(r'\s+[\(\[]?(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
String primaryArtist(String artist) {
  final s = artist.replaceFirst(_feat, '').trim();
  return s.isEmpty ? artist.trim() : s;
}

/// "PASTER × RZZA", "Paster x OD" → each name. Only "×" and a spaced "x" join
/// artists; "&" and "," stay ("Simon & Garfunkel", "Tyler, The Creator").
final _collab = RegExp(r'\s*×\s*|\s+[xX]\s+');
List<String> artistsOf(String artist) {
  final names = [
    for (final n in primaryArtist(artist).split(_collab))
      if (n.trim().isNotEmpty) n.trim(),
  ];
  return names.isEmpty ? [artist.trim()] : names;
}

int _byDisc(Track a, Track b) {
  final na = a.trackNo, nb = b.trackNo;
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return _norm(a.title).compareTo(_norm(b.title));
}

/// Alphabetical, "Unknown ..." last.
int _byName(String a, String b, String unknown) {
  if (a == unknown && b != unknown) return 1;
  if (b == unknown && a != unknown) return -1;
  return _norm(a).compareTo(_norm(b));
}

List<AlbumGroup> groupAlbums(List<Track> tracks) {
  final byKey = <String, List<Track>>{};
  for (final t in tracks) {
    if (t.isMissing) continue;
    (byKey[_norm(t.album)] ??= []).add(t);
  }
  final out = [
    for (final e in byKey.entries)
      () {
        final list = [...e.value]..sort(_byDisc);
        final artists = {for (final t in list) _norm(primaryArtist(t.artist))};
        return AlbumGroup(
          key: e.key,
          title: list.first.album,
          artist: artists.length == 1 ? primaryArtist(list.first.artist) : 'Various Artists',
          tracks: list,
        );
      }(),
  ];
  out.sort((a, b) => _byName(a.title, b.title, TagReader.unknownAlbum));
  return out;
}

/// A collaboration is listed under every artist in it.
List<ArtistGroup> groupArtists(List<Track> tracks) {
  final byKey = <String, List<Track>>{};
  // spelling → count per key: "Paster" ×10 beats "PASTER" ×7
  final spellings = <String, Map<String, int>>{};
  for (final t in tracks) {
    if (t.isMissing) continue;
    for (final name in artistsOf(t.artist)) {
      final key = _norm(name);
      (byKey[key] ??= []).add(t);
      final s = spellings[key] ??= {};
      s[name] = (s[name] ?? 0) + 1;
    }
  }
  final out = [
    for (final e in byKey.entries)
      () {
        final list = [...e.value]
          ..sort((a, b) {
            final c = _byName(a.album, b.album, TagReader.unknownAlbum);
            return c != 0 ? c : _byDisc(a, b);
          });
        final name = spellings[e.key]!.entries.reduce((a, b) => b.value > a.value ? b : a).key;
        return ArtistGroup(key: e.key, name: name, tracks: list);
      }(),
  ];
  out.sort((a, b) => _byName(a.name, b.name, TagReader.unknownArtist));
  return out;
}

/// Order of the Albums / Artists views (Home → Library header).
enum GroupSort {
  name,
  mostSongs,
  recentlyAdded;

  String get label => switch (this) {
        name => l10n.sortAZ,
        mostSongs => l10n.sortMostSongs,
        recentlyAdded => l10n.sortRecentlyAdded,
      };
}

int _newest(List<Track> tracks) =>
    tracks.fold(0, (m, t) => (t.dateAdded?.millisecondsSinceEpoch ?? 0) > m ? t.dateAdded!.millisecondsSinceEpoch : m);

/// [groupAlbums]/[groupArtists] are already A–Z; the other orders are applied here.
List<T> sortGroups<T>(List<T> groups, GroupSort sort, List<Track> Function(T) tracksOf) {
  if (sort == GroupSort.name) return groups;
  final out = [...groups];
  switch (sort) {
    case GroupSort.mostSongs:
      out.sort((a, b) => tracksOf(b).length.compareTo(tracksOf(a).length));
    case GroupSort.recentlyAdded:
      out.sort((a, b) => _newest(tracksOf(b)).compareTo(_newest(tracksOf(a))));
    case GroupSort.name:
      break;
  }
  return out;
}

const _all = (sort: TrackSort.recentlyAdded, query: '');

/// null = the library is still loading.
final albumsProvider = Provider.autoDispose<List<AlbumGroup>?>((ref) {
  final tracks = ref.watch(tracksProvider(_all)).value;
  return tracks == null ? null : groupAlbums(tracks);
});

final artistsProvider = Provider.autoDispose<List<ArtistGroup>?>((ref) {
  final tracks = ref.watch(tracksProvider(_all)).value;
  return tracks == null ? null : groupArtists(tracks);
});

/// Route-lar: /home/album?k=..., /home/artist?k=...
String albumRoute(String key) => '/home/album?k=${Uri.encodeQueryComponent(key)}';
String artistRoute(String key) => '/home/artist?k=${Uri.encodeQueryComponent(key)}';
String albumKeyOf(Track t) => _norm(t.album);
/// The first (main) artist — "Go to artist" opens this one.
String artistKeyOf(Track t) => _norm(artistsOf(t.artist).first);
Set<String> artistKeysOf(Track t) => {for (final n in artistsOf(t.artist)) _norm(n)};
