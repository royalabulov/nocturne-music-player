import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/player_providers.dart';
import '../../core/di/providers.dart';
import '../../core/router/routes.dart';
import '../../core/ui/toast.dart';
import '../../l10n/l10n.dart';
import '../../shared/locate_track.dart';
import '../radio/radio_actions.dart';

/// The app icon's long-press shortcuts: Shuffle all, Continue (named after the last song),
/// Radio, Search. They are set again whenever the last song changes and when the app comes
/// back (a language change shows then), and a tap does what it says.
class AppShortcutsController {
  AppShortcutsController(this._container);

  final ProviderContainer _container;
  StreamSubscription<Object?>? _resumeSub;
  String? _continueTitle;

  /// Sets the shortcuts, follows the last song, and does what a tap asked for — also the tap
  /// that started the app.
  void start() {
    final source = _container.read(shortcutsSourceProvider);
    source.listen(() => unawaited(_takeAndRun()));
    _resumeSub = _container.read(historyRepositoryProvider).watchResumePoint().listen((p) {
      final title = p?.track.title;
      if (title == _continueTitle) return;
      _continueTitle = title;
      unawaited(publish());
    });
    unawaited(publish());
    // After the first frame: the router and the restored queue are there by then
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_takeAndRun()));
  }

  void dispose() => unawaited(_resumeSub?.cancel());

  /// The shortcuts in the current language.
  Future<void> publish() => _container.read(shortcutsSourceProvider).set([
        (id: 'shuffle', label: l10n.shortcutShuffle, longLabel: l10n.shortcutShuffleLong),
        (
          id: 'continue',
          label: l10n.shortcutContinue,
          longLabel: _continueTitle == null ? l10n.shortcutContinue : l10n.shortcutContinueLong(_continueTitle!),
        ),
        (id: 'radio', label: l10n.menuRadio, longLabel: l10n.shortcutRadioLong),
        (id: 'search', label: l10n.search, longLabel: l10n.shortcutSearchLong),
      ]);

  Future<void> _takeAndRun() async {
    final id = await _container.read(shortcutsSourceProvider).take();
    if (id != null) await run(id);
  }

  /// What a tap on shortcut [id] does.
  @visibleForTesting
  Future<void> run(String id) async {
    final handler = _container.read(audioHandlerProvider);
    switch (id) {
      case 'shuffle':
        final tracks = await _container.read(libraryRepositoryProvider).watchTracks().first;
        if (tracks.isEmpty) return showToast(l10n.noTracksYet);
        // A random first song; smooth shuffle orders the rest
        await handler.playTracks(tracks, startIndex: Random().nextInt(tracks.length), shuffle: true);
        openNowPlaying();
      case 'continue':
        // The queue as it was left (restored at start, or read again for an empty player)
        await handler.play();
        if (handler.currentTrackValue == null) return showToast(l10n.shortcutNothingToContinue);
        openNowPlaying();
      case 'radio':
        await startRadioFromNowPlaying(_container);
        if (handler.currentTrackValue != null) openNowPlaying();
      case 'search':
        final context = rootNavigatorKey.currentContext;
        if (context == null) return;
        GoRouter.of(context).go(Routes.home);
        // After Home is shown. Already there, nothing would draw a new frame and the callback
        // would never come (seen on the phone): ask for one
        WidgetsBinding.instance
          ..addPostFrameCallback((_) => _container.read(focusSearchProvider.notifier).request())
          ..scheduleFrame();
    }
  }
}
