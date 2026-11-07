import 'track.dart';

/// How names are compared: "Paster " and "paster" are the same.
String normalizeName(String s) => s.trim().toLowerCase();

/// "Artist feat. X" → "Artist": features don't create separate artists.
/// Names like "Simon & Garfunkel", "AC/DC" aren't split.
final _feat = RegExp(r'\s+[\(\[]?(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false);
String primaryArtist(String artist) {
  final s = artist.replaceFirst(_feat, '').trim();
  return s.isEmpty ? artist.trim() : s;
}

/// "PASTER × RZZA", "Paster x OD" → each name. Only "×" and a spaced "x" join
/// artists; "&" and "," stay ("Simon & Garfunkel", "Tyler, The Creator").
final _collab = RegExp(r'\s*×\s*|\s+[xX]\s+');
List<String> artistsOf(String artist) {
  final names = [
    for (final n in primaryArtist(artist).split(_collab))
      if (n.trim().isNotEmpty) n.trim(),
  ];
  return names.isEmpty ? [artist.trim()] : names;
}

String albumKeyOf(Track t) => normalizeName(t.album);

/// The first (main) artist — "Go to artist" opens this one.
String artistKeyOf(Track t) => normalizeName(artistsOf(t.artist).first);
Set<String> artistKeysOf(Track t) => {for (final n in artistsOf(t.artist)) normalizeName(n)};
