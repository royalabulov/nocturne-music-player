class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.trackCount,
    required this.totalDuration,
    required this.updatedAt,
    this.coverPath,
  });

  final int id;
  final String name;
  final String description;
  final int trackCount;
  final Duration totalDuration;
  final DateTime updatedAt;

  /// Cover of the first track (aggregate).
  final String? coverPath;
}
