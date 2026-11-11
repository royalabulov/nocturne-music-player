import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/output_detector.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/duration_format.dart';
import '../../domain/entities/track.dart';
import '../../domain/entities/track_keys.dart';
import '../../shared/album_art.dart';
import '../../shared/cover_color.dart';
import '../../shared/favorite_button.dart';
import '../../shared/glow_play_button.dart';
import '../tracks/track_actions_sheet.dart';
import '../../shared/locate_track.dart';
import '../../shared/tap_target.dart';
import 'lyrics_controller.dart';
import 'lyrics_view.dart';
import '../../core/audio/player_providers.dart';
import 'queue_sheet.dart';
import 'sleep_timer.dart';
import '../../l10n/l10n.dart';
import '../../core/utils/display_names.dart';

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

    return _PullDownToClose(
      child: Scaffold(
      backgroundColor: AppColors.void_,
      extendBody: true,
      // The area below the controls used to be empty and the sleep timer
      // "floated" alone in the chip row → all in one bottom row.
      // Scaffold's bottom bar: toasts appear above it instead of over it.
      bottomNavigationBar: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
          child: _BottomBar(),
        ),
      ),
      body: Stack(
        children: [
          // Ambient glow + top wash in the cover's colour
          const Positioned.fill(child: _CoverBackdrop()),
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
                        l10n.nowPlaying,
                        style: AppTypography.labelSm.copyWith(
                          letterSpacing: 1.2,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: l10n.closePlayer,
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
                            tooltip: l10n.queue,
                            onPressed: () => showQueueSheet(context),
                            icon: const Icon(Icons.queue_music_rounded),
                            color: AppColors.textPrimary,
                          ),
                          IconButton(
                            tooltip: l10n.more,
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
                  // The cover takes what the screen has left: a full-width square used to push the
                  // controls off short screens and off a turned phone (_PlayerLayout)
                  Expanded(
                    child: _PlayerLayout(
                      art: (size) => _SwipeToSkip(child: _ArtOrLyrics(track: t, size: size)),
                      info: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title and artist are one 48+ px target → the artist's page
                                    // (Now Playing closes). The artist line alone was 22 px high.
                                    TapTarget(
                                      label: '${t.title}, ${t.artistLabel}',
                                      hint: l10n.openArtist,
                                      alignment: AlignmentDirectional.centerStart,
                                      onTap: () => GoRouter.of(context).go(artistRoute(artistKeyOf(t))),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.title,
                                            style: AppTypography.headlineMd,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            t.artistLabel,
                                            style: AppTypography.bodyMd.copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xxs),
                                    // Quality as one quiet line — two bordered pills were the
                                    // loudest thing under the title (design review, 2026-11-02)
                                    Text(
                                      [
                                        t.qualityLabel,
                                        if (t.sampleRateHz != null) '${t.sampleRateHz! ~/ 1000}kHz',
                                      ].join('  ·  '),
                                      style: AppTypography.monoSm.copyWith(color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const _LyricsButton(),
                              FavoriteButton(trackId: t.id, size: 24),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const _Scrubber(),
                          const SizedBox(height: AppSpacing.sm),
                          // Transport. Tooltips double as TalkBack labels; shuffle/repeat
                          // say their state, since only the colour shows it on screen.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                tooltip: shuffle ? l10n.shuffleOn : l10n.shuffleOff,
                                onPressed: handler.toggleShuffle,
                                iconSize: 22,
                                icon: const Icon(Icons.shuffle_rounded),
                                color: shuffle
                                    ? AppColors.cyan
                                    : AppColors.textSecondary,
                              ),
                              IconButton(
                                tooltip: l10n.previousSong,
                                onPressed: handler.skipToPrevious,
                                iconSize: 34,
                                icon: const Icon(Icons.skip_previous_rounded),
                                color: AppColors.textPrimary,
                              ),
                              GlowPlayButton(
                                size: 64,
                                playing: playing,
                                onTap: playing ? handler.pause : handler.play,
                              ),
                              IconButton(
                                tooltip: l10n.nextSong,
                                onPressed: handler.skipToNext,
                                iconSize: 34,
                                icon: const Icon(Icons.skip_next_rounded),
                                color: AppColors.textPrimary,
                              ),
                              IconButton(
                                tooltip: switch (repeat) {
                                  AudioServiceRepeatMode.one => l10n.repeatOne,
                                  AudioServiceRepeatMode.none => l10n.repeatOff,
                                  _ => l10n.repeatAll,
                                },
                                onPressed: handler.cycleRepeat,
                                iconSize: 22,
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Pull the whole player down to close it — back to the mini player (the app
/// shows behind it while dragging: the route isn't opaque).
class _PullDownToClose extends StatefulWidget {
  const _PullDownToClose({required this.child});
  final Widget child;

  @override
  State<_PullDownToClose> createState() => _PullDownToCloseState();
}

class _PullDownToCloseState extends State<_PullDownToClose> with SingleTickerProviderStateMixin {
  late final _dy = AnimationController.unbounded(vsync: this);

  @override
  void dispose() {
    _dy.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    final height = context.size?.height ?? 800;
    if (_dy.value > height * .18 || (d.primaryVelocity ?? 0) > 800) {
      Navigator.of(context).maybePop();
    } else {
      _dy.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (d) => _dy.value = max(0, _dy.value + d.delta.dy),
      onVerticalDragEnd: _end,
      child: AnimatedBuilder(
        animation: _dy,
        // Same tree shape at rest and while pulled (no remount); no clipping at rest
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _dy.value),
          child: ClipRRect(
            clipBehavior: _dy.value == 0 ? Clip.none : Clip.antiAlias,
            // Rounded top corners while pulled, like a sheet
            borderRadius: BorderRadius.vertical(top: Radius.circular(min(_dy.value / 4, AppRadius.xxl))),
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Swipe the cover left → next song, right → previous song. The cover follows the
/// finger, slides out, and the new one slides in from the other side.
class _SwipeToSkip extends ConsumerStatefulWidget {
  const _SwipeToSkip({required this.child});
  final Widget child;

  @override
  ConsumerState<_SwipeToSkip> createState() => _SwipeToSkipState();
}

class _SwipeToSkipState extends ConsumerState<_SwipeToSkip> with SingleTickerProviderStateMixin {
  late final _dx = AnimationController.unbounded(vsync: this);
  bool _busy = false;

  @override
  void dispose() {
    _dx.dispose();
    super.dispose();
  }

  Future<void> _end(DragEndDetails d) async {
    final width = MediaQuery.sizeOf(context).width;
    final v = d.primaryVelocity ?? 0;
    final dir = v.abs() > 600 ? v.sign : (_dx.value.abs() > width * .25 ? _dx.value.sign : 0.0);
    if (dir == 0 || _busy) {
      await _dx.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      return;
    }
    _busy = true;
    final handler = ref.read(audioHandlerProvider);
    await _dx.animateTo(dir * width, duration: const Duration(milliseconds: 160), curve: Curves.easeIn);
    try {
      await (dir < 0 ? handler.skipToNext() : handler.skipToPreviousTrack())
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // slow load — slide the cover back anyway
    }
    if (!mounted) return;
    _dx.value = -dir * width;
    await _dx.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (!_busy) _dx.value += d.delta.dx;
      },
      onHorizontalDragEnd: _end,
      child: AnimatedBuilder(
        animation: _dx,
        builder: (_, child) => Transform.translate(offset: Offset(_dx.value, 0), child: child),
        child: widget.child,
      ),
    );
  }
}

/// Bottom row: output device · next song (tap for the queue) · sleep timer.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  static (IconData, String) _output(OutputKind k) => switch (k) {
    OutputKind.headphones => (Icons.headphones_rounded, l10n.outputHeadphones),
    OutputKind.bluetooth => (Icons.bluetooth_audio_rounded, l10n.outputBluetooth),
    OutputKind.speaker => (Icons.speaker_phone_rounded, l10n.outputSpeakerShort),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, label) = _output(
      ref.watch(outputKindProvider).value ?? OutputKind.speaker,
    );
    final next = ref.watch(upNextProvider);

    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: AppTypography.labelSm),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: next == null
              ? const SizedBox.shrink()
              // The row is 48 high (the sleep timer's area): "Up next" gets all of it, not 32
              : InkWell(
                  onTap: () => showQueueSheet(context),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: kMinTapTarget),
                    child: Center(
                      heightFactor: 1,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: l10n.upNext,
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
        ),
        const SizedBox(width: AppSpacing.md),
        const SleepTimerButton(),
      ],
    );
  }
}

/// Largest cover side.
const _maxArt = 340.0;

/// Cover above the title and controls; on a turned phone, beside them.
///
/// Upright, the cover is the full width (up to [_maxArt]) as before when the screen has room,
/// and the space left over goes two thirds above the cover, one third below the controls. On
/// a short screen the cover shrinks instead of pushing the controls off the bottom (a 360×640
/// phone lost 20 px of them, a turned phone the play button).
class _PlayerLayout extends StatelessWidget {
  const _PlayerLayout({required this.art, required this.info});

  /// The cover, drawn at the given side.
  final Widget Function(double size) art;

  /// Title, scrubber and controls.
  final Widget info;

  /// Gap between the cover and the title.
  static const gap = AppSpacing.xxl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth > c.maxHeight * 1.2) {
        final size = max(0.0, min(min(c.maxHeight - AppSpacing.md, c.maxWidth * .42), _maxArt));
        return Row(
          children: [
            SizedBox.square(dimension: size, child: art(size)),
            const SizedBox(width: AppSpacing.xl),
            // Very little height (a large font on a turned phone): the controls scroll
            Expanded(child: Center(child: SingleChildScrollView(child: info))),
          ],
        );
      }
      return CustomMultiChildLayout(
        delegate: _UprightLayout(),
        children: [
          LayoutId(id: #art, child: LayoutBuilder(builder: (_, a) => art(a.maxWidth))),
          LayoutId(id: #info, child: info),
        ],
      );
    });
  }
}

class _UprightLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final info = layoutChild(#info, BoxConstraints(minWidth: size.width, maxWidth: size.width, maxHeight: size.height));
    final room = size.height - info.height - _PlayerLayout.gap;
    final side = max(0.0, min(min(size.width, _maxArt), room));
    layoutChild(#art, BoxConstraints.tight(Size.square(side)));
    final top = max(0.0, room - side) * 2 / 3;
    positionChild(#art, Offset((size.width - side) / 2, top));
    positionChild(#info, Offset(0, top + side + _PlayerLayout.gap));
  }

  @override
  bool shouldRelayout(_UprightLayout oldDelegate) => false;
}

/// Tap the cover → lyrics in its place; tap again → the cover.
class _ArtOrLyrics extends ConsumerWidget {
  const _ArtOrLyrics({required this.track, required this.size});
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showLyricsProvider);
    // The cover had no name for TalkBack: say what it is and what swiping and tapping do
    return Semantics(
      label: show ? null : l10n.coverHint,
      child: GestureDetector(
        onTap: ref.read(showLyricsProvider.notifier).toggle,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: show
              ? LyricsPanel(key: const ValueKey('lyrics'), size: size)
              : _Art(key: const ValueKey('art'), track: track, size: size),
        ),
      ),
    );
  }
}

/// Next to the heart: lyrics ⇄ cover. Lit while lyrics are shown.
class _LyricsButton extends ConsumerWidget {
  const _LyricsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(showLyricsProvider);
    return IconButton(
      tooltip: show ? l10n.showCover : l10n.showLyrics,
      onPressed: ref.read(showLyricsProvider.notifier).toggle,
      icon: Icon(show ? Icons.lyrics_rounded : Icons.lyrics_outlined, size: 24),
      color: show ? AppColors.cyan : AppColors.textSecondary,
    );
  }
}

class _Art extends ConsumerWidget {
  const _Art({super.key, required this.track, required this.size});
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider);
    final glow = ref.watch(currentCoverColorProvider);
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
              color: glow.withValues(alpha: playing ? .4 : .1),
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
        // Thin line with a small dot; the dot grows only while dragging
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: _dragValue == null ? 4 : 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value,
            max: maxMs,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              unawaited(ref.read(audioHandlerProvider).seek(Duration(milliseconds: v.round())));
              setState(() => _dragValue = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shown.mmss, style: AppTypography.monoSm),
              Text(dur.mmss, style: AppTypography.monoSm),
            ],
          ),
        ),
      ],
    );
  }
}

/// Background in the cover's colour: a glow behind the art and a wash that fades
/// into the void by mid-screen, so text below always sits on a dark background.
/// Eases between songs instead of jumping.
class _CoverBackdrop extends ConsumerWidget {
  const _CoverBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: ref.watch(currentCoverColorProvider)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (_, c, _) {
        final color = c ?? AppColors.electric;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .6],
                    colors: [color.withValues(alpha: .16), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -80,
              left: -60,
              right: -60,
              height: 420,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [color.withValues(alpha: .3), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
