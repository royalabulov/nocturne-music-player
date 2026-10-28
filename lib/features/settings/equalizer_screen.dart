import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_effects.dart';
import '../../core/audio/output_detector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../shared/codec_chip.dart';
import '../player/player_providers.dart';
import 'settings_controller.dart';

/// System EQ (Android Equalizer). The number of bands depends on the device (usually 5).
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  List<EqBand> _bands = const [];
  List<double> _gains = const [];
  int? _dragging;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final effects = ref.read(audioHandlerProvider).effects;
    final bands = await effects.bands();
    final gains = await ref.read(audioSettingsProvider.notifier).currentGains();
    if (!mounted) return;
    setState(() {
      _bands = bands;
      _gains = gains;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(audioSettingsProvider);
    final ctrl = ref.read(audioSettingsProvider.notifier);
    final output = ref.watch(outputKindProvider).value ?? OutputKind.speaker;
    final preset = s.effectivePreset(output);
    // Refresh the sliders when the preset / bass boost / output changes
    ref.listen(audioSettingsProvider, (_, _) => _refresh());
    ref.listen(outputKindProvider, (_, _) => _refresh());

    return Scaffold(
      backgroundColor: AppColors.void_,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.textPrimary,
                ),
                Expanded(child: Text('Equalizer', style: AppTypography.headlineLg)),
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Switch(value: s.eqEnabled, onChanged: ctrl.setEqEnabled),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Row(
                children: [
                  Icon(_outputIcon(output), size: 18, color: AppColors.cyan),
                  const SizedBox(width: 6),
                  Text(output.label, style: AppTypography.labelMd),
                  const SizedBox(width: 8),
                  if (s.autoPreset) const CodecChip('AUTO'),
                  const Spacer(),
                  Text(preset.name, style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Preset chips
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                itemCount: EqPreset.all.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (_, i) {
                  final p = EqPreset.all[i];
                  final active = p.name == preset.name;
                  return GestureDetector(
                    onTap: () => ctrl.setPreset(p.name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.electric : AppColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        boxShadow: active ? Glow.accent : null,
                      ),
                      child: Text(p.name,
                          style: AppTypography.labelMd.copyWith(
                              color: active ? Colors.white : AppColors.textSecondary)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Bands
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: SolidCard(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.lg, AppSpacing.sm, AppSpacing.md),
                child: _bands.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'Play any track first — the system equalizer becomes available once audio is initialised.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                        ),
                      )
                    : Opacity(
                        opacity: s.eqEnabled ? 1 : .4,
                        child: SizedBox(
                          height: 260,
                          child: Row(
                            children: [
                              for (var i = 0; i < _bands.length; i++)
                                Expanded(child: _BandSlider(
                                  band: _bands[i],
                                  value: i < _gains.length ? _gains[i] : 0,
                                  enabled: s.eqEnabled,
                                  onChanged: (v) => setState(() {
                                    _dragging = i;
                                    _gains = [..._gains]..[i] = v;
                                  }),
                                  onChangeEnd: (v) {
                                    _dragging = null;
                                    ctrl.setCustomGain(i, v, _bands.length);
                                  },
                                )),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Bass boost
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: SolidCard(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speaker_rounded, size: 18, color: AppColors.cyan),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Bass Boost', style: AppTypography.bodyMd)),
                        Text('${(s.bassBoost * 100).round()}%',
                            style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
                      ],
                    ),
                    Slider(
                      value: s.bassBoost,
                      onChanged: s.eqEnabled ? (v) => ctrl.setBassBoost(v) : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Text(
                s.autoPreset
                    ? 'Auto preset is on: the preset you pick here is remembered for "${output.label}" and switches when you change output.'
                    : 'Auto preset is off: this preset applies to every output.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textMuted),
              ),
            ),
            if (_dragging != null) const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  static IconData _outputIcon(OutputKind k) => switch (k) {
        OutputKind.headphones => Icons.headphones_rounded,
        OutputKind.bluetooth => Icons.bluetooth_audio_rounded,
        OutputKind.speaker => Icons.speaker_rounded,
      };
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final EqBand band;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}',
            style: AppTypography.labelXs.copyWith(color: AppColors.cyan)),
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: value.clamp(band.minDb, band.maxDb),
                min: band.minDb,
                max: band.maxDb,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(band.label, style: AppTypography.labelXs),
      ],
    );
  }
}
