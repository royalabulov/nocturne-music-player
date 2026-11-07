import 'audio_format.dart';

/// Names the app stores itself when a file has none. Grouping and sorting compare against
/// them; only what's on screen is translated (displayName).
const kUnknownArtist = 'Unknown Artist';
const kUnknownAlbum = 'Unknown Album';

/// Album artist when an album has songs by several artists.
const kVariousArtists = 'Various Artists';

/// One audio file in the library. Built from a Drift row by [TrackMapper].
class Track {
  const Track({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.format,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.coverPath,
    this.dateAdded,
    this.trackNo,
    this.year,
    this.fileSize = 0,
    this.isMissing = false,
    this.replayGainDb,
  });

  final int id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final AudioFormat format;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final String? coverPath;
  final DateTime? dateAdded;
  final int? trackNo;
  final int? year;
  final int fileSize;

  /// REPLAYGAIN_TRACK_GAIN (dB), if the tag has it.
  final double? replayGainDb;

  /// The file wasn't found on disk during the last scan.
  final bool isMissing;

  /// Codec chip text: "FLAC 24-BIT", "320KBPS MP3", "ALAC".
  String get qualityLabel {
    if (format.isLossless) {
      final depth = bitDepth;
      return depth != null ? '${format.label} $depth-BIT' : format.label;
    }
    final kbps = bitrateKbps;
    return kbps != null ? '${kbps}KBPS ${format.label}' : format.label;
  }
}
