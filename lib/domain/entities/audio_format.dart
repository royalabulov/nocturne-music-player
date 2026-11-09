/// Supported audio formats. [label] is shown in the codec chip.
enum AudioFormat {
  flac('FLAC', isLossless: true),
  alac('ALAC', isLossless: true),
  wav('WAV', isLossless: true),
  aiff('AIFF', isLossless: true),
  ape('APE', isLossless: true),
  mp3('MP3'),
  aac('AAC'),
  ogg('OGG'),
  opus('OPUS'),
  unknown('?');

  const AudioFormat(this.label, {this.isLossless = false});

  final String label;
  final bool isLossless;

  /// From the file name alone. An .m4a is taken as AAC, what most of them hold;
  /// [forM4a] tells the lossless ones apart once the length is known.
  static AudioFormat fromExtension(String ext) {
    return switch (ext.toLowerCase().replaceFirst('.', '')) {
      'flac' => flac,
      'alac' => alac,
      'm4a' || 'aac' => aac,
      'wav' => wav,
      'aiff' || 'aif' => aiff,
      'ape' => ape,
      'mp3' => mp3,
      'ogg' => ogg,
      'opus' => opus,
      _ => unknown,
    };
  }

  /// An .m4a holds AAC (lossy, at most ~320 kbps) or ALAC (lossless, usually 600–1100 kbps
  /// for CD audio, never below ~400). Every .m4a used to count as ALAC: AAC songs showed
  /// "ALAC 16-BIT" and filled the Lossless list.
  static AudioFormat forM4a({required int averageKbps}) => averageKbps >= alacFloorKbps ? alac : aac;

  static const alacFloorKbps = 500;
}
