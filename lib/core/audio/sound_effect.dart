import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/settings_repository.dart';
import '../di/providers.dart';
import 'player_providers.dart';

/// Slowed / sped up, with or without reverb: how every song sounds until it is set back.
class SoundEffect {
  const SoundEffect({this.speed = 1, this.reverb = 0});

  /// Speed and pitch together, like a record played slower or faster (1 = normal).
  final double speed;

  /// 0 = off .. 1 = most.
  final double reverb;

  static const minSpeed = 0.7, maxSpeed = 1.3;

  static const normal = SoundEffect();
  static const slowedReverb = SoundEffect(speed: 0.85, reverb: 0.6);
  static const spedUp = SoundEffect(speed: 1.25);
  static const presets = [normal, slowedReverb, spedUp];

  bool get isOn => this != normal;

  SoundEffect copyWith({double? speed, double? reverb}) => SoundEffect(
        speed: _speed(speed ?? this.speed),
        reverb: _reverb(reverb ?? this.reverb),
      );

  /// Sliders move in hundredths: 0.849999 must still match the 0.85 preset.
  static double _speed(double v) => (v.clamp(minSpeed, maxSpeed) * 100).round() / 100;
  static double _reverb(double v) => (v.clamp(0.0, 1.0) * 100).round() / 100;

  String encode() => jsonEncode({'speed': speed, 'reverb': reverb});

  /// Also reads what a backup file brought in: anything out of range is brought back in.
  static SoundEffect decode(String? s) {
    if (s == null || s.isEmpty) return normal;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return SoundEffect(
        speed: _speed((j['speed'] as num?)?.toDouble() ?? 1),
        reverb: _reverb((j['reverb'] as num?)?.toDouble() ?? 0),
      );
    } catch (_) {
      return normal;
    }
  }

  @override
  bool operator ==(Object other) => other is SoundEffect && other.speed == speed && other.reverb == reverb;

  @override
  int get hashCode => Object.hash(speed, reverb);

  @override
  String toString() => 'SoundEffect(${speed}x, reverb $reverb)';
}

/// The effect in use: stored, and applied to the player at start and on every change.
class SoundEffectController extends Notifier<SoundEffect> {
  @override
  SoundEffect build() {
    unawaited(_load());
    return SoundEffect.normal;
  }

  /// A change made before the stored one was read wins over it.
  bool _changed = false;

  Future<void> _load() async {
    final raw = await ref.read(settingsRepositoryProvider).getSetting(SettingsKeys.soundEffect);
    if (!ref.mounted || _changed) return;
    state = SoundEffect.decode(raw);
    await _apply();
  }

  /// While a slider moves: heard at once, stored when it is let go ([set]).
  Future<void> preview(SoundEffect e) async {
    _changed = true;
    state = e;
    await _apply();
  }

  Future<void> set(SoundEffect e) async {
    _changed = true;
    state = e;
    await ref.read(settingsRepositoryProvider).setSetting(SettingsKeys.soundEffect, e.encode());
    await _apply();
  }

  Future<void> _apply() =>
      ref.read(audioHandlerProvider).setSoundEffect(speed: state.speed, reverb: state.reverb);
}

final soundEffectProvider = NotifierProvider<SoundEffectController, SoundEffect>(SoundEffectController.new);

/// Whether this phone can make the reverb; without it the effect sheet offers speed only.
final reverbWorksProvider = FutureProvider<bool>((ref) => ref.watch(playbackServiceProvider).reverbWorks());
