import 'package:audio_service/audio_service.dart';

import '../../domain/entities/track.dart';
import '../../domain/entities/track_keys.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../../l10n/l10n.dart';
import '../utils/display_names.dart';

/// The library as Android Auto (and the system's media controls) browse it: four tabs —
/// Recent, Favorites, Playlists, Songs — and the songs in them. A song's id says where it was
/// picked ("favorites/12"), so playing it plays that list from that song, as a tap does in
/// the app. Who may browse at all is decided on the Kotlin side (BrowseGuard.kt).
class MediaCatalog {
  MediaCatalog({required this.library, required this.history, required this.playlists});

  final LibraryRepository library;
  final HistoryRepository history;
  final PlaylistRepository playlists;

  static const recentId = 'recent_songs';
  static const favoritesId = 'favorites';
  static const playlistsId = 'playlists';
  static const songsId = 'songs';
  static const _playlistPrefix = 'playlist:';

  /// A car screen scrolls badly: the newest or first this many of a list.
  static const maxItems = 300;

  Future<List<MediaItem>> children(String parentId) async {
    switch (parentId) {
      case AudioService.browsableRootId:
        return [
          _folder(recentId, l10n.navRecent),
          _folder(favoritesId, l10n.navFavorites),
          _folder(playlistsId, l10n.navPlaylists),
          _folder(songsId, l10n.tabSongs),
        ];
      // The system asks this to offer the last song again (media resumption)
      case AudioService.recentRootId:
        return [for (final t in (await _recent()).take(1)) _song(recentId, t)];
      case playlistsId:
        return [
          for (final p in (await playlists.watchPlaylists().first).take(maxItems))
            _folder('$_playlistPrefix${p.id}', p.name, subtitle: l10n.songCount(p.trackCount)),
        ];
      default:
        final tracks = await _list(parentId);
        return tracks == null ? const [] : [for (final t in tracks.take(maxItems)) _song(parentId, t)];
    }
  }

  /// The list a song id was picked from and the song's place in it; null when it isn't one.
  Future<({List<Track> queue, int index})?> resolve(String mediaId) async {
    final slash = mediaId.lastIndexOf('/');
    if (slash <= 0) return null;
    final id = int.tryParse(mediaId.substring(slash + 1));
    final tracks = await _list(mediaId.substring(0, slash));
    if (id == null || tracks == null) return null;
    final queue = tracks.take(maxItems).toList();
    final index = queue.indexWhere((t) => t.id == id);
    return index < 0 ? null : (queue: queue, index: index);
  }

  Future<MediaItem?> item(String mediaId) async {
    final r = await resolve(mediaId);
    if (r == null) return null;
    return _song(mediaId.substring(0, mediaId.lastIndexOf('/')), r.queue[r.index]);
  }

  /// Songs whose title, artist or album has [query] ("play Yalın on Nocturne"); an empty
  /// query is the whole library ("play music on Nocturne").
  Future<List<Track>> search(String query) async =>
      searchTracks(await library.watchTracks(sort: TrackSort.title).first, query).take(maxItems).toList();

  Future<List<MediaItem>> searchItems(String query) async =>
      [for (final t in await search(query)) _song(songsId, t)];

  Future<List<Track>?> _list(String id) async {
    if (id == recentId) return _recent();
    if (id == favoritesId) return library.watchFavorites().first;
    if (id == songsId) return library.watchTracks(sort: TrackSort.title).first;
    if (id.startsWith(_playlistPrefix)) {
      final pid = int.tryParse(id.substring(_playlistPrefix.length));
      return pid == null ? null : playlists.watchTracks(pid).first;
    }
    return null;
  }

  Future<List<Track>> _recent() async =>
      [for (final p in await history.watchRecentlyPlayed(limit: 50).first) p.track];

  static MediaItem _folder(String id, String title, {String? subtitle}) =>
      MediaItem(id: id, title: title, playable: false, displaySubtitle: subtitle);

  static MediaItem _song(String list, Track t) => MediaItem(
        id: '$list/${t.id}',
        title: t.title,
        artist: t.artistLabel,
        album: t.albumLabel,
        duration: t.duration,
        playable: true,
        artUri: t.coverPath == null ? null : Uri.file(t.coverPath!),
      );
}
