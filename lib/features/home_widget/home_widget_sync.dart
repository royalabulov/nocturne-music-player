import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player_providers.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/display_names.dart';
import '../../domain/entities/track.dart';
import '../../l10n/l10n.dart';
import '../../shared/cover_color.dart';

/// Keeps the home screen widgets (Kotlin `HomeWidgets`) showing what plays: started once in
/// app_runner on Android. Sends only when something they show changed; the large widget's
/// progress line at most every [progressEvery] while playing.
final homeWidgetSyncProvider = Provider<HomeWidgetSync>((ref) {
  final sync = HomeWidgetSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

class HomeWidgetSync {
  HomeWidgetSync(this._ref) {
    _ref.read(homeWidgetSourceProvider).listen(_onAction);
    void changed(Object? _, Object? _) => _schedule();
    _ref
      ..listen(currentTrackProvider, changed)
      ..listen(durationProvider, changed)
      ..listen(favoriteIdsProvider, changed)
      ..listen(currentCoverColorProvider, changed)
      ..listen(
        playbackStateProvider.select((s) => (s.value?.playing, s.value?.shuffleMode, s.value?.repeatMode)),
        (_, _) {
          _tickWhilePlaying();
          _schedule();
        },
      );
    _tickWhilePlaying();
    _schedule();
  }

  final Ref _ref;

  /// A song change moves several of the streams above at once: one send after they settle.
  static const _settle = Duration(milliseconds: 200);
  static const progressEvery = Duration(seconds: 10);

  Timer? _pending;
  Timer? _ticker;
  String? _lastSent;
  String? _lastWithoutPosition;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Sends again if anything differs, e.g. the app's language changed the buttons' names.
  void refresh() => _schedule();

  void _schedule() {
    _pending?.cancel();
    _pending = Timer(_settle, _send);
  }

  void _tickWhilePlaying() {
    final playing = _ref.read(isPlayingProvider);
    if (playing && _ticker == null) {
      _ticker = Timer.periodic(progressEvery, (_) => _send());
    } else if (!playing) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _send() {
    final handler = _ref.read(audioHandlerProvider);
    final track = _ref.read(currentTrackProvider).value;
    final state = _ref.read(playbackStateProvider).value;
    final map = widgetState(
      track: track,
      playing: state?.playing ?? false,
      shuffle: state?.shuffleMode == AudioServiceShuffleMode.all,
      repeat: state?.repeatMode ?? AudioServiceRepeatMode.none,
      favorite: track != null && (_ref.read(favoriteIdsProvider).value?.contains(track.id) ?? false),
      position: handler.positionValue,
      duration: _ref.read(durationProvider).value ?? track?.duration,
      cover: _ref.read(currentCoverColorProvider),
    );
    final json = jsonEncode(map);
    if (json == _lastSent) return;
    // Only the position moved: the progress line can wait for the next tick
    final withoutPosition = jsonEncode({...map, 'position': 0});
    final now = DateTime.now();
    if (withoutPosition == _lastWithoutPosition && now.difference(_lastSentAt) < progressEvery - const Duration(seconds: 1)) {
      return;
    }
    _lastSent = json;
    _lastWithoutPosition = withoutPosition;
    _lastSentAt = now;
    unawaited(_ref.read(homeWidgetSourceProvider).update(json));
  }

  Future<void> _onAction(String action) async {
    final handler = _ref.read(audioHandlerProvider);
    switch (action) {
      case 'shuffle':
        await handler.toggleShuffle();
      case 'repeat':
        await handler.cycleRepeat();
      case 'favorite':
        final track = handler.currentTrackValue;
        if (track != null) await _ref.read(libraryRepositoryProvider).toggleFavorite(track.id);
    }
  }

  void dispose() {
    _pending?.cancel();
    _ticker?.cancel();
  }
}

/// What the widgets show, as `WidgetState.parse` in HomeWidgets.kt reads it. No [track]:
/// nothing is queued (the mini player was closed) — the widgets show the app's name and a hint.
Map<String, Object?> widgetState({
  required Track? track,
  required bool playing,
  required bool shuffle,
  required AudioServiceRepeatMode repeat,
  required bool favorite,
  required Duration position,
  required Duration? duration,
  required Color cover,
}) =>
    {
      'track': track != null,
      'title': track?.title ?? '',
      'artist': track?.artistLabel ?? '',
      'cover': track?.coverPath ?? '',
      'seed': track?.id ?? 0,
      'playing': track != null && playing,
      'shuffle': shuffle,
      'repeat': switch (repeat) {
        AudioServiceRepeatMode.one => 'one',
        AudioServiceRepeatMode.none => 'none',
        _ => 'all',
      },
      'favorite': favorite,
      'position': position.inMilliseconds,
      'duration': duration?.inMilliseconds ?? 0,
      'tint': widgetTint(cover).toARGB32(),
      'labels': {
        'play': l10n.play,
        'pause': l10n.pause,
        'previous': l10n.previousSong,
        'next': l10n.nextSong,
        'shuffleOn': l10n.shuffleOn,
        'shuffleOff': l10n.shuffleOff,
        'repeat_none': l10n.repeatOff,
        'repeat_all': l10n.repeatAll,
        'repeat_one': l10n.repeatOne,
        'addFavorite': l10n.addToFavorites,
        'removeFavorite': l10n.removeFromFavorites,
        'emptyTitle': 'Nocturne',
        'emptyHint': l10n.widgetEmptyHint,
      },
    };

/// The widget body: the mini player's glass with the cover's colour washed over it at 16 %
/// (MiniPlayer's _CoverTint). Opaque: the widget's drawable keeps the glass's own alpha.
Color widgetTint(Color cover) =>
    Color.alphaBlend(cover.withValues(alpha: .16), AppColors.glassLevel2Solid.withValues(alpha: 1));
