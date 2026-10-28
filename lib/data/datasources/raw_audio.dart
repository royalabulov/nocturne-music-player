/// A file found in the scan's first phase — no tags yet.
class RawAudio {
  const RawAudio({required this.path, required this.size, required this.dateModified});

  final String path;
  final int size;

  /// epoch ms
  final int dateModified;
}
