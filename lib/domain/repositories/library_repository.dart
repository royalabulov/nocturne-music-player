import '../../core/constants.dart';
import '../entities/track.dart';

/// Library statistics for the Home greeting.
class LibraryStats {
  const LibraryStats({
    required this.trackCount,
    required this.totalDuration,
    required this.losslessCount,
    required this.maxSampleRateHz,
    required this.maxBitDepth,
    this.lastScanAt,
  });

  static const empty = LibraryStats(
    trackCount: 0,
    totalDuration: Duration.zero,
    losslessCount: 0,
    maxSampleRateHz: 0,
    maxBitDepth: 0,
  );

  final int trackCount;
  final Duration totalDuration;
  final int losslessCount;
  final int maxSampleRateHz;
  final int maxBitDepth;
  final DateTime? lastScanAt;

  // Value equality: screens don't rebuild when the stream repeats the same result.
  @override
  bool operator ==(Object other) =>
      other is LibraryStats &&
      other.trackCount == trackCount &&
      other.totalDuration == totalDuration &&
      other.losslessCount == losslessCount &&
      other.maxSampleRateHz == maxSampleRateHz &&
      other.maxBitDepth == maxBitDepth &&
      other.lastScanAt == lastScanAt;

  @override
  int get hashCode =>
      Object.hash(trackCount, totalDuration, losslessCount, maxSampleRateHz, maxBitDepth, lastScanAt);
}

enum TrackSort {
  recentlyAdded('Recently added'),
  title('Title A–Z'),
  artist('Artist'),
  album('Album'),
  longest('Longest first'),
  shortest('Shortest first');

  const TrackSort(this.label);
  final String label;
}

/// Which files show up in the library: size and length range
/// (Settings → Library filter). The scanner writes every audio file to the DB;
/// this filter is applied only in queries → changing it needs no rescan.
class TrackFilter {
  const TrackFilter({
    this.minBytes = kMinTrackBytes,
    this.maxBytes,
    this.minMs = 40000,
    this.maxMs,
  });

  final int minBytes, minMs;

  /// null = no upper limit.
  final int? maxBytes, maxMs;

  static const defaults = TrackFilter();

  /// SQL condition for `tracks t` (custom selects).
  String get sql => [
        't.is_missing = 0',
        't.file_size >= $minBytes',
        if (maxBytes != null) 't.file_size <= $maxBytes',
        't.duration_ms >= $minMs',
        if (maxMs != null) 't.duration_ms <= $maxMs',
      ].join(' AND ');

  @override
  bool operator ==(Object other) =>
      other is TrackFilter &&
      other.minBytes == minBytes &&
      other.maxBytes == maxBytes &&
      other.minMs == minMs &&
      other.maxMs == maxMs;

  @override
  int get hashCode => Object.hash(minBytes, maxBytes, minMs, maxMs);
}

class ScanFolder {
  const ScanFolder({required this.id, required this.path, required this.enabled});
  final int id;
  final String path;
  final bool enabled;
}

abstract interface class LibraryRepository {
  /// Tracks that aren't missing. Sort + LIKE search (title/artist/album).
  Stream<List<Track>> watchTracks({TrackSort sort = TrackSort.recentlyAdded, String query = ''});

  Stream<List<Track>> watchRecentlyAdded({int limit = 10});

  Stream<LibraryStats> watchStats();

  Stream<List<Track>> watchFavorites();
  Stream<Set<int>> watchFavoriteIds();
  Future<void> toggleFavorite(int trackId);

  Future<Track?> getTrack(int id);

  /// By file path (Open with Nocturne: is the file already in the library?).
  Future<Track?> getTrackByPath(String path);

  /// Same name + size (the file picker's cache copy doesn't give the original path) —
  /// so the same file isn't copied twice.
  Future<Track?> findTrackByFile(String fileName, int size);

  /// Deletes the file from the phone (may need system confirmation) and removes it from the DB.
  /// false = not deleted (declined / no permission).
  Future<bool> deleteTrack(int id);

  /// Bulk delete: on Android 11+ **one** system dialog for all files.
  /// Returns the track ids actually deleted (declined → empty or partial).
  Future<Set<int>> deleteTracks(List<int> ids);

  /// Bulk favorite: [value] true → add all, false → remove all.
  Future<void> setFavorites(List<int> trackIds, bool value);

  /// File failed to open (deleted outside the app): hide it from lists. The next scan
  /// shows it again if the file is back.
  Future<void> markMissing(int id);

  Stream<List<ScanFolder>> watchScanFolders();
  Future<void> addScanFolder(String path);
  Future<void> removeScanFolder(int id);
  Future<void> setScanFolderEnabled(int id, bool enabled);

  /// scan_state key/value (lastScanAt, autoScan ...)
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
  Stream<String?> watchSetting(String key);
}
