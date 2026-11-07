import '../../domain/entities/lyrics.dart';

/// LRC: "[01:12.40] text". A line can carry several times ("[00:10][01:30] chorus"),
/// "[offset:+250]" shifts every line (ms, + = earlier), other "[ar:...]" tags are ignored.
/// No timed lines → empty list (the text is plain lyrics).
List<LyricLine> parseLrc(String text) {
  var offsetMs = 0;
  final out = <LyricLine>[];
  for (final raw in text.split(RegExp(r'\r?\n|\r'))) {
    final line = raw.trim();
    final offset = _offset.firstMatch(line);
    if (offset != null) {
      offsetMs = int.tryParse(offset.group(1)!.replaceAll('+', '')) ?? 0;
      continue;
    }
    final times = <Duration>[];
    // An index, not a shrinking copy of the line: lyrics come from outside, and a line
    // of a million time stamps must not take minutes.
    var pos = 0;
    while (true) {
      final m = _stamp.matchAsPrefix(line, pos);
      if (m == null) break;
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final frac = m.group(3);
      // ".4" = 400 ms, ".40" = 400 ms, ".400" = 400 ms
      final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0').substring(0, 3));
      times.add(Duration(minutes: min, seconds: sec, milliseconds: ms));
      pos = m.end;
      while (pos < line.length && line[pos].trim().isEmpty) {
        pos++;
      }
    }
    if (times.isEmpty) continue;
    final words = line.substring(pos);
    for (final t in times) {
      final shifted = t - Duration(milliseconds: offsetMs);
      out.add(LyricLine(shifted.isNegative ? Duration.zero : shifted, words));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offset = RegExp(r'^\[offset:\s*([+-]?\d+)\]$', caseSensitive: false);
