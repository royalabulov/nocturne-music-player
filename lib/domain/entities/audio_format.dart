/// Supported audio formats. [label] is shown in the codec chip.
enum AudioFormat {
  flac('FLAC', isLossless: true),
  alac('ALAC', isLossless: true),
  wav('WAV', isLossless: true),
  mp3('MP3'),
  aac('AAC'),
  ogg('OGG'),
  opus('OPUS'),
  unknown('?');

  const AudioFormat(this.label, {this.isLossless = false});

  final String label;
  final bool isLossless;

  static AudioFormat fromExtension(String ext) {
    return switch (ext.toLowerCase().replaceFirst('.', '')) {
      'flac' => flac,
      'm4a' || 'alac' => alac,
      'wav' => wav,
      'mp3' => mp3,
      'aac' => aac,
      'ogg' => ogg,
      'opus' => opus,
      _ => unknown,
    };
  }
}
