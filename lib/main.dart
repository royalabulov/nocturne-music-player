import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import 'app.dart';
import 'core/audio/sonar_audio_handler.dart';
import 'core/diagnostics/crash_log.dart';
import 'core/demo/demo_audio.dart';
import 'core/demo/demo_overrides.dart';
import 'core/di/providers.dart';
import 'core/ui/toast.dart';
import 'data/datasources/media_store_source.dart';
import 'features/import/audio_import.dart';
import 'features/library_scan/scan_controller.dart';
import 'features/player/player_providers.dart';
import 'features/settings/settings_controller.dart';
import 'features/smart_groups/smart_groups.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Error log first: so startup errors are recorded too.
  await CrashLog.init();

  // Edge-to-edge: status bar and nav bar transparent, content goes underneath.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
      .catchError((e) => debugPrint('AudioSession unavailable: $e'));

  late final ProviderContainer container;
  final handler = await AudioService.init(
    builder: () => SonarAudioHandler(
      onTrackStarted: (t) => container.read(historyRepositoryProvider).recordPlay(t.id),
      onTrackUnavailable: (t) {
        container.read(libraryRepositoryProvider).markMissing(t.id);
        showToast('"${t.title}" is no longer on this device — skipped');
      },
      // Web demo: no real files → synthesized WAV
      sourceBuilder: kIsWeb ? DemoAudio.sourceFor : null,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.royal.sonar.playback',
      androidNotificationChannelName: 'Nocturne playback',
      // Stay in foreground while paused too: otherwise Samsung kills the process in the
      // background, and startForeground again from the background crashes on Android 12+.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationIcon: 'drawable/ic_stat_sonar',
    ),
  );

  container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(handler),
      // Running in Chrome: no DB/scanner/file system → in-memory demo library.
      if (kIsWeb) ...demoOverrides(),
    ],
  );
  // Cover paths are needed synchronously (Image.file) → prepare the folder up front.
  if (!kIsWeb) await container.read(coverCacheProvider).warmUp();
  await sessionReady;

  runApp(UncontrolledProviderScope(container: container, child: const SonarApp()));

  // Audio settings (EQ / crossfade / ReplayGain) are loaded from the DB and applied to the player.
  container.read(audioSettingsProvider);

  // Playback memory: save the position every 5 seconds while playing.
  handler.position.where((_) => handler.playing).throttleTime(const Duration(seconds: 5)).listen((pos) {
    final t = handler.currentTrackValue;
    if (t != null) container.read(historyRepositoryProvider).saveResumePoint(t.id, pos);
  });

  // "Open with Nocturne" / Share: if the app was opened this way, take the file and play it;
  // while open, native code reports new files.
  if (!kIsWeb) {
    final importer = container.read(audioImportProvider);
    final scan = container.read(scanControllerProvider.notifier);
    MediaStoreSource.setListeners(
      onOpened: importer.handleOpened,
      // A new song was downloaded while the app is open → add it to the library automatically
      onMediaChanged: scan.scheduleAutoScan,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => importer.handleOpened());
    // Also check when returning from another app (Telegram, Snaptube, browser) — files
    // in those folders don't always reach MediaStore, so no event may arrive
    AppLifecycleListener(onResume: () => scan.scheduleAutoScan(delay: const Duration(milliseconds: 800)));
  }

  // If autoScan is on and permission is granted, scan silently — 1.5 s after the first
  // frame, so the MediaStore/folder walk doesn't compete with Home's first render.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 1500), () {
      container.read(scanControllerProvider.notifier).autoScanIfEnabled();
    });
    // Smart groups: unanalyzed songs in the background (also starts on its own after a scan)
    Future.delayed(const Duration(seconds: 4), () {
      container.read(smartAnalysisProvider.notifier).start();
    });
  });
}
