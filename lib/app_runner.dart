import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:just_audio/just_audio.dart' show AudioSource;
import 'package:rxdart/rxdart.dart';

import 'app.dart';
import 'core/audio/listen_tracker.dart';
import 'core/audio/nocturne_audio_handler.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/di/providers.dart';
import 'core/ui/toast.dart';
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
  final handler = await AudioService.init(
    builder: () => NocturneAudioHandler(
      // Records the play and measures how long it's really heard
      onTrackStarted: (t) => container.read(listenTrackerProvider).trackStarted(t.id),
      onTrackUnavailable: (t) => unawaited(_reportUnplayable(container, t)),
      sourceBuilder: sourceBuilder,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.nocturne.playback',
      androidNotificationChannelName: l10n.notificationChannel,
      // Stay in foreground while paused too: otherwise some phones kill the process in the
      // background, and startForeground again from the background crashes on Android 12+.
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
  // Cover paths are needed synchronously (Image.file) → prepare the folder up front.
  if (!kIsWeb) await container.read(coverCacheProvider).warmUp();
  await sessionReady;

  // Settings → Language before the first frame: otherwise the app starts in the
  // phone's language and only then switches
  initialLanguage = await container.read(settingsRepositoryProvider).getSetting(SettingsKeys.language);

  runApp(UncontrolledProviderScope(container: container, child: const NocturneApp()));

  // Audio settings (EQ / crossfade / ReplayGain) are loaded from the DB and applied to the player.
  container.read(audioSettingsProvider);

  // Playback memory: save the position every 5 seconds while playing.
  handler.position.where((_) => handler.playing).throttleTime(const Duration(seconds: 5)).listen((pos) {
    final t = handler.currentTrackValue;
    if (t == null) return;
    // A full disk fails this every 5 seconds: playback goes on, the error isn't worth a crash entry
    unawaited(container
        .read(historyRepositoryProvider)
        .saveResumePoint(t.id, pos)
        .catchError((Object e) => debugPrint('resume point not saved: $e')));
  });

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
    // in those folders don't always reach MediaStore, so no event may arrive
    AppLifecycleListener(onResume: () => scan.scheduleAutoScan(delay: const Duration(milliseconds: 800)));
  }

  // Forgotten favorites reminder: plan the notifications on start and every time the
  // app goes to the background (also picks up a language change).
  final reminder = container.read(forgottenReminderProvider);
  unawaited(reminder
      .init(onResponse: (id, play) => _openFromReminder(container, handler, id, play: play))
      .then((_) => reminder.reschedule()));
  AppLifecycleListener(onPause: reminder.reschedule);

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
