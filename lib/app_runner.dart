import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:just_audio/just_audio.dart' show AudioSource;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/audio/audio_effects.dart';
import 'core/audio/listen_tracker.dart';
import 'core/audio/nocturne_audio_handler.dart';
import 'core/audio/playback_memory.dart';
import 'core/audio/service_release.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/constants.dart';
import 'core/di/providers.dart';
import 'core/ui/toast.dart';
import 'data/datasources/playback_service_source.dart';
import 'data/db/app_database.dart';
import 'data/db/database_rescue.dart';
import 'domain/entities/track.dart';
import 'domain/repositories/settings_repository.dart';
import 'app_router.dart';
import 'core/router/routes.dart';
import 'features/forgotten/forgotten.dart';
import 'features/forgotten/forgotten_reminder.dart';
import 'features/import/audio_import.dart';
import 'features/library_scan/scan_controller.dart';
import 'features/library_scan/unplayable_track.dart';
import 'core/audio/player_providers.dart';
import 'features/settings/settings_controller.dart';
import 'features/smart_groups/smart_groups.dart';
import 'l10n/l10n.dart';

/// Starts the app. The real app needs no arguments: [sourceBuilder] and [overrides] are how
/// the web preview brings its in-memory library and synthesized sound (main_demo.dart).
Future<void> runNocturne({AudioSource Function(Track)? sourceBuilder, List<Override> overrides = const []}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Error log first: so startup errors are recorded too.
  await CrashLog.init();

  // Edge-to-edge: status bar and nav bar transparent, content goes underneath.
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Audio focus / ducking / pause when headphones are unplugged — system level.
  // Runs in parallel with AudioService.init (sequential awaits added up at startup).
  final sessionReady = AudioSession.instance
      .then((s) => s.configure(const AudioSessionConfiguration.music()))
      .catchError((Object e) => debugPrint('AudioSession unavailable: $e'));

  late final ProviderContainer container;
  late final PlaybackMemory memory;
  // Before the players exist: on a phone that can't make a system equalizer they are built
  // without one (just_audio would fail every song).
  final equalizer = await PlaybackServiceSource().equalizerWorks();
  if (!equalizer) CrashLog.add('no system equalizer on this phone: players built without one');

  final handler = await AudioService.init(
    builder: () => NocturneAudioHandler(
      effects: NocturneEffects(equalizer: equalizer),
      // Records the play and measures how long it's really heard
      onTrackStarted: (t) => container.read(listenTrackerProvider).trackStarted(t.id),
      onTrackUnavailable: (t) => unawaited(_reportUnplayable(container, t)),
      sourceBuilder: sourceBuilder,
      // Play with nothing queued (a Bluetooth button after the app was ended): the last queue
      savedQueue: () => memory.load(evenClosed: true),
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: kPlaybackChannelId,
      androidNotificationChannelName: l10n.notificationChannel,
      // Stay in foreground while paused too: otherwise some phones kill the process in the
      // background, and startForeground again from the background crashes on Android 12+
      // (resuming after a call). The wake lock the plugin would keep with it is released by
      // releaseServiceWhenIdle below.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_stat_sonar',
      // Without this the plugin decodes a cover at full size just for the notification
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );

  container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      ...overrides,
    ],
  );
  // A damaged database is set aside before anything reads it: the app starts with a new one
  // instead of hanging on its start screen for good (DatabaseRescue).
  var databaseReset = false;
  if (!kIsWeb) {
    final file = p.join((await getApplicationDocumentsDirectory()).path, '${AppDatabase.fileName}.sqlite');
    if (await DatabaseRescue.setAsideIfDamaged(container.read(databaseProvider), file)) {
      container.invalidate(databaseProvider);
      databaseReset = true;
      CrashLog.add('database was damaged: set aside, a new one started');
    }
  }
  // Cover paths are needed synchronously (Image.file) → prepare the folder up front.
  if (!kIsWeb) await container.read(coverCacheProvider).warmUp();
  await sessionReady;

  // Settings → Language before the first frame: otherwise the app starts in the
  // phone's language and only then switches
  initialLanguage = await container.read(settingsRepositoryProvider).getSetting(SettingsKeys.language);

  runApp(UncontrolledProviderScope(container: container, child: const NocturneApp()));
  if (databaseReset) {
    WidgetsBinding.instance.addPostFrameCallback((_) => showToast(l10n.databaseReset, error: true));
  }

  // Audio settings (EQ / crossfade / ReplayGain) are loaded from the DB and applied to the player.
  container.read(audioSettingsProvider);

  // Playback memory: the queue and the place in the song, so both survive the app being ended.
  memory = PlaybackMemory(
    settings: container.read(settingsRepositoryProvider),
    library: container.read(libraryRepositoryProvider),
    history: container.read(historyRepositoryProvider),
  );
  memory.attach(handler);
  unawaited(memory.load().then((saved) async {
    if (saved != null) await handler.restoreQueue(saved);
  }).catchError((Object e) => debugPrint('queue not restored: $e')));

  // Nothing heard: the playback service lets the CPU sleep (and drops its notification once stopped)
  final service = container.read(playbackServiceProvider);
  releaseServiceWhenIdle(handler.playbackState, paused: service.paused, stopped: service.stopped);

  // "Open with Nocturne" / Share: if the app was opened this way, take the file and play it;
  // while open, native code reports new files.
  if (!kIsWeb) {
    final importer = container.read(audioImportProvider);
    final scan = container.read(scanControllerProvider.notifier);
    container.read(deviceFilesProvider).setListeners(
      onOpened: importer.handleOpened,
      // A new song was downloaded while the app is open → add it to the library automatically
      onMediaChanged: scan.scheduleAutoScan,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => importer.handleOpened());
    // Also check when returning from another app (messenger, downloader, browser) — files
    // in those folders don't always reach MediaStore, so no event may arrive. Scans only if
    // the media index or a scan folder changed meanwhile.
    AppLifecycleListener(
      onResume: () => scan.scheduleAutoScan(delay: const Duration(milliseconds: 800), onlyIfChanged: true),
    );
  }

  // Forgotten favorites reminder: plan the notifications on start and every time the
  // app goes to the background (also picks up a language change).
  final reminder = container.read(forgottenReminderProvider);
  unawaited(reminder
      .init(onResponse: (id, play) => _openFromReminder(container, handler, id, play: play))
      .then((_) => reminder.reschedule()));
  AppLifecycleListener(onPause: reminder.reschedule);

  // Weekly backup copy (Download/Nocturne): when the app goes to the background, so it never
  // competes with what is on screen
  AppLifecycleListener(onPause: () => unawaited(container.read(autoBackupProvider).runIfDue()));

  // If autoScan is on and permission is granted, scan silently — 1.5 s after the first
  // frame, so the MediaStore/folder walk doesn't compete with Home's first render.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 1500), () {
      unawaited(container.read(scanControllerProvider.notifier).autoScanIfEnabled());
    });
    // Smart groups: unanalyzed songs in the background (also starts on its own after a scan)
    Future.delayed(const Duration(seconds: 4), () {
      unawaited(container.read(smartAnalysisProvider.notifier).start());
    });
  });
}

/// A song wouldn't play: hide it only if its file is really gone, otherwise say why.
Future<void> _reportUnplayable(ProviderContainer c, Track t) async {
  switch (await whyUnplayable(t.path)) {
    case Unplayable.missing:
      showToast(l10n.toastTrackMissing(t.title), error: true);
      await c.read(libraryRepositoryProvider).markMissing(t.id);
    case Unplayable.noPermission:
      showToast(l10n.toastNoMusicPermission, error: true);
    case Unplayable.unreadable:
      showToast(l10n.toastTrackUnreadable(t.title), error: true);
  }
}

/// A reminder was tapped: open Forgotten favorites with that song on top (no sound —
/// headphones may not be in). Its "Play" button also starts the forgotten list there.
Future<void> _openFromReminder(ProviderContainer c, NocturneAudioHandler handler, int trackId, {required bool play}) async {
  appRouter.go('$kForgottenRoute?t=$trackId');
  if (!play) return;
  final rule = c.read(forgottenSettingsProvider);
  final list = await c.read(historyRepositoryProvider).watchForgotten(minPlays: rule.minPlays, days: rule.days).first;
  final tracks = [for (final p in list) p.track];
  final i = tracks.indexWhere((t) => t.id == trackId);
  if (i >= 0) {
    await handler.playTracks(tracks, startIndex: i);
  } else if (await c.read(libraryRepositoryProvider).getTrack(trackId) case final t?) {
    await handler.playTracks([t]);
  }
}
