import '../../core/utils/shared_storage.dart';
import 'dart:convert';

import '../../domain/repositories/settings_repository.dart';

typedef BackupFavorite = ({String path, int addedAt});
typedef BackupPlaylist = ({String name, String description, int createdAt, int updatedAt, List<String> tracks});
typedef BackupPlay = ({String path, int playedAt, bool completed, int positionMs});
typedef BackupFolder = ({String path, bool enabled});
typedef BackupLabel = ({
  String path,
  String mood,
  String genre,
  String predictedMood,
  String predictedGenre,
  int labeledAt,
});
typedef BackupArtist = ({String path, String artist});

/// The content of a backup file, typed and checked.
///
/// A backup comes from outside the app: it may be corrupt, edited or made by someone else.
/// So nothing is believed: a value of the wrong type or range makes [parse] throw
/// [FormatException] before anything reaches the database. Sections and optional fields that
/// are missing are fine (older backups don't have them).
class BackupFile {
  const BackupFile({
    this.favorites = const [],
    this.playlists = const [],
    this.history = const [],
    this.settings = const {},
    this.scanFolders = const [],
    this.vibeLabels = const [],
    this.artists = const [],
  });

  static const format = 'sonar-backup';

  /// Still 1: sections and settings only get added, and an older app skips what it doesn't know.
  static const version = 1;

  /// scan_state keys carried over from Settings (not the scan's internal keys).
  static const settingKeys = SettingsKeys.backedUp;

  /// Read as numbers by the app; an empty text means "no limit" for the filter.
  static const _numberSettings = {
    SettingsKeys.filterMinBytes,
    SettingsKeys.filterMaxBytes,
    SettingsKeys.filterMinMs,
    SettingsKeys.filterMaxMs,
    SettingsKeys.forgottenMinPlays,
    SettingsKeys.forgottenDays,
  };

  static const _maxPath = 4096;
  static const _maxName = 1000;
  static const _maxDescription = 10000;
  static const _maxLabel = 64;
  static const _maxSetting = 64 * 1024;

  /// The latest date DateTime can hold. A later one still looks like a number here, then breaks
  /// every screen that shows it, for good: a restore merges, so it can't be taken back.
  static const _maxDate = 8640000000000000;

  /// A year. More than any play, and all the plays a file can hold still add up without overflow.
  static const _maxPositionMs = 365 * 24 * 60 * 60 * 1000;

  final List<BackupFavorite> favorites;
  final List<BackupPlaylist> playlists;
  final List<BackupPlay> history;
  final Map<String, String> settings;
  final List<BackupFolder> scanFolders;
  final List<BackupLabel> vibeLabels;

  /// The artist names the user typed (Edit artist).
  final List<BackupArtist> artists;

  bool get isEmpty =>
      favorites.isEmpty &&
      playlists.isEmpty &&
      history.isEmpty &&
      settings.isEmpty &&
      scanFolders.isEmpty &&
      vibeLabels.isEmpty &&
      artists.isEmpty;

  /// The same layout [parse] reads (the songs part: what waits for a song to turn up).
  String encodeSongs() => jsonEncode({
        'format': format,
        'version': version,
        'favorites': [for (final f in favorites) {'path': f.path, 'addedAt': f.addedAt}],
        'playlists': [
          for (final p in playlists)
            {
              'name': p.name,
              'description': p.description,
              'createdAt': p.createdAt,
              'updatedAt': p.updatedAt,
              'tracks': p.tracks,
            },
        ],
        'history': [
          for (final h in history)
            {'path': h.path, 'playedAt': h.playedAt, 'completed': h.completed, 'positionMs': h.positionMs},
        ],
        'vibeLabels': [
          for (final l in vibeLabels)
            {
              'path': l.path,
              'mood': l.mood,
              'genre': l.genre,
              'predictedMood': l.predictedMood,
              'predictedGenre': l.predictedGenre,
              'labeledAt': l.labeledAt,
            },
        ],
      });

  static BackupFile parse(String json) {
    // Text editors on Windows put a BOM in front when the file is saved
    final Object? root = jsonDecode(json.startsWith('\uFEFF') ? json.substring(1) : json);
    if (root is! Map<String, Object?> || root['format'] != format) {
      throw const FormatException('Not a Nocturne backup file');
    }
    final saved = root['version'] ?? version;
    if (saved is! int || saved < 1 || saved > version) {
      throw const FormatException('Unsupported backup version');
    }
    return BackupFile(
      favorites: [for (final e in _list(root, 'favorites')) _favorite(_object(e))],
      playlists: [for (final e in _list(root, 'playlists')) _playlist(_object(e))],
      history: [for (final e in _list(root, 'history')) _play(_object(e))],
      settings: _settings(root['settings']),
      scanFolders: [
        for (final e in _list(root, 'scanFolders'))
          if (_folder(_object(e)) case final folder when isSharedStoragePath(folder.path)) folder,
      ],
      vibeLabels: [for (final e in _list(root, 'vibeLabels')) _label(_object(e))],
      artists: [for (final e in _list(root, 'artistOverrides')) _artist(_object(e))],
    );
  }

  static BackupFavorite _favorite(Map<String, Object?> m) =>
      (path: _text(m, 'path', _maxPath), addedAt: _date(m, 'addedAt'));

  static BackupPlaylist _playlist(Map<String, Object?> m) => (
        name: _name(m),
        description: _cut(m, 'description', _maxDescription, orElse: ''),
        createdAt: _date(m, 'createdAt'),
        updatedAt: _date(m, 'updatedAt'),
        tracks: [
          for (final t in _list(m, 'tracks'))
            if (t is String && t.length <= _maxPath) t else throw const FormatException('Bad playlist track'),
        ],
      );

  static BackupPlay _play(Map<String, Object?> m) => (
        path: _text(m, 'path', _maxPath),
        playedAt: _date(m, 'playedAt'),
        completed: _flag(m, 'completed', orElse: false),
        positionMs: _count(m, 'positionMs', _maxPositionMs, orElse: 0),
      );

  static BackupFolder _folder(Map<String, Object?> m) =>
      (path: _text(m, 'path', _maxPath), enabled: _flag(m, 'enabled', orElse: true));

  static BackupLabel _label(Map<String, Object?> m) => (
        path: _text(m, 'path', _maxPath),
        mood: _text(m, 'mood', _maxLabel),
        genre: _text(m, 'genre', _maxLabel),
        predictedMood: _text(m, 'predictedMood', _maxLabel),
        predictedGenre: _text(m, 'predictedGenre', _maxLabel),
        labeledAt: _date(m, 'labeledAt'),
      );

  static BackupArtist _artist(Map<String, Object?> m) {
    final artist = _cut(m, 'artist', _maxName);
    if (artist.trim().isEmpty) throw const FormatException('Bad value for artist');
    return (path: _text(m, 'path', _maxPath), artist: artist);
  }

  /// The app never lets a playlist have a blank name, and nobody could pick one from a list.
  static String _name(Map<String, Object?> m) {
    final name = _cut(m, 'name', _maxName);
    if (name.trim().isEmpty) throw const FormatException('Bad value for name');
    return name;
  }

  /// Only [settingKeys], and only text. Anything else in there is ignored.
  static Map<String, String> _settings(Object? value) {
    if (value == null) return const {};
    final out = <String, String>{};
    for (final MapEntry(:key, value: v) in _object(value).entries) {
      if (!settingKeys.contains(key) || v is! String) continue;
      if (v.length > _maxSetting) throw const FormatException('Setting too long');
      if (_numberSettings.contains(key) && !_isNumberOrEmpty(v)) continue;
      out[key] = v;
    }
    return out;
  }

  static bool _isNumberOrEmpty(String s) => s.isEmpty || (int.tryParse(s) ?? -1) >= 0;

  static Map<String, Object?> _object(Object? value) =>
      value is Map<String, Object?> ? value : throw const FormatException('Expected an object');

  static List<Object?> _list(Map<String, Object?> m, String key) => switch (m[key]) {
        null => const [],
        final List<Object?> list => list,
        _ => throw FormatException('$key is not a list'),
      };

  static String _text(Map<String, Object?> m, String key, int maxLength, {String? orElse}) {
    final value = m[key] ?? orElse;
    if (value is String && value.length <= maxLength) return value;
    throw FormatException('Bad value for $key');
  }

  /// Names and descriptions the user typed: a longer one is cut to [maxLength], not refused.
  /// Older versions took a pasted name of any length, and one such playlist made the whole
  /// backup (the monthly one too) unreadable.
  static String _cut(Map<String, Object?> m, String key, int maxLength, {String? orElse}) {
    final value = m[key] ?? orElse;
    if (value is! String) throw FormatException('Bad value for $key');
    if (value.length <= maxLength) return value;
    // Not between the two halves of an emoji
    final end = (value.codeUnitAt(maxLength - 1) & 0xFC00) == 0xD800 ? maxLength - 1 : maxLength;
    return value.substring(0, end);
  }

  static int _date(Map<String, Object?> m, String key) => _count(m, key, _maxDate);

  /// Dates and positions: whole numbers from 0 to [max].
  static int _count(Map<String, Object?> m, String key, int max, {int? orElse}) {
    final value = m[key] ?? orElse;
    if (value is int && value >= 0 && value <= max) return value;
    throw FormatException('Bad value for $key');
  }

  static bool _flag(Map<String, Object?> m, String key, {required bool orElse}) {
    final value = m[key] ?? orElse;
    if (value is bool) return value;
    throw FormatException('Bad value for $key');
  }
}
