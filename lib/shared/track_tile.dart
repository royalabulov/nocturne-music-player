import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../domain/entities/track.dart';
import 'album_art.dart';
import 'eq_bars.dart';
import '../shared/display_names.dart';

/// Universal track row. [trailing] changes the right side
/// (heart, play, kebab, "Played 42x" ...).
///
/// Flat 64dp row, not a card: the old card rows (56px art, a third
/// "3:52 · 321KBPS MP3" line, 12px gaps) fit ~6 songs per screen; this fits ~9.
/// Bitrate lives in Now Playing (design review, 2026-11-02).
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.active = false,
    this.selected,
  });

  final Track track;

  /// The track playing now — title in cyan.
  final bool active;

  /// Default: "artist • album". Recent overrides it, e.g. "12m ago • 3:45".
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Multi-select mode: null = off, true/false = selected/not selected
  /// (tick over the cover, row highlighted).
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected ?? false;
    return Material(
      color: isSelected ? AppColors.electric.withValues(alpha: .18) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
          child: Row(
            children: [
              _SelectableArt(
                selected: selected,
                child: NowPlayingOverlay(
                  active: active && selected == null,
                  radius: AppRadius.md,
                  child: AlbumArt(path: track.coverPath, seed: track.id, size: 48, radius: AppRadius.md),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The title takes the full width — next to the codec chip it used to
                    // get cut to 1–2 words like "AMAL' × ...".
                    Text(
                      track.title,
                      style: AppTypography.titleSm.copyWith(color: active ? AppColors.cyan : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? artistAlbumLine(track),
                      style: AppTypography.bodySm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: AppSpacing.xxs), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// "artist • album" — just the artist if the album equals the artist or the song
/// itself (YouTube-channel files give "Synaps Records • Synaps Records", singles
/// "Xpert • MƏN BU FİLMƏ BAXMIŞAM") or is unknown.
String artistAlbumLine(Track t) {
  final album = t.album.trim().toLowerCase();
  final repeats = album == t.artist.trim().toLowerCase() || album == t.title.trim().toLowerCase();
  final unknown = album.isEmpty || album.startsWith('unknown');
  return repeats || unknown ? t.artistLabel : '${t.artistLabel} • ${t.album.trim()}';
}

/// Tick circle over the cover in selection mode.
class _SelectableArt extends StatelessWidget {
  const _SelectableArt({required this.selected, required this.child});
  final bool? selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = selected;
    if (s == null) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: s ? .45 : .25),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(
            s ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            key: ValueKey(s),
            size: 28,
            color: s ? AppColors.cyan : Colors.white70,
          ),
        ),
      ],
    );
  }
}
