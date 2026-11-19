import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/track.dart';
import '../../domain/entities/track_keys.dart';
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

  bool get isUnknown => title == kUnknownAlbum;
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

  bool get isUnknown => name == kUnknownArtist;
  String? get coverPath => tracks.map((t) => t.coverPath).nonNulls.firstOrNull;
  int get albumCount => {
    for (final t in tracks)
      if (t.album != kUnknownAlbum) normalizeName(t.album),
  }.length;
}

/// A folder on the phone that holds songs, by the folder the file is in (not its subfolders).
class FolderGroup {
  FolderGroup({required this.key, required this.name, required this.place, required this.tracks});

  /// The folder's full path (route parameter).
  final String key;

  /// Its own name, or "Phone" / "SD card" for the top of a storage.
  final String name;

  /// Where it is, in words: "Phone › Download", "WhatsApp", "SD card".
  final String place;

  /// By title.
  final List<Track> tracks;

  String? get coverPath => tracks.map((t) => t.coverPath).nonNulls.firstOrNull;
  Duration get totalDuration => tracks.fold(Duration.zero, (a, t) => a + t.duration);
}

/// Apps whose music sits in `Android/media/<package>`: shown by the app's name.
const _mediaApps = {
  'com.whatsapp': 'WhatsApp',
  'com.whatsapp.w4b': 'WhatsApp Business',
  'org.telegram.messenger': 'Telegram',
  'org.telegram.messenger.web': 'Telegram',
  'org.thunderdog.challegram': 'Telegram X',
};

/// [dir]'s name and where it is, in words. The phone's own storage is `/storage/emulated/<user>`,
/// a card /storage/XXXX-XXXX; anything else (the web demo) is shown as it is.
@visibleForTesting
({String name, String place}) describeFolder(String dir) {
  final parts = dir.split('/').where((p) => p.isNotEmpty).toList();
  final int rootLen;
  final String root;
  if (parts.length >= 3 && parts[0] == 'storage' && parts[1] == 'emulated') {
    rootLen = 3;
    root = l10n.storagePhone;
  } else if (parts.length >= 2 && parts[0] == 'storage' && parts[1] != 'emulated' && parts[1] != 'self') {
    rootLen = 2;
    root = l10n.storageSdCard;
  } else {
    final name = parts.isEmpty ? dir : parts.last;
    final parent = parts.length > 1 ? '/${parts.sublist(0, parts.length - 1).join('/')}' : '/';
    return (name: name, place: parent);
  }
  final inside = parts.sublist(rootLen);
  if (inside.isEmpty) return (name: root, place: root);
  // Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio → "WhatsApp"
  if (inside.length >= 3 && inside[0] == 'Android' && inside[1] == 'media') {
    final app = _mediaApps[inside[2]] ?? inside[2];
    return (name: inside.length == 3 ? app : inside.last, place: app);
  }
  final above = inside.sublist(0, inside.length - 1);
  // Deep folders keep the two nearest: "Phone › … › Snaptube › Audio"
  final shown = above.length > 2 ? ['…', ...above.sublist(above.length - 2)] : above;
  return (name: inside.last, place: [root, ...shown].join(' › '));
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '/' : path.substring(0, i);
}

/// Folders with songs, A–Z by name, then by place (two "Music" folders).
List<FolderGroup> groupFolders(List<Track> tracks) {
  final byDir = <String, List<Track>>{};
  for (final t in tracks) {
    if (t.isMissing) continue;
    (byDir[_dirOf(t.path)] ??= []).add(t);
  }
  final out = [
    for (final e in byDir.entries)
      () {
        final d = describeFolder(e.key);
        final list = [...e.value]..sort((a, b) => normalizeName(a.title).compareTo(normalizeName(b.title)));
        return FolderGroup(key: e.key, name: d.name, place: d.place, tracks: list);
      }(),
  ];
  out.sort((a, b) {
    final c = normalizeName(a.name).compareTo(normalizeName(b.name));
    if (c != 0) return c;
    final p = normalizeName(a.place).compareTo(normalizeName(b.place));
    return p != 0 ? p : a.key.compareTo(b.key);
  });
  return out;
}

int _byDisc(Track a, Track b) {
  final na = a.trackNo, nb = b.trackNo;
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return normalizeName(a.title).compareTo(normalizeName(b.title));
}

/// Alphabetical, "Unknown ..." last.
int _byName(String a, String b, String unknown) {
  if (a == unknown && b != unknown) return 1;
  if (b == unknown && a != unknown) return -1;
  return normalizeName(a).compareTo(normalizeName(b));
}

List<AlbumGroup> groupAlbums(List<Track> tracks) {
  final byKey = <String, List<Track>>{};
  for (final t in tracks) {
    if (t.isMissing) continue;
    (byKey[normalizeName(t.album)] ??= []).add(t);
  }
  final out = [
    for (final e in byKey.entries)
      () {
        final list = [...e.value]..sort(_byDisc);
        final artists = {for (final t in list) normalizeName(primaryArtist(t.artist))};
        return AlbumGroup(
          key: e.key,
          title: list.first.album,
          artist: artists.length == 1 ? primaryArtist(list.first.artist) : kVariousArtists,
          tracks: list,
        );
      }(),
  ];
  out.sort((a, b) => _byName(a.title, b.title, kUnknownAlbum));
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
      final key = normalizeName(name);
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
            final c = _byName(a.album, b.album, kUnknownAlbum);
            return c != 0 ? c : _byDisc(a, b);
          });
        final name = spellings[e.key]!.entries.reduce((a, b) => b.value > a.value ? b : a).key;
        return ArtistGroup(key: e.key, name: name, tracks: list);
      }(),
  ];
  out.sort((a, b) => _byName(a.name, b.name, kUnknownArtist));
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

final foldersProvider = Provider.autoDispose<List<FolderGroup>?>((ref) {
  final tracks = ref.watch(tracksProvider(_all)).value;
  return tracks == null ? null : groupFolders(tracks);
});
