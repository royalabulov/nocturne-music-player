import '../data/datasources/tag_reader.dart';
import '../domain/entities/track.dart';
import '../l10n/l10n.dart';

/// Album artist when an album has songs by several artists.
const kVariousArtists = 'Various Artists';

/// Names the app makes up itself are stored in English ("Unknown Artist") —
/// grouping and sorting compare against them. Only what's on screen is
/// translated: one string compare per visible row.
String displayName(String stored) => switch (stored) {
      TagReader.unknownArtist => l10n.unknownArtist,
      TagReader.unknownAlbum => l10n.unknownAlbum,
      kVariousArtists => l10n.variousArtists,
      _ => stored,
    };

extension TrackDisplayNames on Track {
  String get artistLabel => displayName(artist);
  String get albumLabel => displayName(album);
}
