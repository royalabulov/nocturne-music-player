enum ScanPhase { idle, enumerating, reading, finalizing, done, error }

class ScanProgress {
  const ScanProgress({
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.added = 0,
    this.currentFile,
    this.error,
  });

  static const idle = ScanProgress(phase: ScanPhase.idle);

  final ScanPhase phase;
  final int done, total, added;
  final String? currentFile;
  final String? error;

  bool get isRunning =>
      phase == ScanPhase.enumerating || phase == ScanPhase.reading || phase == ScanPhase.finalizing;

  double? get fraction => total == 0 ? null : done / total;

  ScanProgress copyWith({
    ScanPhase? phase, int? done, int? total, int? added,
    String? currentFile, String? error,
  }) =>
      ScanProgress(
        phase: phase ?? this.phase,
        done: done ?? this.done,
        total: total ?? this.total,
        added: added ?? this.added,
        currentFile: currentFile ?? this.currentFile,
        error: error ?? this.error,
      );
}
