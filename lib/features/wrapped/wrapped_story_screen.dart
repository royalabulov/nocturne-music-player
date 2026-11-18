import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/display_names.dart';
import '../../domain/analysis/wrapped.dart';
import '../../domain/entities/track.dart';
import '../../l10n/l10n.dart';
import '../../shared/album_art.dart';
import '../../shared/cover_color.dart';
import 'wrapped_card.dart';
import 'wrapped_data.dart';

/// Wrapped as stories: full screen, a bar per slide at the top, a tap on the right goes on,
/// on the left goes back, holding pauses. Every slide but the last moves on by itself.
class WrappedStoryScreen extends ConsumerWidget {
  const WrappedStoryScreen({super.key, required this.period});
  final WrappedPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(wrappedProvider(period));
    return Scaffold(
      backgroundColor: AppColors.void_,
      body: switch (w) {
        AsyncData(value: final wrapped?) => _Story(wrapped: wrapped),
        AsyncData() || AsyncError() => _NotEnough(onClose: () => Navigator.of(context).maybePop()),
        _ => const Center(child: CircularProgressIndicator(color: AppColors.cyan)),
      },
    );
  }
}

class _NotEnough extends StatelessWidget {
  const _NotEnough({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(alignment: AlignmentDirectional.centerEnd, child: _CloseButton(onTap: onClose)),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(l10n.wrappedNotEnough, style: AppTypography.bodyLg, textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One slide: what it shows and the song whose cover colours it.
typedef _Slide = ({Widget Function() build, Track? accent});

class _Story extends ConsumerStatefulWidget {
  const _Story({required this.wrapped});
  final Wrapped wrapped;

  @override
  ConsumerState<_Story> createState() => _StoryState();
}

class _StoryState extends ConsumerState<_Story> with SingleTickerProviderStateMixin {
  static const _slideTime = Duration(seconds: 7);

  late final _clock = AnimationController(vsync: this, duration: _slideTime)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go(1);
    });
  late final List<_Slide> _slides = _build(widget.wrapped);
  int _index = 0;

  bool get _last => _index == _slides.length - 1;

  @override
  void initState() {
    super.initState();
    _clock.forward();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _go(int step) {
    final next = (_index + step).clamp(0, _slides.length - 1);
    if (next == _index) {
      // Back on the first slide starts it again
      if (step < 0) _clock.forward(from: 0);
      return;
    }
    setState(() => _index = next);
    // The card waits for the user: no clock on the last slide
    if (_last) {
      _clock.value = 1;
    } else {
      _clock.forward(from: 0);
    }
  }

  List<_Slide> _build(Wrapped w) {
    final top = w.topSongs.firstOrNull?.track;
    return [
      (build: () => _IntroSlide(w: w), accent: top),
      if (w.topSongs.isNotEmpty)
        (build: () => _TopSongSlide(song: w.topSongs.first, onPlay: () => _play([w.topSongs.first.track])), accent: top),
      if (w.topSongs.length > 1)
        (build: () => _TopSongsSlide(songs: w.topSongs, onPlay: _play), accent: w.topSongs[1].track),
      if (w.topArtists.isNotEmpty) (build: () => _ArtistSlide(artists: w.topArtists), accent: w.topArtists.first.cover),
      if (w.showMoods) (build: () => _MoodSlide(w: w), accent: top),
      (build: () => _ClockSlide(w: w), accent: w.topSongs.length > 2 ? w.topSongs[2].track : top),
      (build: () => _HabitsSlide(w: w, onPlay: _play), accent: w.discoveries.firstOrNull?.track ?? top),
      (build: () => WrappedCardSlide(wrapped: w), accent: top),
    ];
  }

  void _play(List<Track> tracks) => ref.read(audioHandlerProvider).playTracks(tracks);

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_index];
    final accent = slide.accent;
    final color = accent == null
        ? AppColors.electric
        : ref.watch(coverColorProvider((id: accent.id, path: accent.coverPath))).value ?? AppColors.electric;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The slide's cover colour glows from the top and fades into the night
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -.7),
              radius: 1.25,
              colors: [color.withValues(alpha: .55), AppColors.void_],
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _go(d.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? -1 : 1),
          onLongPressStart: (_) => _clock.stop(),
          onLongPressEnd: (_) {
            if (!_last) _clock.forward();
          },
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xs),
                _Progress(count: _slides.length, index: _index, clock: _clock),
                Row(
                  children: [
                    const SizedBox(width: AppSpacing.screenH),
                    Expanded(
                      child: Text(
                        '${wrappedTitle(widget.wrapped.period).toUpperCase()}  ·  WRAPPED',
                        style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary, letterSpacing: 1.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _CloseButton(onTap: () => Navigator.of(context).maybePop()),
                  ],
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: KeyedSubtree(key: ValueKey(_index), child: slide.build()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.index, required this.clock});
  final int count, index;
  final Animation<double> clock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: AnimatedBuilder(
        animation: clock,
        builder: (_, _) => Row(
          children: [
            for (var i = 0; i < count; i++)
              Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: i < index ? 1 : (i == index ? clock.value : 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: l10n.wrappedClose,
        onPressed: onTap,
        icon: const Icon(Icons.close_rounded),
        color: AppColors.textPrimary,
      );
}

// ── building blocks ──────────────────────────────────────

/// Comes up and in, [delay] after the slide appears.
class _Rise extends StatelessWidget {
  const _Rise({this.delay = 0, required this.child});
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const move = 500;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: move + delay),
      curve: Interval(delay / (move + delay), 1, curve: Curves.easeOutCubic),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 28 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

/// A number counting up to [value].
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.style});
  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(groupDigits(v.round()), style: style),
      );
}

const _big = TextStyle(
  fontFamily: AppTypography.display,
  fontFamilyFallback: [AppTypography.body],
  fontSize: 64,
  fontWeight: FontWeight.w800,
  height: 1,
  letterSpacing: -2,
  color: AppColors.textPrimary,
);

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTypography.labelMd.copyWith(color: AppColors.cyan, letterSpacing: 1.6, fontWeight: FontWeight.w700),
      );
}

class _SlideFrame extends StatelessWidget {
  const _SlideFrame({required this.children, this.center = false});
  final List<Widget> children;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: max(0, box.maxHeight - AppSpacing.lg * 2)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({required this.song, this.rank, this.onTap});
  final WrappedSong song;
  final int? rank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = song.track;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 36,
                child: Text('$rank', style: AppTypography.headlineLg.copyWith(color: AppColors.cyan)),
              ),
            AlbumArt(path: t.coverPath, size: 52, seed: t.id),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    t.artistLabel,
                    style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(l10n.playCount(song.plays), style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── the slides ───────────────────────────────────────────

class _IntroSlide extends StatelessWidget {
  const _IntroSlide({required this.w});
  final Wrapped w;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      children: [
        _Rise(child: _Kicker(l10n.wrappedIntro(wrappedTitle(w.period)))),
        const SizedBox(height: AppSpacing.xl),
        _Rise(delay: 200, child: _CountUp(value: w.listened.inMinutes, style: _big.copyWith(fontSize: 80))),
        const SizedBox(height: AppSpacing.xs),
        _Rise(delay: 300, child: Text(l10n.wrappedMinutes, style: AppTypography.headlineLg)),
        const SizedBox(height: AppSpacing.xl),
        _Rise(
          delay: 700,
          child: Text(
            l10n.wrappedIntroStats(w.plays, w.songCount, w.activeDays),
            style: AppTypography.bodyLg.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _TopSongSlide extends StatelessWidget {
  const _TopSongSlide({required this.song, required this.onPlay});
  final WrappedSong song;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final t = song.track;
    final size = min(MediaQuery.sizeOf(context).width * .62, 280.0);
    return _SlideFrame(
      center: true,
      children: [
        _Rise(child: _Kicker(l10n.wrappedTopSong)),
        const SizedBox(height: AppSpacing.xl),
        _Rise(
          delay: 150,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              boxShadow: [BoxShadow(color: AppColors.void_.withValues(alpha: .6), blurRadius: 40, offset: const Offset(0, 16))],
            ),
            child: AlbumArt(path: t.coverPath, size: size, radius: AppRadius.xxl, seed: t.id),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Rise(
          delay: 400,
          child: Text(t.title, style: AppTypography.headlineXl, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        _Rise(
          delay: 450,
          child: Text(t.artistLabel, style: AppTypography.bodyLg.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
        ),
        const SizedBox(height: AppSpacing.md),
        _Rise(
          delay: 700,
          child: Text(
            '${l10n.playCount(song.plays)}  ·  ${wrappedDuration(song.listened)}',
            style: AppTypography.labelMd.copyWith(color: AppColors.cyan),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Rise(
          delay: 900,
          child: FilledButton.icon(
            onPressed: onPlay,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentFill),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l10n.play),
          ),
        ),
      ],
    );
  }
}

class _TopSongsSlide extends StatelessWidget {
  const _TopSongsSlide({required this.songs, required this.onPlay});
  final List<WrappedSong> songs;
  final void Function(List<Track>) onPlay;

  @override
  Widget build(BuildContext context) {
    final tracks = [for (final s in songs) s.track];
    return _SlideFrame(
      children: [
        _Rise(child: _Kicker(l10n.wrappedTopSongs)),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < songs.length; i++)
          _Rise(
            delay: 150 + 120 * i,
            child: _SongRow(song: songs[i], rank: i + 1, onTap: () => onPlay([...tracks.skip(i), ...tracks.take(i)])),
          ),
      ],
    );
  }
}

class _ArtistSlide extends StatelessWidget {
  const _ArtistSlide({required this.artists});
  final List<WrappedArtist> artists;

  @override
  Widget build(BuildContext context) {
    final a = artists.first;
    final size = min(MediaQuery.sizeOf(context).width * .5, 220.0);
    final rest = artists.skip(1).take(3).map((x) => x.name).join(', ');
    return _SlideFrame(
      center: true,
      children: [
        _Rise(child: _Kicker(l10n.wrappedTopArtist)),
        const SizedBox(height: AppSpacing.xl),
        _Rise(
          delay: 150,
          child: AlbumArt(path: a.cover.coverPath, size: size, radius: size / 2, seed: a.cover.id),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Rise(
          delay: 400,
          child: Text(a.name, style: _big.copyWith(fontSize: 44), textAlign: TextAlign.center, maxLines: 2),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Rise(
          delay: 550,
          child: Text(
            '${l10n.playCount(a.plays)}  ·  ${wrappedDuration(a.listened)}',
            style: AppTypography.labelMd.copyWith(color: AppColors.cyan),
          ),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _Rise(
            delay: 900,
            child: Text(
              l10n.wrappedThen(rest),
              style: AppTypography.bodyLg.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _MoodSlide extends StatelessWidget {
  const _MoodSlide({required this.w});
  final Wrapped w;

  @override
  Widget build(BuildContext context) {
    final moods = [
      for (final e in w.moods)
        if (moodById(e.key) case final m?) (mood: m, share: e.value),
    ];
    final top = moods.first;
    return _SlideFrame(
      children: [
        _Rise(child: _Kicker(l10n.wrappedMood)),
        const SizedBox(height: AppSpacing.xl),
        _Rise(delay: 150, child: Text(top.mood.emoji, style: const TextStyle(fontSize: 56))),
        const SizedBox(height: AppSpacing.sm),
        _Rise(
          delay: 250,
          child: Text('${(top.share * 100).round()}%', style: _big.copyWith(fontSize: 72)),
        ),
        _Rise(delay: 350, child: Text(top.mood.label, style: AppTypography.headlineLg)),
        const SizedBox(height: AppSpacing.xl),
        for (var i = 0; i < moods.length; i++)
          _Rise(
            delay: 600 + 120 * i,
            child: _ShareBar(label: '${moods[i].mood.emoji}  ${moods[i].mood.label}', share: moods[i].share),
          ),
      ],
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.label, required this.share});
  final String label;
  final double share;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.bodyMd)),
              Text('${(share * 100).round()}%', style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: share),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: AppColors.textPrimary.withValues(alpha: .12),
                color: AppColors.cyan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _hour(int h) => '${h.toString().padLeft(2, '0')}:00';

class _ClockSlide extends StatelessWidget {
  const _ClockSlide({required this.w});
  final Wrapped w;

  @override
  Widget build(BuildContext context) {
    final label = listeningTimeLabel(w.time);
    final peak = w.peakHour;
    final most = w.byHour.reduce((a, b) => a > b ? a : b).inSeconds;
    return _SlideFrame(
      children: [
        _Rise(child: _Kicker(l10n.wrappedWhen)),
        const SizedBox(height: AppSpacing.xl),
        _Rise(delay: 150, child: Text(label.emoji, style: const TextStyle(fontSize: 56))),
        const SizedBox(height: AppSpacing.sm),
        _Rise(delay: 250, child: Text(label.name, style: _big.copyWith(fontSize: 44))),
        const SizedBox(height: AppSpacing.xs),
        _Rise(
          delay: 400,
          child: Text(l10n.wrappedPeakHour(_hour(peak)), style: AppTypography.bodyLg.copyWith(color: AppColors.textSecondary)),
        ),
        const SizedBox(height: AppSpacing.xxl),
        // 24 bars, one an hour; the busiest one lit
        _Rise(
          delay: 600,
          child: SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < 24; h++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: most == 0 ? 0 : w.byHour[h].inSeconds / most),
                        duration: Duration(milliseconds: 600 + 25 * h),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => Container(
                          height: max(3, 120 * v),
                          decoration: BoxDecoration(
                            color: h == peak ? AppColors.cyan : AppColors.textPrimary.withValues(alpha: .28),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Rise(
          delay: 700,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final h in [0, 6, 12, 18, 23]) Text(_hour(h), style: AppTypography.labelXs)],
          ),
        ),
      ],
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  const _HabitsSlide({required this.w, required this.onPlay});
  final Wrapped w;
  final void Function(List<Track>) onPlay;

  @override
  Widget build(BuildContext context) {
    // Too little history to tell what is new: the streak and the days alone
    if (!w.knowsDiscoveries) {
      return _SlideFrame(
        children: [
          _Rise(child: _Kicker(l10n.wrappedStreak)),
          const SizedBox(height: AppSpacing.lg),
          _Rise(delay: 150, child: _CountUp(value: w.longestStreak, style: _big.copyWith(fontSize: 96))),
          _Rise(delay: 250, child: Text(l10n.wrappedStreakDaysWord(w.longestStreak), style: AppTypography.headlineLg)),
          const SizedBox(height: AppSpacing.xl),
          _Rise(
            delay: 600,
            child: Text(
              l10n.wrappedActiveDays(w.activeDays),
              style: AppTypography.bodyLg.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    }
    return _SlideFrame(
      children: [
        _Rise(child: _Kicker(l10n.wrappedNew)),
        const SizedBox(height: AppSpacing.lg),
        if (w.discoveryCount == 0)
          _Rise(delay: 150, child: Text(l10n.wrappedNoNew, style: AppTypography.headlineLg))
        else ...[
          _Rise(delay: 150, child: _CountUp(value: w.discoveryCount, style: _big)),
          const SizedBox(height: AppSpacing.xs),
          _Rise(delay: 250, child: Text(l10n.wrappedNewCount(w.discoveryCount), style: AppTypography.headlineMd)),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < w.discoveries.length; i++)
            _Rise(
              delay: 450 + 120 * i,
              child: _SongRow(song: w.discoveries[i], onTap: () => onPlay([w.discoveries[i].track])),
            ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _Rise(delay: 900, child: _Kicker(l10n.wrappedStreak)),
        const SizedBox(height: AppSpacing.xs),
        _Rise(
          delay: 1000,
          child: Text(l10n.wrappedStreakDays(w.longestStreak), style: _big.copyWith(fontSize: 40)),
        ),
      ],
    );
  }
}
