import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/domain/analysis/wrapped.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/domain/repositories/history_repository.dart';
import 'package:nocturne/features/wrapped/wrapped_card.dart';
import 'package:nocturne/features/wrapped/wrapped_data.dart';
import 'package:nocturne/features/wrapped/wrapped_story_screen.dart';
import 'package:nocturne/l10n/l10n.dart';

/// Wrapped's stories as the user sees them: every slide fits a small phone and a big one in
/// both languages, a tap on the right goes on and on the left goes back, the card comes last.
void main() {
  const nov = WrappedPeriod.month(2026, 11);

  Track track(int id) => Track(
        id: id,
        path: '/m/$id.mp3',
        title: 'A rather long song title number $id that goes on',
        artist: id.isEven ? 'Yalın' : 'Şebnem Ferah × mor ve ötesi',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  /// A full month: every slide has something to show. [freshHistory]: the history begins in
  /// this month, so there is no telling which songs are new.
  Wrapped full({bool freshHistory = false}) {
    final tracks = {for (var i = 1; i <= 8; i++) i: track(i)};
    final plays = [
      // The history began in September: November's new songs mean something
      if (!freshHistory)
        PlayRecord(
          trackId: 1,
          playedAt: DateTime(2026, 9, 5),
          listened: const Duration(minutes: 3),
          duration: const Duration(minutes: 3),
        ),
      for (var id = 1; id <= 8; id++)
        for (var n = 0; n < 9 - id; n++)
          PlayRecord(
            trackId: id,
            playedAt: DateTime(2026, 11, 1 + n * 3, 8 + id * 2),
            listened: const Duration(minutes: 3),
            duration: const Duration(minutes: 3),
          ),
    ];
    return buildWrapped(nov, plays, tracks, moodOf: {for (var i = 1; i <= 8; i++) i: ['sad', 'calm', 'happy', 'energetic'][i % 4]})!;
  }

  Future<void> open(WidgetTester tester, Wrapped w, {Size size = const Size(412, 915), String lang = 'en'}) async {
    setAppLocale(Locale(lang));
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [wrappedProvider.overrideWith((ref, _) async => w)],
      child: const MaterialApp(home: WrappedStoryScreen(period: nov)),
    ));
    // Not pumpAndSettle: the story's clock never stops ticking
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> tapRight(WidgetTester tester) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width * .85, size.height * .2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500)); // the slide going out is removed after its fade
  }

  test('a full month has all 8 slides to show', () {
    final w = full();
    expect(w.topSongs, hasLength(5));
    expect(w.showMoods, isTrue);
    expect(w.discoveryCount, greaterThan(0));
  });

  for (final (size, lang) in [
    (const Size(320, 568), 'en'),
    (const Size(360, 640), 'az'),
    (const Size(412, 915), 'az'),
    (const Size(412, 915), 'en'),
  ]) {
    testWidgets('every slide fits at ${size.width.toInt()}×${size.height.toInt()} in $lang', (tester) async {
      await open(tester, full(), size: size, lang: lang);
      for (var i = 0; i < 8; i++) {
        expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
        await tapRight(tester);
      }
      expect(find.byType(WrappedCard), findsOneWidget, reason: 'the card is the last slide');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a history that began this month: no "new songs", the streak slide instead, and it fits', (tester) async {
    final w = full(freshHistory: true);
    expect(w.knowsDiscoveries, isFalse);
    await open(tester, w, size: const Size(320, 568));
    final t = lookupL10n(const Locale('en'));
    for (var i = 0; i < 8; i++) {
      expect(find.text(t.wrappedNew.toUpperCase()), findsNothing);
      expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
      await tapRight(tester);
    }
    expect(find.byType(WrappedCard), findsOneWidget);
  });

  testWidgets('a tap on the left goes back; slides move on by themselves', (tester) async {
    await open(tester, full());
    final t = lookupL10n(const Locale('en'));
    expect(find.text(t.wrappedTopSong.toUpperCase()), findsNothing);

    await tapRight(tester);
    expect(find.text(t.wrappedTopSong.toUpperCase()), findsOneWidget);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width * .1, size.height * .2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.wrappedTopSong.toUpperCase()), findsNothing, reason: 'back on the first slide');

    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.wrappedTopSong.toUpperCase()), findsOneWidget, reason: 'moved on after its time');
  });

  testWidgets('without enough analyzed songs there is no mood slide', (tester) async {
    final w = full();
    final noMood = Wrapped(
      period: w.period,
      plays: w.plays,
      songCount: w.songCount,
      listened: w.listened,
      topSongs: w.topSongs,
      topArtists: w.topArtists,
      moods: w.moods,
      moodCoverage: .2,
      byHour: w.byHour,
      time: w.time,
      discoveries: w.discoveries,
      discoveryCount: w.discoveryCount,
      longestStreak: w.longestStreak,
      activeDays: w.activeDays,
    );
    await open(tester, noMood);
    final t = lookupL10n(const Locale('en'));
    for (var i = 0; i < 7; i++) {
      expect(find.text(t.wrappedMood.toUpperCase()), findsNothing);
      await tapRight(tester);
    }
    expect(find.byType(WrappedCard), findsOneWidget, reason: 'one slide fewer: the card came a tap sooner');
  });

  testWidgets('a period with too few plays says so instead of a story', (tester) async {
    setAppLocale(const Locale('en'));
    await tester.pumpWidget(ProviderScope(
      overrides: [wrappedProvider.overrideWith((ref, _) async => null)],
      child: const MaterialApp(home: WrappedStoryScreen(period: nov)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(lookupL10n(const Locale('en')).wrappedNotEnough), findsOneWidget);
  });

  test('numbers and titles', () {
    setAppLocale(const Locale('az'));
    expect(groupDigits(7), '7');
    expect(groupDigits(1820), '1 820');
    expect(groupDigits(1234567), '1 234 567');
    expect(wrappedTitle(nov), 'Noyabr 2026');
    expect(wrappedTitle(const WrappedPeriod.year(2026)), '2026');
    setAppLocale(const Locale('en'));
    expect(monthName(1), 'January');
    expect(monthName(12), 'December');
  });
}
