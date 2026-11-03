import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/online_mode.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/entities/lyrics.dart';
import '../../l10n/l10n.dart';
import 'lyrics_controller.dart';
import 'player_providers.dart';

/// Lyrics in the cover's place, same square. Synced lyrics follow the song and a
/// tapped line jumps there; any other tap (the parent) goes back to the cover.
class LyricsPanel extends ConsumerWidget {
  const LyricsPanel({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retry = ref.read(lyricsProvider.notifier).retry;
    final online = ref.watch(onlineModeProvider.select((s) => s.enabled));
    final state = ref.watch(lyricsProvider);
    // While the next song loads, the old song's source line goes away too
    final lyrics = state.isLoading ? null : state.value?.lyrics;

    final body = state.when(
          loading: () => _Message(text: l10n.lyricsSearching, busy: true),
          error: (_, _) => _Message(text: l10n.lyricsError, action: (l10n.lyricsRetry, retry)),
          data: (r) => switch (r.status) {
            LyricsStatus.found => switch (r.lyrics!) {
                final l when l.synced => _SyncedLyrics(lines: l.lines, height: size),
                Lyrics(plain: final String text) => _PlainLyrics(text: text),
                _ => _Message(text: l10n.lyricsInstrumental, icon: Icons.music_note_rounded),
              },
            LyricsStatus.notFound =>
              _Message(text: l10n.lyricsNotFound, action: online ? (l10n.lyricsRetry, retry) : null),
            LyricsStatus.needsOnline =>
              _Message(text: l10n.lyricsNeedOnline, action: (l10n.turnOnOnline, () => toggleOnlineMode(ref))),
            LyricsStatus.onlineSearchOff => _Message(text: l10n.lyricsSearchOff),
            LyricsStatus.error => _Message(text: l10n.lyricsError, action: (l10n.lyricsRetry, retry)),
          },
        );

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.void_.withValues(alpha: .55),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xxl)),
          border: Border.all(color: AppColors.borderArt),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xxl)),
          child: Column(
            children: [
              Expanded(child: body),
              if (lyrics != null && !lyrics.instrumental)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    lyrics.source == LyricsSource.file ? l10n.lyricsFromFile : l10n.lyricsFromLrclib,
                    style: AppTypography.labelSm.copyWith(color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top and bottom edges fade out, so lines slide in and out softly.
class _FadeEdges extends StatelessWidget {
  const _FadeEdges({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, .12, .88, 1],
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        ).createShader(r),
        child: child,
      );
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lines, required this.height});
  final List<LyricLine> lines;
  final double height;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  late List<GlobalKey> _keys = _newKeys();
  int _shown = -2;

  /// The user scrolled by hand → don't pull the view back for a moment.
  DateTime _userScrolledAt = DateTime(0);

  List<GlobalKey> _newKeys() => List.generate(widget.lines.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(_SyncedLyrics old) {
    super.didUpdateWidget(old);
    if (old.lines != widget.lines) {
      _keys = _newKeys();
      _shown = -2;
    }
  }

  void _follow(int i, {bool jump = false}) {
    if (i < 0 || DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: .4,
      duration: jump ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    // Rebuilds only when the sung line changes, not on every position tick
    final active = ref.watch(
      positionProvider.select((a) => activeLyricLine(lines, a.value ?? Duration.zero)),
    );
    if (active != _shown) {
      final first = _shown == -2;
      _shown = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(active, jump: first);
      });
    }
    final handler = ref.read(audioHandlerProvider);

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: _FadeEdges(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: widget.height * .4, horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++)
                GestureDetector(
                  key: _keys[i],
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _userScrolledAt = DateTime(0);
                    handler.seek(lines[i].time);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: AppTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                        color: i == active
                            ? AppColors.textPrimary
                            : AppColors.textMuted.withValues(alpha: i < active ? .45 : .7),
                      ),
                      // A break between verses is an empty line → a note
                      child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => _FadeEdges(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl, horizontal: AppSpacing.lg),
          child: Text(
            text,
            style: AppTypography.bodyLg.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.icon = Icons.lyrics_outlined, this.busy = false, this.action});
  final String text;
  final IconData icon;
  final bool busy;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan),
              )
            else
              Icon(icon, size: 32, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: action.$2,
                style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
                child: Text(action.$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
