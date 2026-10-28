import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';

/// Hero tag for the cover between the mini player and Now Playing.
const kNowPlayingArtHero = 'now-playing-art';

/// Mini-player floating 12px above the bottom nav (Level 2 glass).
/// Listens to the player through the shell (track, playing state, progress).
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.track,
    this.progressBar = const MiniProgressStrip(progress: 0),
    this.playing = false,
    this.onTap,
    this.onPlayPause,
    this.onNext,
  });

  final Track track;

  /// The 2px strip along the top edge. The shell passes a separate widget that tracks
  /// the position, so the whole mini-player doesn't rebuild on every tick (~5/s).
  final Widget progressBar;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Edges line up with the bottom menu (screenH) — it used to be 4dp wider on each side
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, 12),
      child: GestureDetector(
        onTap: onTap,
        child: GlassCard(
          level: GlassLevel.floating,
          radius: AppRadius.xl,
          // Always on screen: blur was recomputed on every scroll frame
          blur: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 2px scrubber — top edge
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                child: SizedBox(height: 2, child: RepaintBoundary(child: progressBar)),
              ),
              SizedBox(
                height: AppSpacing.miniPlayerHeight - 2,
                child: Row(
                  children: [
                    const SizedBox(width: AppSpacing.sm),
                    // Hero: when Now Playing opens, the cover flies up and grows from the mini player
                    Hero(
                      tag: kNowPlayingArtHero,
                      child: AlbumArt(path: track.coverPath, seed: track.id, size: 40, radius: AppRadius.md),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, style: AppTypography.titleSm,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(track.artist, style: AppTypography.labelSm,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onPlayPause,
                      icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      color: AppColors.textPrimary,
                      iconSize: 28,
                    ),
                    IconButton(
                      onPressed: onNext,
                      icon: const Icon(Icons.skip_next_rounded),
                      color: AppColors.textPrimary,
                      iconSize: 28,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mini-player's 2px progress strip.
class MiniProgressStrip extends StatelessWidget {
  const MiniProgressStrip({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: progress.clamp(0, 1),
        child: const SizedBox.expand(
          child: DecoratedBox(decoration: BoxDecoration(gradient: AppColors.progressGradient)),
        ),
      ),
    );
  }
}
