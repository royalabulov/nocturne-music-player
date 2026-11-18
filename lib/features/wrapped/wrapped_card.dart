import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/toast.dart';
import '../../core/utils/display_names.dart';
import '../../domain/analysis/wrapped.dart';
import '../../l10n/l10n.dart';
import '../../shared/album_art.dart';
import '../../shared/cover_color.dart';
import 'wrapped_data.dart';

/// The card is drawn at this size and saved 3× larger: 1080 × 1920, a phone story's size.
const _cardSize = Size(360, 640);
const _pixelRatio = 3.0;

/// The last slide: the whole Wrapped on one card, to save or share. Nothing is shared without
/// the user's tap.
class WrappedCardSlide extends ConsumerStatefulWidget {
  const WrappedCardSlide({super.key, required this.wrapped});
  final Wrapped wrapped;

  @override
  ConsumerState<WrappedCardSlide> createState() => _WrappedCardSlideState();
}

class _WrappedCardSlideState extends ConsumerState<WrappedCardSlide> {
  final _boundary = GlobalKey();

  /// The card once saved: sharing again doesn't save a second copy.
  String? _savedUri;
  bool _busy = false;

  String get _fileName => 'nocturne-wrapped-${widget.wrapped.period.id}-${DateTime.now().millisecondsSinceEpoch}.png';

  Future<String?> _save() async {
    if (_savedUri != null) return _savedUri;
    final box = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (box == null) return null;
    final image = await box.toImage(pixelRatio: _pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return null;
    return _savedUri = await ref.read(deviceFilesProvider).saveImage(_fileName, png.buffer.asUint8List());
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      showToast(l10n.wrappedCardFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onSave() => _run(() async {
        final uri = await _save();
        showToast(uri == null ? l10n.wrappedCardFailed : l10n.wrappedSaved, error: uri == null);
      });

  Future<void> _onShare() => _run(() async {
        final uri = await _save();
        final shared = uri != null &&
            await ref.read(deviceFilesProvider).shareImage(uri, title: wrappedTitle(widget.wrapped.period));
        if (!shared) showToast(l10n.wrappedCardFailed, error: true);
      });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.lg),
      child: Column(
        children: [
          Expanded(
            child: FittedBox(
              // Round on screen only: the saved picture is square, rounded corners came out
              // see-through, and apps show those white or black
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                child: RepaintBoundary(
                  key: _boundary,
                  child: WrappedCard(wrapped: widget.wrapped),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _onShare,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentFill,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(l10n.share),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.surfaceHigh,
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(l10n.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The card itself, always the same size and type size (the phone's font size setting would
/// make the saved picture differ from phone to phone).
class WrappedCard extends ConsumerWidget {
  const WrappedCard({super.key, required this.wrapped});
  final Wrapped wrapped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = wrapped;
    final top = w.topSongs.firstOrNull?.track;
    final color = top == null
        ? AppColors.electric
        : ref.watch(coverColorProvider((id: top.id, path: top.coverPath))).value ?? AppColors.electric;
    final time = listeningTimeLabel(w.time);
    final mood = w.showMoods ? moodById(w.moods.first.key) : null;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Container(
        width: _cardSize.width,
        height: _cardSize.height,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: .9), AppColors.surface, AppColors.void_],
            stops: const [0, .55, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOCTURNE WRAPPED',
              style: AppTypography.labelSm.copyWith(color: AppColors.textPrimary, letterSpacing: 2, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(wrappedTitle(w.period), style: AppTypography.headlineXl),
            const Spacer(),
            Text(
              groupDigits(w.listened.inMinutes),
              style: const TextStyle(
                fontFamily: AppTypography.display,
                fontSize: 64,
                fontWeight: FontWeight.w800,
                height: 1,
                letterSpacing: -2,
                color: AppColors.textPrimary,
              ),
            ),
            Text(l10n.wrappedMinutes, style: AppTypography.titleSm),
            const SizedBox(height: 28),
            if (w.topSongs.firstOrNull case final s?) ...[
              _CardLabel(l10n.wrappedTopSong),
              const SizedBox(height: 8),
              Row(
                children: [
                  AlbumArt(path: s.track.coverPath, size: 56, seed: s.track.id),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.track.title, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          s.track.artistLabel,
                          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (w.topArtists.firstOrNull case final a?)
                  Expanded(child: _CardFact(label: l10n.wrappedTopArtist, value: a.name)),
                Expanded(child: _CardFact(label: l10n.wrappedWhen, value: '${time.emoji} ${time.name}')),
              ],
            ),
            if (mood != null) ...[
              const SizedBox(height: 16),
              _CardFact(
                label: l10n.wrappedMood,
                value: '${mood.emoji} ${(w.moods.first.value * 100).round()}% ${mood.label}',
              ),
            ],
            const Spacer(),
            Text(l10n.wrappedCardFooter, style: AppTypography.labelXs.copyWith(color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTypography.labelXs.copyWith(color: AppColors.cyan, letterSpacing: 1.4, fontWeight: FontWeight.w700),
      );
}

class _CardFact extends StatelessWidget {
  const _CardFact({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardLabel(label),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.titleSm, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      );
}
