import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/glass.dart';
import '../../core/ui/toast.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/history_repository.dart';
import '../../l10n/l10n.dart';
import '../../shared/album_art.dart';
import '../../core/utils/display_names.dart';
import '../../shared/empty_state.dart';
import '../../shared/glow_play_button.dart';
import '../tracks/track_sliver_list.dart';
import '../../shared/action_pill.dart';
import '../../core/audio/player_providers.dart';
import 'forgotten.dart';
import 'forgotten_reminder.dart';
import '../../shared/screen_back_button.dart';

/// Menu → Forgotten favorites: songs played a lot (or favorites) that haven't been
/// played for a while. The rule (plays, days) is set at the top of the screen.
class ForgottenScreen extends ConsumerStatefulWidget {
  const ForgottenScreen({super.key, this.highlightId});

  /// Opened from a reminder: this song is shown in a card on top.
  final int? highlightId;

  @override
  ConsumerState<ForgottenScreen> createState() => _ForgottenScreenState();
}

class _ForgottenScreenState extends ConsumerState<ForgottenScreen> {
  /// The "Adjust" card is open.
  bool _rulesOpen = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(forgottenSettingsProvider);
    final loaded = ref.watch(forgottenProvider).value;
    final items = loaded ?? const <PlayedTrack>[];
    final meta = {for (final p in items) p.track.id: p};
    final tracks = [for (final p in items) p.track];
    final handler = ref.read(audioHandlerProvider);

    String subtitle(Track t) {
      final p = meta[t.id];
      if (p == null) return t.artistLabel;
      final days = DateTime.now().difference(p.lastPlayedAt).inDays;
      return '${p.playCount}× • ${l10n.agoDays(days)} • ${t.artistLabel}';
    }

    return Scaffold(
      backgroundColor: AppColors.void_,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverList.list(
              children: [
                Row(
                  children: [
                    const ScreenBackButton(),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.menuForgotten, style: AppTypography.headlineXl),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.forgottenRule(settings.minPlays, settings.days),
                        style: AppTypography.bodyMd.copyWith(color: AppColors.textSecondary),
                      ),
                      if (meta[widget.highlightId] case final p?) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _FromReminderCard(
                          played: p,
                          onPlay: () => handler.playTracks(tracks, startIndex: tracks.indexOf(p.track)),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      _RuleCard(
                        settings: settings,
                        open: _rulesOpen,
                        onToggle: () => setState(() => _rulesOpen = !_rulesOpen),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _ReminderCard(),
                      if (tracks.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            ActionPill(
                              icon: Icons.play_arrow_rounded,
                              label: l10n.playAll,
                              primary: true,
                              onTap: () => handler.playTracks(tracks),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            ActionPill(
                              icon: Icons.shuffle_rounded,
                              label: l10n.shuffle,
                              onTap: () => handler.playTracks(tracks, shuffle: true),
                            ),
                            const Spacer(),
                            Text(l10n.trackCount(tracks.length), style: AppTypography.labelSm),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ],
            ),
            if (loaded != null && tracks.isEmpty)
              // Empty: say why (the rule is right above)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.history_toggle_off_rounded,
                  title: l10n.forgottenEmptyTitle,
                  message: l10n.forgottenEmpty,
                ),
              )
            else
              TrackSliverList(tracks: tracks, subtitle: subtitle),
            const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.dockOffset + AppSpacing.miniPlayerHeight)),
          ],
        ),
      ),
    );
  }
}

/// The rule, collapsible: "Played at least − 5× +" (the number can be typed) and
/// "Not played for" 7 · 15 · 30 · 60 · 90 · Custom… days.
class _RuleCard extends ConsumerWidget {
  const _RuleCard({required this.settings, required this.open, required this.onToggle});
  final ForgottenSettings settings;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settings;
    final custom = !ForgottenSettings.quickDays.contains(s.days);
    final ctrl = ref.read(forgottenSettingsProvider.notifier);
    return SolidCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(l10n.forgottenAdjust, style: AppTypography.titleSm)),
                  AnimatedRotation(
                    turns: open ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(l10n.forgottenMinPlays, style: AppTypography.bodyMd)),
                            _StepButton(
                              icon: Icons.remove_rounded,
                              tooltip: l10n.decrease,
                              onTap: s.minPlays > ForgottenSettings.minPlaysRange.min
                                  ? () => ctrl.set(minPlays: s.minPlays - 1)
                                  : null,
                            ),
                            _NumberField(
                              value: s.minPlays,
                              suffix: '×',
                              onChanged: (v) => ctrl.set(minPlays: v),
                            ),
                            _StepButton(
                              icon: Icons.add_rounded,
                              tooltip: l10n.increase,
                              onTap: s.minPlays < ForgottenSettings.minPlaysRange.max
                                  ? () => ctrl.set(minPlays: s.minPlays + 1)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(l10n.forgottenDays, style: AppTypography.bodyMd),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final d in ForgottenSettings.quickDays)
                              _QuickChip(
                                label: l10n.forgottenDaysN(d),
                                selected: s.days == d,
                                onTap: () => ctrl.set(days: d),
                              ),
                            // Any other number: typed in a small dialog
                            _QuickChip(
                              label: custom ? l10n.forgottenDaysN(s.days) : l10n.forgottenCustom,
                              icon: Icons.edit_outlined,
                              selected: custom,
                              onTap: () async {
                                final v = await _askDays(context, s.days);
                                if (v != null) unawaited(ctrl.set(days: v));
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The song a reminder named — on top when the screen is opened from it.
class _FromReminderCard extends StatelessWidget {
  const _FromReminderCard({required this.played, required this.onPlay});
  final PlayedTrack played;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final t = played.track;
    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onPlay,
      child: Row(
        children: [
          AlbumArt(path: t.coverPath, seed: t.id, size: 56, radius: AppRadius.md),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined, size: 14, color: AppColors.cyan),
                    const SizedBox(width: 4),
                    Text(l10n.reminderFrom, style: AppTypography.labelSm.copyWith(color: AppColors.cyan)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(t.title, style: AppTypography.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${played.playCount}× • ${t.artistLabel}',
                  style: AppTypography.labelSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GlowPlayButton(size: 44, onTap: onPlay),
        ],
      ),
    );
  }
}

/// Reminder: on/off, which weekdays (as many as you like = times a week), what time.
/// Turning it on asks for the notification permission first.
class _ReminderCard extends ConsumerWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(reminderSettingsProvider);
    final ctrl = ref.read(reminderSettingsProvider.notifier);
    final time = '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';
    final dayNames = l10n.reminderWeekdays.split(',');

    Future<void> toggle(bool on) async {
      if (on && !await ref.read(forgottenReminderProvider).requestPermission()) {
        showToast(l10n.reminderPermissionDenied, error: true);
        return;
      }
      await ctrl.set(s.copyWith(enabled: on));
    }

    return SolidCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_outlined, color: AppColors.textSecondary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.reminder, style: AppTypography.titleSm),
                    Text(
                      s.enabled ? l10n.reminderSummary(s.weekdays.length == 7 ? l10n.reminderEveryDay : l10n.reminderTimesAWeek(s.weekdays.length), time) : l10n.reminderOff,
                      style: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(value: s.enabled, onChanged: toggle),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !s.enabled
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.reminderDays, style: AppTypography.bodyMd),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                            _QuickChip(
                              label: dayNames[d - 1],
                              selected: s.weekdays.contains(d),
                              onTap: () {
                                final days = {...s.weekdays};
                                // At least one day stays on (switch the reminder off instead)
                                if (!days.remove(d)) days.add(d);
                                if (days.isNotEmpty) unawaited(ctrl.set(s.copyWith(weekdays: days)));
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(child: Text(l10n.reminderTime, style: AppTypography.bodyMd)),
                          ActionPill(
                            icon: Icons.schedule_rounded,
                            label: time,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
                                builder: (context, child) => MediaQuery(
                                  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                                  child: child!,
                                ),
                              );
                              if (picked != null) unawaited(ctrl.set(s.copyWith(hour: picked.hour, minute: picked.minute)));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// − / + : full 48 dp touch target, named for screen readers.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        icon: Icon(icon, size: 22),
        color: AppColors.textPrimary,
        disabledColor: AppColors.textMuted,
      );
}

/// "Custom…": type the number of days (1–365).
Future<int?> _askDays(BuildContext context, int current) {
  final ctrl = TextEditingController(text: '$current');
  int? parse() => int.tryParse(ctrl.text);
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      title: Text(l10n.forgottenDays, style: AppTypography.headlineMd),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        style: AppTypography.bodyMd,
        cursorColor: AppColors.cyan,
        onSubmitted: (_) => Navigator.pop(ctx, parse()),
        decoration: InputDecoration(
          suffixText: l10n.forgottenDaysUnit,
          helperText: l10n.forgottenDaysRange,
          filled: true,
          fillColor: AppColors.surfaceContainer,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, parse()),
          style: FilledButton.styleFrom(backgroundColor: AppColors.electric),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
}

/// A small number box: type a value, it's saved on "done" or when focus leaves.
/// Follows outside changes (−/+ buttons) when not being edited.
class _NumberField extends StatefulWidget {
  const _NumberField({required this.value, required this.suffix, required this.onChanged});
  final int value;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _ctrl = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _ctrl.text != '${widget.value}') _ctrl.text = '${widget.value}';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = int.tryParse(_ctrl.text);
    if (v == null || v == widget.value) {
      _ctrl.text = '${widget.value}';
    } else {
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        textAlign: TextAlign.center,
        style: AppTypography.titleSm,
        cursorColor: AppColors.cyan,
        onSubmitted: (_) => _focus.unfocus(),
        decoration: InputDecoration(
          isDense: true,
          suffixText: widget.suffix,
          suffixStyle: AppTypography.labelSm.copyWith(color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.surfaceHigh,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // 40 dp tall + the Wrap's spacing ≈ the 48 dp touch target
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.electric : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: AppTypography.labelMd.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
