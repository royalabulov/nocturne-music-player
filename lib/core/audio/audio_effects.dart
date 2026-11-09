import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../l10n/l10n.dart';

/// One EQ band reported by the device.
class EqBand {
  const EqBand({required this.index, required this.centerHz, required this.minDb, required this.maxDb});
  final int index;
  final double centerHz;
  final double minDb, maxDb;

  String get label => centerHz >= 1000 ? '${(centerHz / 1000).toStringAsFixed(centerHz % 1000 == 0 ? 0 : 1)}k' : '${centerHz.round()}';
}

/// EQ preset: a 10-point curve (31 Hz … 16 kHz). Devices have a different number
/// of bands (usually 5) → log-interpolated by centre frequency.
class EqPreset {
  const EqPreset(this.name, this.curve);
  final String name;
  final List<double> curve; // dB, 10 values

  /// [name] is the id saved in the settings; this is what the screen shows.
  String get label => switch (name) {
        'Flat' => l10n.presetFlat,
        'Bass Boost' => l10n.presetBassBoost,
        'Vocal' => l10n.presetVocal,
        'Treble' => l10n.presetTreble,
        'Rock' => l10n.presetRock,
        'Pop' => l10n.presetPop,
        'Electronic' => l10n.presetElectronic,
        'Headphones' => l10n.presetHeadphones,
        'Speaker' => l10n.presetSpeaker,
        'Custom' => l10n.presetCustom,
        _ => name,
      };

  static const freqs = [31.0, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  static const flat = EqPreset('Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  static const bassBoost = EqPreset('Bass Boost', [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]);
  static const vocal = EqPreset('Vocal', [-2, -1, 0, 1, 3, 4, 3, 1, 0, -1]);
  static const treble = EqPreset('Treble', [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]);
  static const rock = EqPreset('Rock', [4, 3, 2, 0, -1, 0, 2, 3, 4, 4]);
  static const pop = EqPreset('Pop', [-1, 0, 2, 3, 3, 2, 0, -1, -1, -1]);
  static const electronic = EqPreset('Electronic', [5, 4, 1, 0, -1, 1, 2, 3, 4, 5]);
  static const headphones = EqPreset('Headphones', [2, 1, 0, 0, 0, 1, 2, 2, 1, 1]);
  static const speaker = EqPreset('Speaker', [0, 0, 2, 3, 2, 1, 2, 3, 3, 2]);
  static const custom = EqPreset('Custom', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

  static const all = [flat, bassBoost, vocal, treble, rock, pop, electronic, headphones, speaker, custom];

  static EqPreset byName(String? name) => all.firstWhere((p) => p.name == name, orElse: () => flat);

  /// This preset's dB value for [band] (log-frequency interpolation).
  double gainAt(double hz) {
    final x = log(hz.clamp(freqs.first, freqs.last));
    for (var i = 0; i < freqs.length - 1; i++) {
      final x0 = log(freqs[i]), x1 = log(freqs[i + 1]);
      if (x <= x1) {
        final t = ((x - x0) / (x1 - x0)).clamp(0.0, 1.0);
        return curve[i] + (curve[i + 1] - curve[i]) * t;
      }
    }
    return curve.last;
  }
}

/// The same effects for both players — during the A/B crossfade both must go
/// through the same EQ. Android system Equalizer (bound to the ExoPlayer audio session).
/// On iOS the pipeline is empty (phase 5+).
class NocturneEffects {
  /// [equalizer]: false on a phone that can't make a system equalizer (EqualizerProbe.kt).
  /// just_audio builds one for every player with no try, so there no song played at all;
  /// without it the music plays and the equalizer screen says it isn't there.
  /// [android]: tests stand in for the phone.
  NocturneEffects({bool equalizer = true, @visibleForTesting bool? android})
      : _withEq = equalizer && (android ?? (!kIsWeb && Platform.isAndroid)) {
    _eqs = [_newEq(), _newEq()];
  }

  final bool _withEq;
  late final List<AndroidEqualizer?> _eqs;
  AndroidEqualizer? _newEq() => _withEq ? AndroidEqualizer() : null;

  /// The effects for player [slot] (0 or 1).
  AudioPipeline pipeline(int slot) => AudioPipeline(androidAudioEffects: [?_eqs[slot]]);

  /// A new equalizer for player [slot], whose player is being replaced (an equalizer belongs to
  /// one player). It gets the current on/off state and, once its player has loaded, the gains.
  AudioPipeline renew(int slot) {
    final eq = _eqs[slot] = _newEq();
    if (eq != null) {
      unawaited(eq.setEnabled(_enabled));
      final gains = _applied;
      if (gains.isNotEmpty) unawaited(eq.parameters.then((_) => _setBands(eq, gains)));
    }
    return pipeline(slot);
  }

  bool get supported => _withEq;

  bool _enabled = false;
  List<double> _applied = const [];

  /// The gains last sent to the equalizers (after [withHeadroom]).
  @visibleForTesting
  List<double> get applied => _applied;

  List<EqBand>? _bands;

  /// The device's bands. Waits until a player has loaded once (the system equalizer exists
  /// only from then on); empty where there is none.
  Future<List<EqBand>> bands() async {
    if (_bands != null) return _bands!;
    final eq = _eqs[0];
    if (eq == null) return const [];
    try {
      final p = await eq.parameters;
      return _bands = [
        for (final b in p.bands)
          EqBand(index: b.index, centerHz: b.centerFrequency, minDb: p.minDecibels, maxDb: p.maxDecibels),
      ];
    } catch (e) {
      debugPrint('NocturneEffects: EQ parameters unavailable: $e');
      return const [];
    }
  }

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    for (final eq in _eqs) {
      await eq?.setEnabled(on);
    }
  }

  /// dB per band (length = bands().length). Applied to both players, lowered by
  /// [withHeadroom] so a boost can't push the song past full scale.
  Future<void> setGains(List<double> db) async {
    final gains = _applied = withHeadroom(db);
    final known = await bands();
    for (final eq in _eqs) {
      if (eq != null) await _setBands(eq, gains);
    }
    if (known.isEmpty) _bands = null; // try again next time
  }

  Future<void> _setBands(AndroidEqualizer eq, List<double> db) async {
    try {
      final p = await eq.parameters;
      for (var i = 0; i < p.bands.length && i < db.length; i++) {
        await p.bands[i].setGain(db[i].clamp(p.minDecibels, p.maxDecibels));
      }
    } catch (e) {
      debugPrint('NocturneEffects: setGains failed: $e');
    }
  }

  /// The curve moved down by its highest boost: the shape stays, nothing is above 0 dB.
  /// Songs are mastered close to full scale, so "Bass Boost" with the bass slider (+14 dB at
  /// 60 Hz) clipped and crackled, and came on that much louder than the song itself.
  static List<double> withHeadroom(List<double> db) {
    final top = db.fold(0.0, max);
    return [for (final g in db) g - top];
  }

  /// Preset + bass boost (0..1) → dB list for the device's bands.
  Future<List<double>> gainsFor(EqPreset preset, {double bassBoost = 0, List<double>? custom}) async {
    final bands = await this.bands();
    return [
      for (var i = 0; i < bands.length; i++)
        () {
          final b = bands[i];
          var g = preset.name == 'Custom' && custom != null && i < custom.length
              ? custom[i]
              : preset.gainAt(b.centerHz);
          // Bass boost: +0..8 dB on bands below 250 Hz (more as frequency drops)
          if (bassBoost > 0 && b.centerHz < 300) {
            g += bassBoost * 8 * (1 - (log(b.centerHz) - log(31)) / (log(300) - log(31))).clamp(0.3, 1.0);
          }
          return g.clamp(b.minDb, b.maxDb);
        }(),
    ];
  }
}
