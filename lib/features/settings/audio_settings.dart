import 'dart:convert';

import '../../core/audio/audio_effects.dart';
import '../../core/audio/output_detector.dart';

/// Settings → Audio Engine. Stored as JSON in scan_state['audioSettings'].
class AudioSettings {
  const AudioSettings({
    this.crossfade = false,
    this.crossfadeSec = 3.5,
    this.eqEnabled = false,
    this.preset = 'Flat',
    this.customGains = const [],
    this.bassBoost = 0,
    this.autoPreset = true,
    this.presetByOutput = defaultPresetByOutput,
    this.replayGain = true,
  });

  /// Default per output while auto preset is on.
  static const defaultPresetByOutput = {
    'headphones': 'Headphones',
    'bluetooth': 'Flat',
    'speaker': 'Speaker',
  };

  final bool crossfade;
  final double crossfadeSec;
  final bool eqEnabled;

  /// Preset used when auto preset is off.
  final String preset;

  /// Band values (dB) of the "Custom" preset, one per device band.
  final List<double> customGains;

  /// 0..1
  final double bassBoost;
  final bool autoPreset;

  /// OutputKind.name → preset name.
  final Map<String, String> presetByOutput;
  final bool replayGain;

  /// The preset applied right now (auto → by output).
  EqPreset effectivePreset(OutputKind output) => EqPreset.byName(
        autoPreset ? (presetByOutput[output.name] ?? defaultPresetByOutput[output.name]) : preset,
      );

  Duration get crossfadeDuration => crossfade ? Duration(milliseconds: (crossfadeSec * 1000).round()) : Duration.zero;

  AudioSettings copyWith({
    bool? crossfade,
    double? crossfadeSec,
    bool? eqEnabled,
    String? preset,
    List<double>? customGains,
    double? bassBoost,
    bool? autoPreset,
    Map<String, String>? presetByOutput,
    bool? replayGain,
  }) =>
      AudioSettings(
        crossfade: crossfade ?? this.crossfade,
        crossfadeSec: crossfadeSec ?? this.crossfadeSec,
        eqEnabled: eqEnabled ?? this.eqEnabled,
        preset: preset ?? this.preset,
        customGains: customGains ?? this.customGains,
        bassBoost: bassBoost ?? this.bassBoost,
        autoPreset: autoPreset ?? this.autoPreset,
        presetByOutput: presetByOutput ?? this.presetByOutput,
        replayGain: replayGain ?? this.replayGain,
      );

  Map<String, dynamic> toJson() => {
        'crossfade': crossfade,
        'crossfadeSec': crossfadeSec,
        'eqEnabled': eqEnabled,
        'preset': preset,
        'customGains': customGains,
        'bassBoost': bassBoost,
        'autoPreset': autoPreset,
        'presetByOutput': presetByOutput,
        'replayGain': replayGain,
      };

  static AudioSettings fromJson(Map<String, dynamic> j) => AudioSettings(
        crossfade: j['crossfade'] as bool? ?? false,
        crossfadeSec: (j['crossfadeSec'] as num?)?.toDouble() ?? 3.5,
        eqEnabled: j['eqEnabled'] as bool? ?? false,
        preset: j['preset'] as String? ?? 'Flat',
        customGains: [for (final g in (j['customGains'] as List? ?? const [])) (g as num).toDouble()],
        bassBoost: (j['bassBoost'] as num?)?.toDouble() ?? 0,
        autoPreset: j['autoPreset'] as bool? ?? true,
        presetByOutput: {
          ...defaultPresetByOutput,
          ...((j['presetByOutput'] as Map?)?.cast<String, String>() ?? const {}),
        },
        replayGain: j['replayGain'] as bool? ?? true,
      );

  String encode() => jsonEncode(toJson());
  static AudioSettings decode(String? s) {
    if (s == null || s.isEmpty) return const AudioSettings();
    try {
      return fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return const AudioSettings();
    }
  }
}
