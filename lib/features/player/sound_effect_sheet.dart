import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sound_effect.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../l10n/l10n.dart';
import '../../shared/cover_accent.dart';
import '../../shared/nocturne_sheet.dart';
import '../../shared/tap_target.dart';

/// Now Playing, next to the lyrics: slowed / sped up and reverb. Lit while an effect is on,
/// since it stays on for every song until it is set back.
class SoundEffectButton extends ConsumerWidget {
  const SoundEffectButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(soundEffectProvider.select((e) => e.isOn));
    return IconButton(
      tooltip: l10n.soundEffect,
      onPressed: () => showSoundEffectSheet(context),
      icon: Icon(on ? Icons.slow_motion_video_rounded : Icons.slow_motion_video_outlined, size: 24),
      color: on ? CoverAccent.of(context).line : AppColors.textSecondary,
    );
  }
}

/// "0.85× · Reverb" for the line under the title; null when the sound is normal.
String? soundEffectLabel(SoundEffect e) => !e.isOn
    ? null
    : [
        if (e.speed != 1) l10n.speedValue(_x(e.speed)),
        if (e.reverb > 0) l10n.reverb,
      ].join('  ·  ');

String _x(double speed) => speed.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

Future<void> showSoundEffectSheet(BuildContext context) => showNocturneSheet(
      context,
      scrollControlled: true,
      scrollable: true,
      child: const _SoundEffectSheet(),
    );

class _SoundEffectSheet extends ConsumerWidget {
  const _SoundEffectSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(soundEffectProvider);
    final ctrl = ref.read(soundEffectProvider.notifier);
    // Until the phone has answered, the reverb is offered: most phones have it
    final reverbWorks = ref.watch(reverbWorksProvider).value ?? true;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetTitle(l10n.soundEffect, subtitle: l10n.soundEffectHint),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (preset, label) in [
                (SoundEffect.normal, l10n.soundNormal),
                (SoundEffect.slowedReverb, l10n.soundSlowedReverb),
                (SoundEffect.spedUp, l10n.soundSpedUp),
              ])
                _PresetPill(
                  label: label,
                  selected: e == (reverbWorks ? preset : preset.copyWith(reverb: 0)),
                  onTap: () => ctrl.set(reverbWorks ? preset : preset.copyWith(reverb: 0)),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _EffectSlider(
          title: l10n.speed,
          valueLabel: l10n.speedValue(_x(e.speed)),
          value: e.speed,
          min: SoundEffect.minSpeed,
          max: SoundEffect.maxSpeed,
          divisions: 60,
          labels: [l10n.speedValue('0.7'), l10n.speedValue('1'), l10n.speedValue('1.3')],
          onChanged: (v) => ctrl.preview(e.copyWith(speed: v)),
          onChangeEnd: (v) => ctrl.set(e.copyWith(speed: v)),
        ),
        _EffectSlider(
          title: l10n.reverb,
          valueLabel: e.reverb == 0 ? l10n.off : '${(e.reverb * 100).round()}%',
          value: reverbWorks ? e.reverb : 0,
          min: 0,
          max: 1,
          divisions: 20,
          labels: [l10n.off, l10n.reverbMax],
          onChanged: reverbWorks ? (v) => ctrl.preview(e.copyWith(reverb: v)) : null,
          onChangeEnd: reverbWorks ? (v) => ctrl.set(e.copyWith(reverb: v)) : null,
          note: reverbWorks ? null : l10n.reverbUnavailable,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _PresetPill extends StatelessWidget {
  const _PresetPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TapTarget(
      label: label,
      selected: selected,
      onTap: onTap,
      child: Material(
        color: selected ? AppColors.accentFill : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              style: AppTypography.labelMd.copyWith(color: selected ? Colors.white : AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _EffectSlider extends StatelessWidget {
  const _EffectSlider({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labels,
    required this.onChanged,
    required this.onChangeEnd,
    this.note,
  });
  final String title, valueLabel;
  final double value, min, max;
  final int divisions;
  final List<String> labels;
  final ValueChanged<double>? onChanged, onChangeEnd;

  /// Why the slider can't be moved.
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.xs, AppSpacing.screenH, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.bodyMd)),
              Text(valueLabel, style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (_) => valueLabel,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final l in labels) Text(l, style: AppTypography.labelXs)],
          ),
          if (note case final n?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(n, style: AppTypography.labelSm.copyWith(color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}
