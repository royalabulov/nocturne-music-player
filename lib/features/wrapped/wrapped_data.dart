import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/analysis/wrapped.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../l10n/l10n.dart';
import '../smart_groups/vibe_classifier.dart';
import '../smart_groups/vibe_review.dart';

/// Every play on the phone, read once while Wrapped is open. Not watched: the song playing
/// meanwhile must not reshuffle a story being watched.
final _allPlaysProvider = FutureProvider.autoDispose<List<PlayRecord>>(
  (ref) => ref.watch(historyRepositoryProvider).playsSince(DateTime(2000)),
);

/// The periods that have a Wrapped, newest first.
final wrappedPeriodsProvider = FutureProvider.autoDispose<List<WrappedPeriod>>(
  (ref) async => wrappedPeriods(await ref.watch(_allPlaysProvider.future)),
);

/// This month's plays still to go before it has a Wrapped (0 = it has one).
final wrappedPlaysToGoProvider = FutureProvider.autoDispose<int>((ref) async {
  final now = DateTime.now();
  return wrappedPlaysToGo(await ref.watch(_allPlaysProvider.future), WrappedPeriod.month(now.year, now.month));
});

/// One period's Wrapped; null when it has too few plays.
final wrappedProvider = FutureProvider.autoDispose.family<Wrapped?, WrappedPeriod>((ref, period) async {
  final plays = await ref.watch(_allPlaysProvider.future);
  final ids = {for (final p in plays) if (period.contains(p.playedAt)) p.trackId}.toList();
  final tracks = {for (final t in await ref.read(libraryRepositoryProvider).getTracks(ids)) t.id: t};
  // A snapshot from the database, like the plays: analysis running in the background mustn't
  // redo the story. Not through the smart-group providers: one nobody listens to is paused,
  // and its future never came (the story stayed on its spinner).
  final analysis = ref.read(analysisRepositoryProvider);
  final data = await analysis.watchVibeData().first;
  final labels = await analysis.watchLabels().first;
  final predicted = data.length > 1500 ? await compute(classifyLibrary, data) : classifyLibrary(data);
  final results = applyLabels(predicted, labels);
  return buildWrapped(period, plays, tracks, moodOf: {
    for (final d in data)
      if (d.scores != null) d.trackId: results[d.trackId]?.mood?.name,
  });
});

/// The new month's banner on Home: last month's Wrapped, in the first [wrappedBannerDays]
/// days of a month, until it is opened or closed. Null = no banner.
final wrappedBannerProvider = FutureProvider.autoDispose<WrappedPeriod?>((ref) async {
  final now = DateTime.now();
  if (now.day > wrappedBannerDays) return null;
  final last = WrappedPeriod.lastMonth(now);
  final hidden = ref.watch(stringSettingProvider(SettingsKeys.wrappedBannerHidden)).value;
  if (hidden == last.id) return null;
  final periods = await ref.watch(wrappedPeriodsProvider.future);
  return periods.contains(last) ? last : null;
});

const wrappedBannerDays = 7;

/// The banner stays away for [period] once opened or closed.
Future<void> hideWrappedBanner(WidgetRef ref, WrappedPeriod period) =>
    ref.read(settingsRepositoryProvider).setSetting(SettingsKeys.wrappedBannerHidden, period.id);

/// "November 2026", "2026".
String wrappedTitle(WrappedPeriod p) => p.isYear ? '${p.year}' : '${monthName(p.month!)} ${p.year}';

/// "November", "Noyabr".
String monthName(int month) => l10n.monthNames.split(',')[month - 1].trim();

/// A mood id from the engine → the mood itself.
Mood? moodById(String id) => Mood.values.where((m) => m.name == id).firstOrNull;

/// 1820 → "1 820" (a thin space, readable in both languages).
String groupDigits(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('\u2009');
    out.write(s[i]);
  }
  return out.toString();
}

/// "2h 26m", "48m".
String wrappedDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? l10n.durHoursMinutes(h, m) : l10n.durMinutes(d.inMinutes);
}

/// The listener's time of day: its name and emoji.
({String name, String emoji}) listeningTimeLabel(ListeningTime t) => switch (t) {
      ListeningTime.morning => (name: l10n.wrappedMorning, emoji: '🌅'),
      ListeningTime.afternoon => (name: l10n.wrappedAfternoon, emoji: '☀️'),
      ListeningTime.evening => (name: l10n.wrappedEvening, emoji: '🌆'),
      ListeningTime.night => (name: l10n.wrappedNight, emoji: '🌙'),
    };
