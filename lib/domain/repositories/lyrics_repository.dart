import '../entities/lyrics.dart';
import '../entities/track.dart';

abstract interface class LyricsRepository {
  /// The song file first, then saved LRCLIB answers, then LRCLIB itself —
  /// only when [online] (Online mode is on) and [onlineSearch] (Settings) allow it.
  /// [force]: ask LRCLIB again even if it recently had nothing.
  /// [isCancelled]: the song changed meanwhile — don't keep asking the server.
  Future<LyricsResult> load(
    Track track, {
    required bool online,
    required bool onlineSearch,
    bool force = false,
    bool Function()? isCancelled,
  });
}
