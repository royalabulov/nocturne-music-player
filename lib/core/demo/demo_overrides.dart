import 'package:flutter_riverpod/misc.dart';

import '../di/providers.dart';
import 'demo_repositories.dart';

/// For running on the web (Chrome): an in-memory demo library instead of the real DB/scanner.
/// Only for looking at the UI.
List<Override> demoOverrides() {
  final lib = DemoLibraryRepository();
  return [
    libraryRepositoryProvider.overrideWithValue(lib),
    historyRepositoryProvider.overrideWithValue(DemoHistoryRepository(lib)),
    playlistRepositoryProvider.overrideWithValue(DemoPlaylistRepository(lib)),
    analysisRepositoryProvider.overrideWithValue(DemoAnalysisRepository(lib)),
  ];
}
