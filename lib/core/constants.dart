/// Largest text scale the layout supports.
const kMaxTextScale = 1.5;

/// Bump when TagReader logic changes → the next scan re-reads every file's tags
/// (unchanged files too). v2: UTF-16 BOM fix. v3: ReplayGain.
/// v4: Ü/Ø/ß loss (doubled BOM) — frames read straight from bytes; ReplayGain regex fix.
/// v5: v4's check didn't see FFFD (it looked after the byte swap).
/// v6: no artist → taken from an "Artist - Title" name (guessArtist), "- Topic" cleaned.
/// v7: quoted names aren't split, a "01 " track number is dropped.
/// v8: "- Topic" is cleaned from album names too.
const kTagReaderVersion = 8;

/// Version of the smart-groups audio analysis (Kotlin AudioAnalyzer + stored
/// classes). When it goes up, every song is re-analyzed in the background.
/// v2: 3×10 s segments (with low-pass) + tempo, major/minor, brightness.
const kVibeAnalysisVersion = 2;

/// Version shown in Settings (keep in sync with pubspec.yaml).
const kAppVersion = '1.0.1';
