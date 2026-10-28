import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sonar_audio_handler.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../../domain/repositories/library_repository.dart';
import '../../shared/album_art.dart';
import '../player/player_providers.dart';
import 'smart_groups.dart';
import 'vibe_classifier.dart';
import 'vibe_review.dart';

const _sampleSize = 40;
const _all = (sort: TrackSort.recentlyAdded, query: '');

/// "Check smart groups": random songs are shown one by one, the user
/// confirms or corrects the AI's guess. Answers both correct the groups
/// and are stored to compute the accuracy percentage.
class VibeReviewScreen extends ConsumerStatefulWidget {
  const VibeReviewScreen({super.key});

  @override
  ConsumerState<VibeReviewScreen> createState() => _VibeReviewScreenState();
}

class _VibeReviewScreenState extends ConsumerState<VibeReviewScreen> {
  late final SonarAudioHandler _handler = ref.read(audioHandlerProvider);
  List<int>? _queue;
  int _i = 0;
  int _answered = 0;
  String? _mood, _genre; // current choice (null = the guess is still shown)
  bool _clipPlaying = false;

  @override
  void dispose() {
    if (_clipPlaying) _handler.pause();
    super.dispose();
  }

  void _newSession(List<TrackVibeData> data, Map<int, VibeResult> predicted, List<VibeLabel> labels) {
    _queue = pickReviewSample(data, predicted, {for (final l in labels) l.trackId}, count: _sampleSize);
    _i = 0;
    _answered = 0;
    _resetChoice();
  }

  void _resetChoice() {
    _mood = null;
    _genre = null;
  }

  Future<void> _playClip(Track t) async {
    if (_clipPlaying) {
      await _handler.pause();
      setState(() => _clipPlaying = false);
      return;
    }
    setState(() => _clipPlaying = true);
    await _handler.playTracks([t]);
    // From the middle of the song — the intro often doesn't show the mood
    await _handler.seek(t.duration * .4);
  }

  Future<void> _answer(int trackId, VibeResult? p, {required bool skip}) async {
    if (!skip) {
      await ref.read(analysisRepositoryProvider).saveLabel(VibeLabel(
            trackId: trackId,
            mood: _mood ?? moodKey(p?.mood),
            genre: _genre ?? genreKey(p?.genre),
            predictedMood: moodKey(p?.mood),
            predictedGenre: genreKey(p?.genre),
            labeledAt: DateTime.now(),
          ));
      _answered++;
    }
    if (_clipPlaying) {
      await _handler.pause();
      _clipPlaying = false;
    }
    if (!mounted) return;
    setState(() {
      _i++;
      _resetChoice();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(vibeDataProvider).value;
    // Read only the first time, so the guesses stay fixed during the session
    final predicted = ref.watch(vibePredictionsProvider).value;
    final labels = ref.watch(vibeLabelsProvider).value;
    final tracks = ref.watch(tracksProvider(_all)).value;

    Widget body;
    if (data == null || predicted == null || labels == null || tracks == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      if (_queue == null) _newSession(data, predicted, labels);
      final byId = {for (final t in tracks) t.id: t};
      final queue = _queue!.where(byId.containsKey).toList();
      if (queue.isEmpty && labels.isEmpty) {
        body = const _Message(
          icon: Icons.hourglass_top_rounded,
          title: 'Not enough analyzed songs yet',
          text: 'Let Nocturne finish analyzing your library (Menu → Your Vibes), then come back.',
        );
      } else if (_i >= queue.length) {
        body = _Results(
          report: accuracyOf(labels),
          current: currentAccuracy(labels, predicted),
          answeredNow: _answered,
          onMore: () => setState(() => _newSession(data, predicted, labels)),
        );
      } else {
        final t = byId[queue[_i]]!;
        final p = predicted[t.id];
        body = _ReviewCard(
          // New song = new scroll position (start from the top)
          key: ValueKey(t.id),
          track: t,
          position: _i + 1,
          total: queue.length,
          predictedMood: moodKey(p?.mood),
          predictedGenre: genreKey(p?.genre),
          mood: _mood ?? moodKey(p?.mood),
          genre: _genre ?? genreKey(p?.genre),
          clipPlaying: _clipPlaying,
          report: labels.isEmpty ? null : accuracyOf(labels),
          onMood: (v) => setState(() => _mood = v),
          onGenre: (v) => setState(() => _genre = v),
          onPlay: () => _playClip(t),
          onSave: () => _answer(t.id, p, skip: false),
          onSkip: () => _answer(t.id, p, skip: true),
        );
      }
    }

    return Scaffold(
      backgroundColor: AppColors.void_,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.textPrimary,
                ),
                Expanded(child: Text('Check smart groups', style: AppTypography.headlineMd)),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    super.key,
    required this.track,
    required this.position,
    required this.total,
    required this.predictedMood,
    required this.predictedGenre,
    required this.mood,
    required this.genre,
    required this.clipPlaying,
    required this.report,
    required this.onMood,
    required this.onGenre,
    required this.onPlay,
    required this.onSave,
    required this.onSkip,
  });

  final Track track;
  final int position, total;
  final String predictedMood, predictedGenre, mood, genre;
  final bool clipPlaying;
  final AccuracyReport? report;
  final ValueChanged<String> onMood, onGenre;
  final VoidCallback onPlay, onSave, onSkip;

  @override
  Widget build(BuildContext context) {
    final correct = mood == predictedMood && genre == predictedGenre;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.xxl),
      children: [
        Text('Song $position of $total', style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
        if (report != null)
          Text(
            'So far: mood ${_pct(report!.moodAccuracy)} • genre ${_pct(report!.genreAccuracy)} '
            '(${report!.total} answers)',
            style: AppTypography.labelSm,
          ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: position / total,
            minHeight: 3,
            backgroundColor: AppColors.surfaceHigh,
            color: AppColors.cyan,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AlbumArt(path: track.coverPath, seed: track.id, size: 88, radius: AppRadius.lg),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, style: AppTypography.headlineMd, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(track.artist, style: AppTypography.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.xs),
                  _Chip(
                    label: clipPlaying ? 'Pause' : 'Play a clip',
                    icon: clipPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    selected: false,
                    onTap: onPlay,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SolidCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI GUESSED', style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
              const SizedBox(height: 4),
              Text('${moodTitle(predictedMood)}  •  ${genreTitle(predictedGenre)}', style: AppTypography.titleSm),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('What mood is it really?', style: AppTypography.titleSm),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final k in [...Mood.values.map((m) => m.name), kNone])
              _Chip(label: moodTitle(k), selected: mood == k, onTap: () => onMood(k)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('And the genre?', style: AppTypography.titleSm),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final k in [...Genre.values.map((g) => g.name), kNone])
              _Chip(label: genreTitle(k), selected: genre == k, onTap: () => onGenre(k)),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // Too narrow side by side → stacked, the main button full width
        FilledButton.icon(
          onPressed: onSave,
          style: FilledButton.styleFrom(
            backgroundColor: correct ? AppColors.online.withValues(alpha: .85) : AppColors.electric,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          ),
          icon: Icon(correct ? Icons.check_rounded : Icons.edit_rounded, size: 18),
          label: Text(correct ? 'AI is right — next' : 'Save correction'),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: onSkip,
          child: Text("Don't know this song — skip",
              style: AppTypography.labelMd.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.report, required this.current, required this.answeredNow, required this.onMore});
  final AccuracyReport report;

  /// The current model against the same answers (differs after the algorithm is updated).
  final AccuracyReport current;
  final int answeredNow;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0, AppSpacing.screenH, AppSpacing.xxl),
      children: [
        Text('RESULTS', style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
        Text(
          'Based on ${report.total} answers${answeredNow > 0 ? ' ($answeredNow just now)' : ''}',
          style: AppTypography.bodySm,
        ),
        const SizedBox(height: AppSpacing.md),
        // Main number = current model; the result at answer time below, for comparison
        Row(
          children: [
            Expanded(child: _Score(title: 'Mood', value: current.moodAccuracy, ok: current.moodCorrect, n: current.total)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Score(title: 'Genre', value: current.genreAccuracy, ok: current.genreCorrect, n: current.total)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'When you checked: mood ${_pct(report.moodAccuracy)} • genre ${_pct(report.genreAccuracy)}',
          style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Errors(title: 'Most common mood mistakes', errors: current.moodErrors, name: moodTitle),
        const SizedBox(height: AppSpacing.md),
        _Errors(title: 'Most common genre mistakes', errors: current.genreErrors, name: genreTitle),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Your answers are kept as corrections — those songs now sit in the groups you chose.',
          style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: onMore,
          style: FilledButton.styleFrom(backgroundColor: AppColors.electric, foregroundColor: Colors.white),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Check more songs'),
        ),
      ],
    );
  }
}

String _pct(double v) => '${(v * 100).round()}%';

class _Score extends StatelessWidget {
  const _Score({required this.title, required this.value, required this.ok, required this.n});
  final String title;
  final double value;
  final int ok, n;

  @override
  Widget build(BuildContext context) {
    final color = value >= .75 ? AppColors.online : value >= .5 ? AppColors.warning : AppColors.error;
    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.labelMd),
          Text(_pct(value), style: AppTypography.headlineXl.copyWith(color: color)),
          Text('$ok of $n correct', style: AppTypography.labelSm),
        ],
      ),
    );
  }
}

class _Errors extends StatelessWidget {
  const _Errors({required this.title, required this.errors, required this.name});
  final String title;
  final List<ConfusionEntry> errors;
  final String Function(String) name;

  @override
  Widget build(BuildContext context) {
    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.titleSm),
          const SizedBox(height: AppSpacing.xs),
          if (errors.isEmpty) Text('None 🎉', style: AppTypography.bodySm),
          for (final e in errors.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'AI said ${name(e.predicted)} → really ${name(e.actual)}  ·  ${e.count}×',
                style: AppTypography.bodySm,
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.electric : AppColors.surfaceContainer,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.electric : AppColors.borderLevel1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: const Color(0x14FFFFFF),
        highlightColor: const Color(0x0AFFFFFF),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: AppColors.textPrimary), const SizedBox(width: 4)],
              Text(label,
                  style: AppTypography.labelMd.copyWith(color: selected ? Colors.white : AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTypography.headlineMd, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(text, style: AppTypography.bodySm, textAlign: TextAlign.center),
          ],
        ),
      );
}
