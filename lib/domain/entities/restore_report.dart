/// What a restored backup brought back.
class RestoreReport {
  const RestoreReport({
    required this.favorites,
    required this.playlists,
    required this.playlistTracks,
    required this.plays,
    required this.missingTracks,
  });
  final int favorites, playlists, playlistTracks, plays, missingTracks;
}
