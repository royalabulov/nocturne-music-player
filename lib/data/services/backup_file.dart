import 'dart:convert';

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
  });

  static const format = 'sonar-backup';
  static const version = 1;

  /// scan_state keys carried over from Settings (not the scan's internal keys).
  static const settingKeys = {'audioSettings', 'autoScan'};

  static const _maxPath = 4096;
  static const _maxName = 1000;
  static const _maxDescription = 10000;
  static const _maxLabel = 64;
  static const _maxSetting = 64 * 1024;

  final List<BackupFavorite> favorites;
  final List<BackupPlaylist> playlists;
  final List<BackupPlay> history;
  final Map<String, String> settings;
  final List<BackupFolder> scanFolders;
  final List<BackupLabel> vibeLabels;

  static BackupFile parse(String json) {
    final Object? root = jsonDecode(json);
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
          if (_folder(_object(e)) case final folder when _isSharedFolder(folder.path)) folder,
      ],
      vibeLabels: [for (final e in _list(root, 'vibeLabels')) _label(_object(e))],
    );
  }

  static BackupFavorite _favorite(Map<String, Object?> m) =>
      (path: _text(m, 'path', _maxPath), addedAt: _count(m, 'addedAt'));

  static BackupPlaylist _playlist(Map<String, Object?> m) => (
        name: _text(m, 'name', _maxName),
        description: _text(m, 'description', _maxDescription, orElse: ''),
        createdAt: _count(m, 'createdAt'),
        updatedAt: _count(m, 'updatedAt'),
        tracks: [
          for (final t in _list(m, 'tracks'))
            if (t is String && t.length <= _maxPath) t else throw const FormatException('Bad playlist track'),
        ],
      );

  static BackupPlay _play(Map<String, Object?> m) => (
        path: _text(m, 'path', _maxPath),
        playedAt: _count(m, 'playedAt'),
        completed: _flag(m, 'completed', orElse: false),
        positionMs: _count(m, 'positionMs', orElse: 0),
      );

  static BackupFolder _folder(Map<String, Object?> m) =>
      (path: _text(m, 'path', _maxPath), enabled: _flag(m, 'enabled', orElse: true));

  static BackupLabel _label(Map<String, Object?> m) => (
        path: _text(m, 'path', _maxPath),
        mood: _text(m, 'mood', _maxLabel),
        genre: _text(m, 'genre', _maxLabel),
        predictedMood: _text(m, 'predictedMood', _maxLabel),
        predictedGenre: _text(m, 'predictedGenre', _maxLabel),
        labeledAt: _count(m, 'labeledAt'),
      );

  /// Only [settingKeys], and only text. Anything else in there is ignored.
  static Map<String, String> _settings(Object? value) {
    if (value == null) return const {};
    final out = <String, String>{};
    for (final MapEntry(:key, value: v) in _object(value).entries) {
      if (!settingKeys.contains(key) || v is! String) continue;
      if (v.length > _maxSetting) throw const FormatException('Setting too long');
      out[key] = v;
    }
    return out;
  }

  /// A folder the scanner may walk: shared storage only. Others are dropped, not an error.
  static bool _isSharedFolder(String path) =>
      path.startsWith('/storage/') &&
      !path.split('/').contains('..') &&
      !path.contains('/Android/data/') &&
      !path.contains('/Android/obb/');

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

  /// Dates and positions: whole numbers from 0 up.
  static int _count(Map<String, Object?> m, String key, {int? orElse}) {
    final value = m[key] ?? orElse;
    if (value is int && value >= 0) return value;
    throw FormatException('Bad value for $key');
  }

  static bool _flag(Map<String, Object?> m, String key, {required bool orElse}) {
    final value = m[key] ?? orElse;
    if (value is bool) return value;
    throw FormatException('Bad value for $key');
  }
}
