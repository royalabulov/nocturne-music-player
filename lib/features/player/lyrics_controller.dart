import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/network/online_mode.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../core/audio/player_providers.dart';

/// Now Playing shows lyrics instead of the cover. Stays on across songs (not saved).
class ShowLyrics extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final showLyricsProvider = NotifierProvider<ShowLyrics, bool>(ShowLyrics.new);

/// Lyrics of the current song. Only the lyrics view watches it, so nothing is
/// looked up (no network) unless the user opens lyrics.
class LyricsController extends AsyncNotifier<LyricsResult> {
  @override
  Future<LyricsResult> build() {
    ref.watch(currentTrackProvider.select((a) => a.value?.id));
    // Online mode switched on/off (not every connection re-check)
    ref.watch(onlineModeProvider.select((s) => s.enabled));
    // Settings → Network: look for lyrics on lrclib.net (only in Online mode). Default on.
    ref.watch(boolSettingProvider(SettingsKeys.lyricsOnline));
    return _load();
  }

  Future<LyricsResult> _load({bool force = false}) async {
    final track = ref.read(currentTrackProvider).value;
    if (track == null) return const LyricsResult(LyricsStatus.notFound);
    return ref.read(lyricsRepositoryProvider).load(
          track,
          online: ref.read(onlineModeProvider).enabled,
          onlineSearch: ref.read(boolSettingProvider(SettingsKeys.lyricsOnline)).value ?? true,
          force: force,
          // A rebuild (next song) makes this ref stale → stop retrying for the old song
          isCancelled: () => !ref.mounted,
        );
  }

  /// "Search again": asks LRCLIB even if it had nothing a moment ago.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(force: true));
  }
}

final lyricsProvider = AsyncNotifierProvider.autoDispose<LyricsController, LyricsResult>(LyricsController.new);
