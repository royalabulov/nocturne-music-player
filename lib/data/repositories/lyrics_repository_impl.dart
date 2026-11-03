import 'package:drift/drift.dart';

import '../../domain/entities/lyrics.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../datasources/lrc_parser.dart';
import '../datasources/lrclib_source.dart';
import '../datasources/lyrics_file_source.dart';
import '../datasources/tag_reader.dart';
import '../db/app_database.dart';

class LyricsRepositoryImpl implements LyricsRepository {
  LyricsRepositoryImpl(
    this._db, {
    this._files = const LyricsFileSource(),
    LrclibSource? lrclib,
    DateTime Function()? now,
  })  : _lrclib = lrclib ?? LrclibSource(),
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final LyricsFileSource _files;
  final LrclibSource _lrclib;
  final DateTime Function() _now;

  /// LRCLIB had nothing → don't ask again for this long (the database grows).
  static const askAgainAfter = Duration(days: 7);

  @override
  Future<LyricsResult> load(
    Track track, {
    required bool online,
    required bool onlineSearch,
    bool force = false,
    bool Function()? isCancelled,
  }) async {
    final local = await _files.read(track.path);
    if (local != null) return LyricsResult.found(local);

    final row = await (_db.select(_db.trackLyrics)..where((r) => r.trackId.equals(track.id))).getSingleOrNull();
    if (row != null && row.found) return LyricsResult.found(_fromRow(row));
    final askedRecently =
        row != null && _now().millisecondsSinceEpoch - row.fetchedAt < askAgainAfter.inMilliseconds;
    if (askedRecently && !force) return const LyricsResult(LyricsStatus.notFound);

    if (!onlineSearch) return const LyricsResult(LyricsStatus.onlineSearchOff);
    if (!online) return const LyricsResult(LyricsStatus.needsOnline);

    final answer = await _lrclib.find(
      // "YA İNDİ_ YA HEÇ VAXT": downloaders put "_" where the name had a comma
      title: track.title.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
      artist: track.artist == TagReader.unknownArtist ? null : firstArtist(track.artist),
      duration: track.duration,
      isCancelled: isCancelled,
    );
    switch (answer) {
      case LrclibFound():
        await _save(track.id, found: true, synced: answer.synced, plain: answer.plain, instrumental: answer.instrumental);
        return LyricsResult.found(answer.toLyrics());
      case LrclibNotFound():
        await _save(track.id, found: false);
        return const LyricsResult(LyricsStatus.notFound);
      case LrclibFailed():
        return const LyricsResult(LyricsStatus.error);
    }
  }

  Future<void> _save(int trackId, {required bool found, String? synced, String? plain, bool instrumental = false}) =>
      _db.into(_db.trackLyrics).insertOnConflictUpdate(TrackLyricsCompanion.insert(
            trackId: Value(trackId),
            found: found,
            synced: Value(synced),
            plain: Value(plain),
            instrumental: Value(instrumental),
            fetchedAt: _now().millisecondsSinceEpoch,
          ));

  static Lyrics _fromRow(LyricsRow r) => Lyrics(
        source: LyricsSource.lrclib,
        lines: r.synced == null ? const [] : parseLrc(r.synced!),
        plain: r.plain,
        instrumental: r.instrumental,
      );

  /// "Paster x OD", "Artz × Bugy", "OGB feat. Xpert" → "Paster", "Artz", "OGB".
  /// "&" and "," stay ("Simon & Garfunkel", "Tyler, The Creator").
  /// LRCLIB lists the main artist; the full string rarely matches.
  static String firstArtist(String artist) {
    final first = artist.split(_join).first.trim();
    return first.isEmpty ? artist.trim() : first;
  }

  static final _join = RegExp(r'\s*×\s*|\s+[xX]\s+|\s+(?:feat|ft)\.?\s+', caseSensitive: false);
}
