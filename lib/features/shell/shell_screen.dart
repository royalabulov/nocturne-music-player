import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/locate_track.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../player/player_providers.dart';
import '../selection/selection_bar.dart';
import '../selection/track_selection.dart';
import 'bottom_nav_bar.dart';
import 'mini_player.dart';
import 'side_menu.dart';

/// Main scaffold with tabs. Each tab keeps its own navigation stack
/// (StatefulShellRoute.indexedStack). Mini-player + dock at the bottom.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({
    super.key,
    required this.navigationShell,
    required this.location,
  });

  final StatefulNavigationShell navigationShell;

  /// Current route — multi-select closes when it changes (tab, playlist opened/closed).
  final String location;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void didUpdateWidget(ShellScreen old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) {
      // Providers can't change during build → after the frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(trackSelectionProvider.notifier).clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selecting = ref.watch(trackSelectionProvider.select((s) => s.active));
    final track = ref.watch(currentTrackProvider).value;
    final playing = ref.watch(isPlayingProvider);
    final handler = ref.read(audioHandlerProvider);

    // Settings isn't in the bottom menu (opened from the side menu) → back returns to Home
    final offNav = navigationShell.currentIndex >= navItems.length;

    // In selection mode, back closes the selection first
    return PopScope(
      canPop: !selecting && !offNav,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          ref.read(trackSelectionProvider.notifier).clear();
        } else {
          navigationShell.goBranch(0);
        }
      },
      child: Scaffold(
        key: sideMenuKey,
        extendBody: true,
        drawer: SideMenu(location: widget.location),
        drawerScrimColor: const Color(0xB3000000),
        body: navigationShell,
        bottomNavigationBar: selecting
            ? const SelectionBar()
            // List text showed through behind the floating menu and the system
            // navigation bar → a top-to-bottom darkening background (no blur — it's cheap).
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .35, 1],
                    colors: [
                      Color(0x000A0E14),
                      Color(0xE60A0E14),
                      AppColors.void_,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (track != null)
                        MiniPlayer(
                          track: track,
                          progressBar: const _MiniProgress(),
                          playing: playing,
                          onTap: () {
                            // Search kept its focus → when Now Playing closed, Flutter
                            // restored focus and the keyboard popped up
                            FocusManager.instance.primaryFocus?.unfocus();
                            context.push('/now-playing');
                          },
                          onPlayPause: playing ? handler.pause : handler.play,
                          onNext: handler.skipToNext,
                        ),
                      BottomNavBar(
                        index: navigationShell.currentIndex,
                        onTap: (i) => navigationShell.goBranch(
                          i,
                          // Tapping the current tab again returns to its root.
                          initialLocation: i == navigationShell.currentIndex,
                        ),
                        onSearch: () {
                          // Go to Home's root, then focus search
                          navigationShell.goBranch(0, initialLocation: true);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              ref.read(focusSearchProvider.notifier).request();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// The position stream rebuilds only this 2px strip — not the mini-player or the shell.
class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;
    final progress = dur.inMilliseconds == 0
        ? 0.0
        : pos.inMilliseconds / dur.inMilliseconds;
    return MiniProgressStrip(progress: progress);
  }
}
