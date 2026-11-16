import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/di/providers.dart';
import 'package:nocturne/core/ui/toast.dart';
import 'package:nocturne/data/datasources/audio_analyzer_source.dart';
import 'package:nocturne/demo/demo_repositories.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/scan_progress.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/analysis_repository.dart';
import 'package:nocturne/domain/repositories/settings_repository.dart';
import 'package:nocturne/features/library_scan/permission_gate.dart';
import 'package:nocturne/features/library_scan/scan_controller.dart';
import 'package:nocturne/features/radio/radio_actions.dart';
import 'package:nocturne/features/radio/radio_controller.dart';
import 'package:nocturne/features/smart_groups/smart_groups.dart';
import 'package:nocturne/l10n/l10n.dart';

/// Radio tapped before enough songs are analyzed: the toast says whether waiting helps,
/// and how long.
void main() {
  final t = lookupL10n(const Locale('en'));
  setUp(() => setAppLocale(const Locale('en')));

  const seed = Track(
    id: 1,
    path: '/music/1.mp3',
    title: 'Song 1',
    artist: 'A',
    album: 'B',
    duration: Duration(minutes: 3),
    format: AudioFormat.mp3,
  );

  Future<(ProviderContainer, DemoSettingsRepository)> tapRadio(
    WidgetTester tester, {
    required AnalysisProgress progress,
    bool analysisOn = true,
    Duration? left,
  }) async {
    final settings = DemoSettingsRepository();
    if (!analysisOn) await settings.setSetting(SettingsKeys.smartAnalysis, 'false');
    final c = ProviderContainer(overrides: [
      radioProvider.overrideWith(_NotReady.new),
      analysisRepositoryProvider.overrideWithValue(_Progress(progress)),
      settingsRepositoryProvider.overrideWithValue(settings),
      scanControllerProvider.overrideWith(_Idle.new),
      audioAnalyzerProvider.overrideWithValue(_Unsupported()),
      smartAnalysisProvider.overrideWith(() => _Analysis(left)),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(scaffoldMessengerKey: rootMessengerKey, home: const Scaffold()),
    ));
    unawaited(startRadio(c, seed));
    await tester.pumpAndSettle();
    return (c, settings);
  }

  testWidgets('analysis running: how far, and about how long is left', (tester) async {
    await tapRadio(tester, progress: const AnalysisProgress(done: 5, total: 450), left: const Duration(minutes: 12, seconds: 10));
    expect(find.text(t.radioNotReadyTimeLeft(5, 450, t.minutesLong(13))), findsOneWidget);
  });

  testWidgets('too early to say how long: just how far', (tester) async {
    await tapRadio(tester, progress: const AnalysisProgress(done: 2, total: 450));
    expect(find.text(t.radioNotReady(2, 450)), findsOneWidget);
  });

  testWidgets('analysis off: says so, and "Turn on" turns it on', (tester) async {
    final (_, settings) = await tapRadio(tester, progress: const AnalysisProgress(done: 5, total: 450), analysisOn: false);
    expect(find.text(t.radioAnalysisOff), findsOneWidget);

    await tester.tap(find.text(t.turnOn));
    await tester.pumpAndSettle();
    expect(await settings.getSetting(SettingsKeys.smartAnalysis), 'true');
    expect(find.text(t.radioAnalysisTurnedOn), findsOneWidget);
  });

  testWidgets('everything analyzed and still too few: waiting will not help', (tester) async {
    await tapRadio(tester, progress: const AnalysisProgress(done: 6, total: 6));
    expect(find.text(t.radioTooFewSongs(RadioController.minSongs + 1)), findsOneWidget);
  });

  test('time: rounded up to minutes, hours past an hour', () {
    setAppLocale(const Locale('en'));
    expect(aboutTime(const Duration(seconds: 20)), t.minutesLong(1));
    expect(aboutTime(const Duration(minutes: 59, seconds: 1)), t.hoursMinutesLong(1, 0));
    expect(aboutTime(const Duration(minutes: 95)), t.hoursMinutesLong(1, 35));
  });
}

class _NotReady extends RadioController {
  @override
  RadioState build() => const RadioState();

  @override
  Future<RadioStart> start(Track seed) async => RadioStart.notReady;
}

class _Analysis extends SmartAnalysisController {
  _Analysis(this._left);
  final Duration? _left;

  @override
  Duration? timeLeft(int remaining) => _left;
}

class _Progress extends DemoAnalysisRepository {
  _Progress(this._p) : super(DemoLibraryRepository());
  final AnalysisProgress _p;

  @override
  Stream<AnalysisProgress> watchProgress(int version) => Stream.value(_p);
}

class _Unsupported extends AudioAnalyzerSource {
  @override
  bool get supported => false;
}

class _Idle extends ScanController {
  @override
  LibraryScanState build() => const LibraryScanState(permission: MediaPermission.granted, progress: ScanProgress.idle);
}
