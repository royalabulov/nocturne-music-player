import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player_providers.dart';
import '../../core/constants.dart';
import '../../core/di/providers.dart';
import '../../core/ui/toast.dart';
import '../../domain/entities/track.dart';
import '../../l10n/l10n.dart';
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
      final p = await container.read(analysisRepositoryProvider).watchProgress(kVibeAnalysisVersion).first;
      showToast(l10n.radioNotReady(p.done, p.total));
  }
}

/// Menu → Radio: from the song playing, or else the one played last.
Future<void> startRadioFromNowPlaying(ProviderContainer container) async {
  final seed = container.read(audioHandlerProvider).currentTrackValue ??
      (await container.read(historyRepositoryProvider).watchRecentlyPlayed(limit: 1).first).firstOrNull?.track;
  if (seed == null) return showToast(l10n.radioNothingPlaying);
  await startRadio(container, seed);
}
