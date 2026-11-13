import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import 'nocturne_audio_handler.dart';
import 'queue_snapshot.dart';

/// Keeps the play queue and the place in the song stored, so both come back after Android
/// ended the app (memory, a battery saver, a swipe out of the recent apps while paused).
class PlaybackMemory {
  PlaybackMemory({required this.settings, required this.library, required this.history});

  final SettingsRepository settings;
  final LibraryRepository library;
  final HistoryRepository history;

  /// The stored queue with the songs still in the library. [evenClosed]: also one whose mini
  /// player was swiped away (play pressed with nothing queued brings it back; a start doesn't).
  Future<SavedQueue?> load({bool evenClosed = false}) async {
    final s = QueueSnapshot.decode(await settings.getSetting(SettingsKeys.playQueue));
    if (s == null || (s.closed && !evenClosed)) return null;
    final found = {for (final t in await library.getTracks(s.trackIds)) t.id: t};
    // The place in the song is the resume point, written every few seconds while playing
    final resume = await history.watchResumePoint().first;
    final position = resume != null && resume.track.id == s.currentId ? resume.position : Duration.zero;
    return SavedQueue.from(s, found, position: position);
  }

  /// Follows [handler] and stores what changes. [queueSettle]: changes that come together
  /// (a new list, its first song) are stored once.
  List<StreamSubscription<void>> attach(
    NocturneAudioHandler handler, {
    Duration queueSettle = const Duration(seconds: 1),
    Duration positionEvery = const Duration(seconds: 5),
  }) {
    QueueSnapshot? last;
    Future<void> storeQueue() async {
      final now = handler.snapshot;
      // Empty at the start (nothing restored yet) must not wipe what is stored. Empty after
      // a queue = the mini player was swiped away.
      final store = now ?? last?.asClosed();
      if (store == null) return;
      last = now;
      await _guard(settings.setSetting(SettingsKeys.playQueue, store.encode()));
    }

    Future<void> storePosition() async {
      final t = handler.currentTrackValue;
      if (t == null) return;
      await _guard(history.saveResumePoint(t.id, handler.positionValue));
    }

    return [
      Rx.merge<Object?>([
        handler.trackQueue,
        handler.currentTrack,
        handler.playbackState.map((s) => (s.shuffleMode, s.repeatMode)).distinct(),
      ]).debounceTime(queueSettle).listen((_) => unawaited(storeQueue())),
      // While playing: every few seconds
      handler.position
          .where((_) => handler.playing)
          .throttleTime(positionEvery)
          .listen((_) => unawaited(storePosition())),
      // Paused, or moved while paused: the exact place, not the one from up to 5 s before
      handler.position
          .where((_) => !handler.playing)
          .debounceTime(queueSettle)
          .listen((_) => unawaited(storePosition())),
    ];
  }

  /// A full disk fails these: playback goes on, the error isn't worth a crash entry.
  static Future<void> _guard(Future<void> f) => f.catchError((Object e) => debugPrint('playback memory: $e'));
}
