import 'package:drift/drift.dart';

// Row class names carry a *Row suffix so they don't clash with domain
// entities (Track, Playlist ...).

/// Every audio file in the library.
@DataClassName('TrackRow')
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text()();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get trackNo => integer().nullable()();
  IntColumn get discNo => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// AudioFormat.name
  TextColumn get format => text()();
  IntColumn get bitrateKbps => integer().nullable()();
  IntColumn get sampleRateHz => integer().nullable()();
  IntColumn get bitDepth => integer().nullable()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();

  /// File name in the cover cache (md5.jpg); null = no cover
  TextColumn get coverHash => text().nullable()();

  /// epoch ms
  IntColumn get dateAdded => integer()();
  IntColumn get dateModified => integer()();

  /// REPLAYGAIN_TRACK_GAIN dB (v2)
  RealColumn get replayGainDb => real().nullable()();

  /// true when the file isn't found during prune — not deleted, so playlists/favs don't break.
  BoolColumn get isMissing => boolean().withDefault(const Constant(false))();
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get coverHash => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

@DataClassName('PlaylistTrackRow')
class PlaylistTracks extends Table {
  IntColumn get playlistId => integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

@DataClassName('FavoriteRow')
class Favorites extends Table {
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {trackId};
}

@DataClassName('PlayHistoryRow')
class PlayHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get playedAt => integer()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
}

/// Key/value: lastScanAt, lastScanTrackCount, autoScan ...
@DataClassName('ScanStateRow')
class ScanState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Smart groups: result of the YAMNet audio analysis, one row per song (v3).
@DataClassName('TrackAnalysisRow')
class TrackAnalyses extends Table {
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();

  /// kVibeAnalysisVersion — bumped when the algorithm changes; old rows are re-analyzed.
  IntColumn get version => integer()();

  /// JSON {"Sad music": 0.012, ...}; null = analysis failed (corrupt file etc.)
  TextColumn get scores => text().nullable()();
  RealColumn get rmsDb => real().nullable()();
  IntColumn get analyzedAt => integer()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Smart groups: the user's answer in the "Check groups" screen (v4).
/// Used both as a correction (overrides the groups) and to measure accuracy —
/// the prediction at answer time is stored too.
@DataClassName('VibeLabelRow')
class VibeLabels extends Table {
  IntColumn get trackId => integer().references(Tracks, #id, onDelete: KeyAction.cascade)();

  /// Mood.name / Genre.name; 'none' = belongs to no mood/genre group
  TextColumn get mood => text()();
  TextColumn get genre => text()();
  TextColumn get predictedMood => text()();
  TextColumn get predictedGenre => text()();
  IntColumn get labeledAt => integer()();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// Scan folders chosen by the user.
@DataClassName('ScanFolderRow')
class ScanFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}
