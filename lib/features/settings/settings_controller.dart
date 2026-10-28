import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_effects.dart';
import '../../core/audio/output_detector.dart';
import '../../core/di/providers.dart';
import '../player/player_providers.dart';
import 'audio_settings.dart';

final outputDetectorProvider = Provider<OutputDetector>((ref) {
  final d = OutputDetector();
  ref.onDispose(d.dispose);
  return d;
});

final outputKindProvider = StreamProvider<OutputKind>(
  (ref) => ref.watch(outputDetectorProvider).stream,
);

/// Single source of audio settings. A change → write to the DB + apply to the handler/EQ.
class AudioSettingsController extends Notifier<AudioSettings> {
  static const _key = 'audioSettings';
  StreamSubscription? _outSub, _trackSub;

  @override
  AudioSettings build() {
    ref.onDispose(() {
      _outSub?.cancel();
      _trackSub?.cancel();
    });
    _load();
    // When the output changes (headphones plugged in / BT connected) the auto preset updates
    _outSub = ref.read(outputDetectorProvider).stream.listen((_) => _applyEq());
    // EQ parameters don't exist until the player's first load → re-apply on every track
    _trackSub = ref.read(audioHandlerProvider).currentTrack.listen((_) => _applyEq());
    return const AudioSettings();
  }

  Future<void> _load() async {
    final raw = await ref.read(libraryRepositoryProvider).getSetting(_key);
    state = AudioSettings.decode(raw);
    await _applyAll();
  }

  Future<void> _save() => ref.read(libraryRepositoryProvider).setSetting(_key, state.encode());

  Future<void> _applyAll() async {
    final h = ref.read(audioHandlerProvider);
    h.crossfade = state.crossfadeDuration;
    h.replayGain = state.replayGain;
    await h.applyGainNow();
    await _applyEq();
  }

  Future<void> _applyEq() async {
    final effects = ref.read(audioHandlerProvider).effects;
    if (!effects.supported) return;
    await effects.setEnabled(state.eqEnabled);
    if (!state.eqEnabled) return;
    final output = ref.read(outputDetectorProvider).current;
    final gains = await effects.gainsFor(
      state.effectivePreset(output),
      bassBoost: state.bassBoost,
      custom: state.customGains,
    );
    await effects.setGains(gains);
  }

  Future<void> _update(AudioSettings s) async {
    state = s;
    await _save();
    await _applyAll();
  }

  // ── public API ────────────────────────────────────────────

  Future<void> setCrossfade(bool on) => _update(state.copyWith(crossfade: on));
  Future<void> setCrossfadeSec(double sec) => _update(state.copyWith(crossfadeSec: sec));
  Future<void> setReplayGain(bool on) => _update(state.copyWith(replayGain: on));
  Future<void> setEqEnabled(bool on) => _update(state.copyWith(eqEnabled: on));
  Future<void> setAutoPreset(bool on) => _update(state.copyWith(autoPreset: on));
  Future<void> setBassBoost(double v) => _update(state.copyWith(bassBoost: v.clamp(0, 1)));

  /// With auto preset on, saved for the current output; otherwise globally.
  Future<void> setPreset(String name) {
    if (state.autoPreset) {
      final out = ref.read(outputDetectorProvider).current;
      return _update(state.copyWith(presetByOutput: {...state.presetByOutput, out.name: name}));
    }
    return _update(state.copyWith(preset: name));
  }

  /// Changing a band with a slider switches the preset to "Custom" automatically.
  Future<void> setCustomGain(int band, double db, int bandCount) async {
    final gains = List<double>.filled(bandCount, 0);
    // Start from the current effective preset so the slider doesn't "jump"
    final out = ref.read(outputDetectorProvider).current;
    final current = state.effectivePreset(out);
    final effects = ref.read(audioHandlerProvider).effects;
    final base = current.name == 'Custom' && state.customGains.length == bandCount
        ? state.customGains
        : await effects.gainsFor(current);
    for (var i = 0; i < bandCount && i < base.length; i++) {
      gains[i] = base[i];
    }
    if (band < bandCount) gains[band] = db;
    var s = state.copyWith(customGains: gains);
    s = s.autoPreset
        ? s.copyWith(presetByOutput: {...s.presetByOutput, out.name: 'Custom'})
        : s.copyWith(preset: 'Custom');
    await _update(s);
  }

  /// For the EQ screen: current band values (preset + bass boost applied).
  Future<List<double>> currentGains() async {
    final effects = ref.read(audioHandlerProvider).effects;
    final out = ref.read(outputDetectorProvider).current;
    return effects.gainsFor(state.effectivePreset(out), bassBoost: state.bassBoost, custom: state.customGains);
  }

  EqPreset get effectivePreset => state.effectivePreset(ref.read(outputDetectorProvider).current);
}

final audioSettingsProvider =
    NotifierProvider<AudioSettingsController, AudioSettings>(AudioSettingsController.new);
