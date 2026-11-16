import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player_providers.dart';
import '../../core/constants.dart';
import '../../core/di/providers.dart';
import '../../core/ui/toast.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../l10n/l10n.dart';
import '../smart_groups/smart_groups.dart';
import 'radio_controller.dart';

/// "Radio from this song" (a song's ••• menu, Now Playing). Says why when no radio starts.
/// Takes the container, not a widget's ref: the menu that asked is closed by the time the
/// radio has started.
Future<void> startRadio(ProviderContainer container, Track seed) async {
  final radio = container.read(radioProvider.notifier);
  // Analyzing the song first can take a second or two: say something if it does
  final slow = Timer(const Duration(milliseconds: 600), () => showToast(l10n.radioStarting));
  final RadioStart result;
  try {
    result = await radio.start(seed);
  } finally {
    slow.cancel();
  }
  switch (result) {
    case RadioStart.started || RadioStart.busy:
      break;
    case RadioStart.notAnalyzed:
      showToast(l10n.radioNotAnalyzed, error: true);
    case RadioStart.notReady:
      await _sayWhyNotReady(container);
  }
}

/// Too few songs analyzed for a radio: whether waiting helps, and how long.
Future<void> _sayWhyNotReady(ProviderContainer container) async {
  final p = await container.read(analysisRepositoryProvider).watchProgress(kVibeAnalysisVersion).first;
  final analysis = container.read(smartAnalysisProvider.notifier);
  // Everything analyzed, still too few: the library is too small, or most files can't be read
  if (p.complete) return showToast(l10n.radioTooFewSongs(RadioController.minSongs + 1));
  final on = await container.read(settingsRepositoryProvider).getSetting(SettingsKeys.smartAnalysis) != 'false';
  // Off: it would never get ready, however long one waits
  if (!on) {
    return showToast(
      l10n.radioAnalysisOff,
      action: ToastAction(l10n.turnOn, () {
        unawaited(analysis.setEnabled(true));
        showToast(l10n.radioAnalysisTurnedOn);
      }),
    );
  }
  final left = analysis.timeLeft(p.total - p.done);
  showToast(left == null
      ? l10n.radioNotReady(p.done, p.total)
      : l10n.radioNotReadyTimeLeft(p.done, p.total, aboutTime(left)));
}

/// "13 minutes", "1 h 20 min". Rounded up: "about 0 minutes left" says nothing.
@visibleForTesting
String aboutTime(Duration d) {
  final minutes = (d.inSeconds / 60).ceil().clamp(1, 1 << 30);
  return minutes < 60 ? l10n.minutesLong(minutes) : l10n.hoursMinutesLong(minutes ~/ 60, minutes % 60);
}

/// Menu → Radio: from the song playing, or else the one played last.
Future<void> startRadioFromNowPlaying(ProviderContainer container) async {
  final seed = container.read(audioHandlerProvider).currentTrackValue ??
      (await container.read(historyRepositoryProvider).watchRecentlyPlayed(limit: 1).first).firstOrNull?.track;
  if (seed == null) return showToast(l10n.radioNothingPlaying);
  await startRadio(container, seed);
}
