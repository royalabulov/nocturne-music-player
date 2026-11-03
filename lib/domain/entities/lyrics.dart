/// One timed line of synced lyrics.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

enum LyricsSource { file, lrclib }

/// Lyrics of one song: synced lines (karaoke-style) or plain text.
class Lyrics {
  const Lyrics({required this.source, this.lines = const [], this.plain, this.instrumental = false});

  final LyricsSource source;

  /// Synced lines, by time. Empty → only [plain].
  final List<LyricLine> lines;
  final String? plain;

  /// LRCLIB knows the song and says it has no words.
  final bool instrumental;

  bool get synced => lines.isNotEmpty;
}

enum LyricsStatus {
  found,

  /// Looked everywhere allowed — nothing.
  notFound,

  /// Nothing local; the internet would be needed but Online mode is off.
  needsOnline,

  /// Nothing local; online search is turned off in Settings.
  onlineSearchOff,

  /// Server busy / no connection — worth trying again.
  error,
}

class LyricsResult {
  const LyricsResult(this.status, [this.lyrics]);
  const LyricsResult.found(Lyrics this.lyrics) : status = LyricsStatus.found;

  final LyricsStatus status;
  final Lyrics? lyrics;
}

/// Index of the line being sung at [pos]: the last line that started. -1 before the first.
int activeLyricLine(List<LyricLine> lines, Duration pos) {
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= pos) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
