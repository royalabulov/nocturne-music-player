import '../../domain/entities/audio_format.dart';
import '../../domain/entities/track.dart';
import '../datasources/cover_cache.dart';
import '../db/app_database.dart';

/// Drift row → domain entity.
class TrackMapper {
  const TrackMapper(this.covers);
  final CoverCache covers;

  Track toDomain(TrackRow r) => Track(
        id: r.id,
        path: r.path,
        title: r.title,
        artist: r.artist,
        album: r.album,
        duration: Duration(milliseconds: r.durationMs),
        format: AudioFormat.values.asNameMap()[r.format] ?? AudioFormat.unknown,
        bitrateKbps: r.bitrateKbps,
        sampleRateHz: r.sampleRateHz,
        bitDepth: r.bitDepth,
        coverPath: covers.pathFor(r.coverHash),
        dateAdded: DateTime.fromMillisecondsSinceEpoch(r.dateAdded),
        trackNo: r.trackNo,
        year: r.year,
        fileSize: r.fileSize,
        isMissing: r.isMissing,
        replayGainDb: r.replayGainDb,
      );

  List<Track> toDomainList(List<TrackRow> rows) => [for (final r in rows) toDomain(r)];
}
