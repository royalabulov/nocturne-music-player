import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/repositories/library_repository.dart';

/// Size: 0 – 2 MB in 50 KB steps. Right end = no upper limit.
const _sizeMaxKb = 2000.0;
const _sizeStepKb = 50;

/// Length: 0 – 5 min in 5 s steps. Right end = no upper limit.
const _lenMaxSec = 300.0;
const _lenStepSec = 5;

String formatKb(double kb) {
  if (kb >= _sizeMaxKb) return 'No limit';
  if (kb >= 1000) return '${(kb / 1000).toStringAsFixed(kb % 1000 == 0 ? 0 : 1)} MB';
  return '${kb.round()} KB';
}

String formatSec(double s) {
  if (s >= _lenMaxSec) return 'No limit';
  final m = s ~/ 60, sec = (s % 60).round();
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// Slider values ↔ [TrackFilter] (at the max end = null, i.e. no limit).
@visibleForTesting
TrackFilter filterFromRanges(RangeValues size, RangeValues length) => TrackFilter(
      minBytes: (size.start * 1024).round(),
      maxBytes: size.end >= _sizeMaxKb ? null : (size.end * 1024).round(),
      minMs: (length.start * 1000).round(),
      maxMs: length.end >= _lenMaxSec ? null : (length.end * 1000).round(),
    );

/// Settings → Library filter: which files show up in the library.
/// Keeps voice notes, ringtones and half-downloaded files out.
class LibraryFilterGroup extends ConsumerStatefulWidget {
  const LibraryFilterGroup({super.key});

  @override
  ConsumerState<LibraryFilterGroup> createState() => _LibraryFilterGroupState();
}

class _LibraryFilterGroupState extends ConsumerState<LibraryFilterGroup> {
  /// Local value while dragging; saved on release (so every tick doesn't
  /// re-query every list).
  RangeValues? _size, _length;

  static RangeValues _sizeOf(TrackFilter f) => RangeValues(
        (f.minBytes / 1024).clamp(0, _sizeMaxKb).toDouble(),
        f.maxBytes == null ? _sizeMaxKb : (f.maxBytes! / 1024).clamp(0, _sizeMaxKb).toDouble(),
      );

  static RangeValues _lengthOf(TrackFilter f) => RangeValues(
        (f.minMs / 1000).clamp(0, _lenMaxSec).toDouble(),
        f.maxMs == null ? _lenMaxSec : (f.maxMs! / 1000).clamp(0, _lenMaxSec).toDouble(),
      );

  void _commit() {
    final f = ref.read(trackFilterProvider);
    final next = filterFromRanges(_size ?? _sizeOf(f), _length ?? _lengthOf(f));
    _size = _length = null;
    ref.read(trackFilterProvider.notifier).set(next);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(trackFilterProvider);
    final shown = ref.watch(libraryStatsProvider).value?.trackCount;
    final size = _size ?? _sizeOf(filter);
    final length = _length ?? _lengthOf(filter);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Library filter', style: AppTypography.bodyMd)),
              if (filter != TrackFilter.defaults)
                GestureDetector(
                  onTap: () => ref.read(trackFilterProvider.notifier).reset(),
                  child: Text('Reset', style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Only songs inside both ranges are shown. Hides voice notes, ringtones and half-downloaded files.'
            '${shown == null ? '' : '  •  $shown songs shown'}',
            style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          _RangeRow(
            title: 'By size',
            label: '${formatKb(size.start)} – ${formatKb(size.end)}',
            values: size,
            max: _sizeMaxKb,
            divisions: _sizeMaxKb ~/ _sizeStepKb,
            ends: const ('0 KB', '2 MB+'),
            onChanged: (v) => setState(() => _size = v),
            onChangeEnd: (_) => _commit(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RangeRow(
            title: 'By length',
            label: '${formatSec(length.start)} – ${formatSec(length.end)}',
            values: length,
            max: _lenMaxSec,
            divisions: _lenMaxSec ~/ _lenStepSec,
            ends: const ('0 sec', '5 min+'),
            onChanged: (v) => setState(() => _length = v),
            onChangeEnd: (_) => _commit(),
          ),
        ],
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.title,
    required this.label,
    required this.values,
    required this.max,
    required this.divisions,
    required this.ends,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title, label;
  final RangeValues values;
  final double max;
  final int divisions;
  final (String, String) ends;
  final ValueChanged<RangeValues> onChanged, onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.labelMd.copyWith(color: AppColors.textPrimary))),
            Text(label, style: AppTypography.labelMd.copyWith(color: AppColors.cyan)),
          ],
        ),
        RangeSlider(
          values: values,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(ends.$1, style: AppTypography.labelXs),
            Text(ends.$2, style: AppTypography.labelXs),
          ],
        ),
      ],
    );
  }
}
