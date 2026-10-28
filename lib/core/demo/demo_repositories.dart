import 'dart:math';

import 'package:rxdart/rxdart.dart';

import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/playlist_repository.dart';
import 'demo_library.dart';

/// Web demo: no DB, everything in memory. All streams come from BehaviorSubject
/// → same behaviour as the real repo (UI updates on change).
class DemoLibraryRepository implements LibraryRepository {
  DemoLibraryRepository() : _tracks = BehaviorSubject.seeded(DemoLibrary.tracks());

  final BehaviorSubject<List<Track>> _tracks;
  final _favorites = BehaviorSubject<Set<int>>.seeded({3, 7, 12, 18, 1, 25, 31});
  final _folders = BehaviorSubject<List<ScanFolder>>.seeded(const [
    ScanFolder(id: 1, path: '/storage/emulated/0/Music', enabled: true),
    ScanFolder(id: 2, path: '/storage/emulated/0/Download', enabled: true),
    ScanFolder(id: 3, path: '/storage/emulated/0/snaptube/download', enabled: true),
    ScanFolder(id: 4, path: '/storage/emulated/0/Telegram/Telegram Audio', enabled: false),
  ]);
  final _settings = BehaviorSubject<Map<String, String>>.seeded({
    'lastScanAt': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
  });

  List<Track> get all => _tracks.value;

  @override
  Stream<List<Track>> watchTracks({TrackSort sort = TrackSort.recentlyAdded, String query = ''}) =>
      _tracks.map((list) {
        final q = query.trim().toLowerCase();
        final out = [
          for (final t in list)
            if (q.isEmpty ||
                t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q) ||
                t.album.toLowerCase().contains(q))
              t,
        ];
        switch (sort) {
          case TrackSort.recentlyAdded:
            out.sort((a, b) => (b.dateAdded ?? DateTime(0)).compareTo(a.dateAdded ?? DateTime(0)));
          case TrackSort.title:
            out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
          case TrackSort.artist:
            out.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
          case TrackSort.album:
            out.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
          case TrackSort.longest:
            out.sort((a, b) => b.duration.compareTo(a.duration));
          case TrackSort.shortest:
            out.sort((a, b) => a.duration.compareTo(b.duration));
        }
        return out;
      });

  @override
  Stream<List<Track>> watchRecentlyAdded({int limit = 10}) =>
      watchTracks().map((l) => l.take(limit).toList());

  @override
  Stream<LibraryStats> watchStats() => _tracks.map((l) => LibraryStats(
        trackCount: l.length,
        totalDuration: l.fold(Duration.zero, (a, t) => a + t.duration),
        losslessCount: l.where((t) => t.format.isLossless).length,
        maxSampleRateHz: l.fold(0, (a, t) => max(a, t.sampleRateHz ?? 0)),
        maxBitDepth: l.fold(0, (a, t) => max(a, t.bitDepth ?? 0)),
        lastScanAt: DateTime.tryParse(_settings.value['lastScanAt'] ?? ''),
      ));

  @override
  Stream<List<Track>> watchFavorites() => Rx.combineLatest2(
        _tracks,
        _favorites,
        (List<Track> l, Set<int> f) => [for (final t in l) if (f.contains(t.id)) t],
      );

  @override
  Stream<Set<int>> watchFavoriteIds() => _favorites.stream;

  @override
  Future<void> toggleFavorite(int trackId) async {
    final f = {..._favorites.value};
    f.contains(trackId) ? f.remove(trackId) : f.add(trackId);
    _favorites.add(f);
  }

  @override
  Future<Track?> getTrack(int id) async => _tracks.value.where((t) => t.id == id).firstOrNull;

  @override
  Future<Track?> getTrackByPath(String path) async => _tracks.value.where((t) => t.path == path).firstOrNull;

  @override
  Future<Track?> findTrackByFile(String fileName, int size) async =>
      _tracks.value.where((t) => t.fileSize == size && t.path.endsWith('/$fileName')).firstOrNull;

  @override
  Future<void> markMissing(int id) async {}

  @override
  Future<bool> deleteTrack(int id) async {
    _tracks.add([for (final t in _tracks.value) if (t.id != id) t]);
    return true;
  }

  @override
  Future<Set<int>> deleteTracks(List<int> ids) async {
    final set = ids.toSet();
    _tracks.add([for (final t in _tracks.value) if (!set.contains(t.id)) t]);
    return set;
  }

  @override
  Future<void> setFavorites(List<int> trackIds, bool value) async {
    final f = {..._favorites.value};
    value ? f.addAll(trackIds) : f.removeAll(trackIds);
    _favorites.add(f);
  }

  @override
  Stream<List<ScanFolder>> watchScanFolders() => _folders.stream;

  @override
  Future<void> addScanFolder(String path) async {
    final id = _folders.value.map((f) => f.id).fold(0, max) + 1;
    _folders.add([..._folders.value, ScanFolder(id: id, path: path, enabled: true)]);
  }

  @override
  Future<void> removeScanFolder(int id) async =>
      _folders.add([for (final f in _folders.value) if (f.id != id) f]);

  @override
  Future<void> setScanFolderEnabled(int id, bool enabled) async => _folders.add([
        for (final f in _folders.value)
          f.id == id ? ScanFolder(id: f.id, path: f.path, enabled: enabled) : f,
      ]);

  @override
  Future<String?> getSetting(String key) async => _settings.value[key];

  @override
  Future<void> setSetting(String key, String value) async =>
      _settings.add({..._settings.value, key: value});

  @override
  Stream<String?> watchSetting(String key) => _settings.map((m) => m[key]).distinct();
}

class DemoHistoryRepository implements HistoryRepository {
  DemoHistoryRepository(this._lib) {
    _resume.add(ResumePoint(track: _lib.all[6], position: const Duration(minutes: 1, seconds: 42)));
  }

  final DemoLibraryRepository _lib;
  final _plays = BehaviorSubject<List<(int, DateTime)>>.seeded(DemoLibrary.history());
  final _resume = BehaviorSubject<ResumePoint?>.seeded(null);

  Track? _track(int id) => _lib.all.where((t) => t.id == id).firstOrNull;

  @override
  Future<void> recordPlay(int trackId) async =>
      _plays.add([..._plays.value, (trackId, DateTime.now())]);

  /// id → (count, lastPlayed, score)
  Map<int, (int, DateTime, double)> _agg(List<(int, DateTime)> plays) {
    final now = DateTime.now();
    final m = <int, (int, DateTime, double)>{};
    for (final (id, at) in plays) {
      final days = now.difference(at).inMinutes / (60 * 24);
      final prev = m[id] ?? (0, DateTime(0), 0.0);
      m[id] = (
        prev.$1 + 1,
        at.isAfter(prev.$2) ? at : prev.$2,
        prev.$3 + exp(-days / 14),
      );
    }
    return m;
  }

  List<PlayedTrack> _list(
    List<(int, DateTime)> plays,
    Comparable<Object> Function((int, DateTime, double) v) key,
    int limit,
  ) {
    final entries = _agg(plays).entries.toList()..sort((a, b) => key(b.value).compareTo(key(a.value)));
    return [
      for (final e in entries.take(limit))
        if (_track(e.key) case final t?)
          PlayedTrack(track: t, playCount: e.value.$1, lastPlayedAt: e.value.$2),
    ];
  }

  @override
  Stream<List<PlayedTrack>> watchRecentlyPlayed({int limit = 50}) =>
      _plays.map((p) => _list(p, (v) => v.$2, limit));

  @override
  Stream<List<PlayedTrack>> watchMostPlayed({int limit = 50}) =>
      _plays.map((p) => _list(p, (v) => v.$1, limit));

  @override
  Stream<List<PlayedTrack>> watchRecommended({int limit = 10}) =>
      _plays.map((p) => _list(p, (v) => v.$3, limit));

  @override
  Stream<WeekStats> watchWeekStats() => _plays.map((p) {
        final since = DateTime.now().subtract(const Duration(days: 7));
        var plays = 0;
        var listened = Duration.zero;
        for (final (id, at) in p) {
          if (at.isBefore(since)) continue;
          plays++;
          listened += _track(id)?.duration ?? Duration.zero;
        }
        return WeekStats(plays: plays, listened: listened);
      });

  @override
  Future<void> saveResumePoint(int trackId, Duration position) async {
    final t = _track(trackId);
    if (t != null) _resume.add(ResumePoint(track: t, position: position));
  }

  @override
  Stream<ResumePoint?> watchResumePoint() => _resume.stream;
}

class _Pl {
  _Pl(this.id, this.name, this.description, this.trackIds, this.updatedAt);
  final int id;
  String name, description;
  List<int> trackIds;
  DateTime updatedAt;
}

class DemoPlaylistRepository implements PlaylistRepository {
  DemoPlaylistRepository(this._lib) {
    var i = 0;
    _pls.add([
      for (final (name, desc, ids) in DemoLibrary.playlists)
        _Pl(++i, name, desc, [...ids], DateTime.now().subtract(Duration(days: i * 2))),
    ]);
  }

  final DemoLibraryRepository _lib;
  final _pls = BehaviorSubject<List<_Pl>>.seeded(const []);

  Track? _track(int id) => _lib.all.where((t) => t.id == id).firstOrNull;

  Playlist _toEntity(_Pl p) {
    final tracks = [for (final id in p.trackIds) ?_track(id)];
    return Playlist(
      id: p.id,
      name: p.name,
      description: p.description,
      trackCount: tracks.length,
      totalDuration: tracks.fold(Duration.zero, (a, t) => a + t.duration),
      updatedAt: p.updatedAt,
      coverPath: tracks.firstOrNull?.coverPath,
    );
  }

  void _mutate(int id, void Function(_Pl p) f) {
    final list = [..._pls.value];
    final p = list.where((p) => p.id == id).firstOrNull;
    if (p == null) return;
    f(p);
    p.updatedAt = DateTime.now();
    _pls.add(list);
  }

  @override
  Stream<List<Playlist>> watchPlaylists() => _pls.map((l) {
        final out = l.map(_toEntity).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return out;
      });

  @override
  Stream<Playlist?> watchPlaylist(int id) => _pls.map((l) {
        final p = l.where((p) => p.id == id).firstOrNull;
        return p == null ? null : _toEntity(p);
      });

  @override
  Stream<List<Track>> watchTracks(int playlistId) => _pls.map((l) {
        final p = l.where((p) => p.id == playlistId).firstOrNull;
        if (p == null) return const <Track>[];
        return [for (final id in p.trackIds) ?_track(id)];
      });

  @override
  Stream<Set<int>> watchPlaylistIdsContaining(int trackId) =>
      _pls.map((l) => {for (final p in l) if (p.trackIds.contains(trackId)) p.id});

  @override
  Future<int> create(String name, {String description = ''}) async {
    final id = _pls.value.map((p) => p.id).fold(0, max) + 1;
    _pls.add([..._pls.value, _Pl(id, name, description, [], DateTime.now())]);
    return id;
  }

  @override
  Future<void> rename(int id, String name, {String? description}) async => _mutate(id, (p) {
        p.name = name;
        if (description != null) p.description = description;
      });

  @override
  Future<void> delete(int id) async => _pls.add([for (final p in _pls.value) if (p.id != id) p]);

  @override
  Future<void> addTracks(int playlistId, List<int> trackIds) async => _mutate(playlistId, (p) {
        for (final id in trackIds) {
          if (!p.trackIds.contains(id)) p.trackIds.add(id);
        }
      });

  @override
  Future<void> removeTrack(int playlistId, int trackId) async =>
      _mutate(playlistId, (p) => p.trackIds.remove(trackId));

  @override
  Future<void> reorder(int playlistId, int oldIndex, int newIndex) async => _mutate(playlistId, (p) {
        // newIndex = final position (same semantics as the real repo)
        final item = p.trackIds.removeAt(oldIndex);
        p.trackIds.insert(newIndex.clamp(0, p.trackIds.length), item);
      });
}

/// Web demo: fixed (seeded) fake YAMNet scores and a genre tag for every demo
/// song — so the Smart groups UI shows without real analysis.
class DemoAnalysisRepository implements AnalysisRepository {
  DemoAnalysisRepository(this.lib);
  final DemoLibraryRepository lib;
  final _labels = BehaviorSubject<Map<int, VibeLabel>>.seeded(const {});

  @override
  Future<void> saveLabel(VibeLabel l) async => _labels.add({..._labels.value, l.trackId: l});

  @override
  Future<void> deleteLabel(int trackId) async => _labels.add({..._labels.value}..remove(trackId));

  @override
  Stream<List<VibeLabel>> watchLabels() => _labels.map((m) => m.values.toList());

  static const _genreTags = ['Hip-Hop', 'Pop', 'Rock', 'Electronic', 'Jazz', null, 'Muğam', null];
  static const _moodClasses = ['Sad music', 'Tender music', 'Happy music', 'Exciting music'];

  List<TrackVibeData> _build(List<Track> tracks) => [
        for (final t in tracks)
          () {
            final rnd = Random(t.id);
            final scores = <String, double>{
              'Music': .8,
              for (final c in _moodClasses) c: rnd.nextDouble() * .01,
              'Pop music': rnd.nextDouble() * .1,
            };
            // Give every song one clear mood
            scores[_moodClasses[t.id % _moodClasses.length]] = .05 + rnd.nextDouble() * .1;
            return TrackVibeData(
              trackId: t.id,
              genreTag: _genreTags[t.id % _genreTags.length],
              scores: scores,
              rmsDb: -20 + rnd.nextDouble() * 10,
            );
          }(),
      ];

  @override
  Future<List<PendingAnalysis>> pending(int version, {int limit = 20}) async => const [];

  @override
  Future<void> save(int trackId, int version, {Map<String, double>? scores, double? rmsDb}) async {}

  @override
  Stream<List<TrackVibeData>> watchVibeData() => lib.watchTracks().map(_build);

  @override
  Stream<AnalysisProgress> watchProgress(int version) =>
      lib.watchTracks().map((l) => AnalysisProgress(done: l.length, total: l.length));
}
