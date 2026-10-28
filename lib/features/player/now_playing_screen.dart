import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/output_detector.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../shared/album_art.dart';
import '../../shared/codec_chip.dart';
import '../../shared/favorite_button.dart';
import '../../shared/glow_play_button.dart';
import '../../shared/track_actions_sheet.dart';
import '../home/locate_track.dart';
import '../library_browse/library_groups.dart';
import '../settings/settings_controller.dart';
import '../shell/mini_player.dart';
import 'player_providers.dart';
import 'queue_sheet.dart';
import 'sleep_timer.dart';

/// Full-screen player. Not in the original design — drawn to match the design system.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(currentTrackProvider).value;
    if (t == null) {
      // Queue emptied (stop) → close the screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(backgroundColor: AppColors.void_);
    }
    final handler = ref.read(audioHandlerProvider);
    // Only the needed fields: PlaybackState arrives again on every player event (buffer,
    // position) — a full watch rebuilt the whole screen.
    final (:playing, :shuffle, :repeat) = ref.watch(
      playbackStateProvider.select((a) {
        final s = a.value;
        return (
          playing: s?.playing ?? false,
          shuffle: s != null && s.shuffleMode != AudioServiceShuffleMode.none,
          repeat: s?.repeatMode ?? AudioServiceRepeatMode.none,
        );
      }),
    );

    return Scaffold(
      backgroundColor: AppColors.void_,
      body: Stack(
        children: [
          // Ambient glow — behind the album art
          Positioned(
            top: -80,
            left: -60,
            right: -60,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.electric.withValues(alpha: .18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1 icon on the left, 2 on the right → a title inside the Row was off-centre
                      Text(
                        'NOW PLAYING',
                        style: AppTypography.labelSm.copyWith(
                          letterSpacing: 1.2,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 32,
                            ),
                            color: AppColors.textPrimary,
                          ),
                          const Spacer(),
                          // Two icons in the same style. "Show in library" (was a cyan
                          // "target" icon that looked like an active state) → in the ••• menu
                          IconButton(
                            tooltip: 'Queue',
                            onPressed: () => showQueueSheet(context),
                            icon: const Icon(Icons.queue_music_rounded),
                            color: AppColors.textPrimary,
                          ),
                          IconButton(
                            tooltip: 'More',
                            onPressed: () => showTrackActions(
                              context,
                              t,
                              // Home → scroll to this track in the Library list
                              onShowInLibrary: () {
                                ref
                                    .read(locateTrackProvider.notifier)
                                    .request(t.id);
                                final router = GoRouter.of(context);
                                Navigator.of(context).maybePop();
                                router.go(Routes.home);
                              },
                            ),
                            icon: const Icon(Icons.more_horiz_rounded),
                            color: AppColors.textPrimary,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(flex: 2),
                  _Art(track: t),
                  const SizedBox(height: AppSpacing.xxl),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              style: AppTypography.headlineLg,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            // Tap the artist → their page (Now Playing closes)
                            GestureDetector(
                              onTap: () =>
                                  GoRouter.of(context)
                                      .go(artistRoute(artistKeyOf(t))),
                              child: Text(
                                t.artist,
                                style: AppTypography.bodyMd.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FavoriteButton(trackId: t.id, size: 26),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      CodecChip(t.qualityLabel),
                      const SizedBox(width: AppSpacing.xs),
                      if (t.sampleRateHz != null)
                        CodecChip('${t.sampleRateHz! ~/ 1000}kHz'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _Scrubber(),
                  const SizedBox(height: AppSpacing.lg),
                  // Transport
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: handler.toggleShuffle,
                        iconSize: 26,
                        icon: const Icon(Icons.shuffle_rounded),
                        color: shuffle
                            ? AppColors.cyan
                            : AppColors.textSecondary,
                      ),
                      IconButton(
                        onPressed: handler.skipToPrevious,
                        iconSize: 40,
                        icon: const Icon(Icons.skip_previous_rounded),
                        color: AppColors.textPrimary,
                      ),
                      GlowPlayButton(
                        size: 72,
                        playing: playing,
                        onTap: playing ? handler.pause : handler.play,
                      ),
                      IconButton(
                        onPressed: handler.skipToNext,
                        iconSize: 40,
                        icon: const Icon(Icons.skip_next_rounded),
                        color: AppColors.textPrimary,
                      ),
                      IconButton(
                        onPressed: handler.cycleRepeat,
                        iconSize: 26,
                        icon: Icon(
                          repeat == AudioServiceRepeatMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                        ),
                        color: repeat == AudioServiceRepeatMode.none
                            ? AppColors.textSecondary
                            : AppColors.cyan,
                      ),
                    ],
                  ),
                  const Spacer(),
                  // The area below the controls used to be empty and the sleep timer
                  // "floated" alone in the chip row → all in one bottom row
                  const _BottomBar(),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom row: output device · next song (tap for the queue) · sleep timer.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  static (IconData, String) _output(OutputKind k) => switch (k) {
    OutputKind.headphones => (Icons.headphones_rounded, 'Headphones'),
    OutputKind.bluetooth => (Icons.bluetooth_audio_rounded, 'Bluetooth'),
    OutputKind.speaker => (Icons.speaker_phone_rounded, 'Speaker'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, label) = _output(
      ref.watch(outputKindProvider).value ?? OutputKind.speaker,
    );
    // Refresh "Up next" when the queue, current song or shuffle/repeat changes
    ref.watch(queueProvider);
    ref.watch(currentTrackProvider);
    ref.watch(
      playbackStateProvider.select(
        (a) => (a.value?.shuffleMode, a.value?.repeatMode),
      ),
    );
    final next = ref.read(audioHandlerProvider).upNextValue;

    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.labelSm),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: next == null
              ? const SizedBox.shrink()
              : InkWell(
                  onTap: () => showQueueSheet(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Up next  ',
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.cyan,
                            ),
                          ),
                          TextSpan(
                            text: next.title,
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.md),
        const SleepTimerButton(),
      ],
    );
  }
}

class _Art extends ConsumerWidget {
  const _Art({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = (MediaQuery.sizeOf(context).width - AppSpacing.xl * 2).clamp(
      200.0,
      340.0,
    );
    final playing = ref.watch(isPlayingProvider);
    // While paused the cover shrinks a little and the glow fades; it grows back when playing.
    return AnimatedScale(
      scale: playing ? 1 : .88,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xxl)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6)
                  .withValues(alpha: playing ? .4 : .1),
              blurRadius: 48,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Hero(
          tag: kNowPlayingArtHero,
          // Smooth cover transition when the track changes
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: AlbumArt(
              key: ValueKey(track.id),
              path: track.coverPath,
              seed: track.id,
              size: size,
              radius: AppRadius.xxl,
            ),
          ),
        ),
      ),
    );
  }
}

/// Slider + time labels. Shows a local value while dragging, seeks on release.
class _Scrubber extends ConsumerStatefulWidget {
  const _Scrubber();

  @override
  ConsumerState<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<_Scrubber> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;
    final maxMs = dur.inMilliseconds == 0 ? 1.0 : dur.inMilliseconds.toDouble();
    final value = (_dragValue ?? pos.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs,
    );
    final shown = Duration(milliseconds: value.round());

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            max: maxMs,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              ref
                  .read(audioHandlerProvider)
                  .seek(Duration(milliseconds: v.round()));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shown.mmss, style: AppTypography.monoMd),
              Text(dur.mmss, style: AppTypography.monoMd),
            ],
          ),
        ),
      ],
    );
  }
}
