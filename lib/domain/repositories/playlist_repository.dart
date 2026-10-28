import '../entities/playlist.dart';
import '../entities/track.dart';

abstract interface class PlaylistRepository {
  /// All playlists, most recently changed first. trackCount/totalDuration/cover
  /// come aggregated.
  Stream<List<Playlist>> watchPlaylists();

  Stream<Playlist?> watchPlaylist(int id);

  /// The playlist's tracks, in position order.
  Stream<List<Track>> watchTracks(int playlistId);

  /// Which playlists contain the track (ticks in the Add to playlist sheet).
  Stream<Set<int>> watchPlaylistIdsContaining(int trackId);

  Future<int> create(String name, {String description = ''});
  Future<void> rename(int id, String name, {String? description});
  Future<void> delete(int id);

  /// Not added if already there. Appended to the end.
  Future<void> addTracks(int playlistId, List<int> trackIds);
  Future<void> removeTrack(int playlistId, int trackId);
  Future<void> reorder(int playlistId, int oldIndex, int newIndex);
}
