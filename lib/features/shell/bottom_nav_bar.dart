import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

class NavItem {
  const NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const navItems = <NavItem>[
  NavItem('Home', Icons.home_outlined, Icons.home_rounded),
  NavItem('Recent', Icons.history_rounded, Icons.history_rounded),
  NavItem('Favorites', Icons.favorite_border_rounded, Icons.favorite_rounded),
  NavItem('Playlists', Icons.queue_music_rounded, Icons.queue_music_rounded),
];

const _barHeight = AppSpacing.bottomNavHeight;
const _gap = 10.0;
const _animDuration = Duration(milliseconds: 280);
const _splash = Color(0x14FFFFFF); // white, 8%
const _highlight = Color(0x0AFFFFFF); // white, 4%

/// Floating dock in the iOS WhatsApp style: tabs inside a rounded "pill",
/// a sliding highlight behind the active tab, a separate round search button on the right.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key, required this.index, required this.onTap, required this.onSearch});

  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // No blur: the dock is always on screen and BackdropFilter re-processed the
    // background on every scroll frame (one of the main causes of jank).
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, bottomInset + AppSpacing.sm),
      child: SizedBox(
        height: _barHeight,
        child: Row(
          children: [
            Expanded(
              child: _Capsule(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final itemW = c.maxWidth / navItems.length;
                    // On screens not in the menu, like Settings, no tab is active
                    final onNav = index < navItems.length;
                    return Stack(
                      children: [
                        // Sliding pill behind the active tab
                        if (onNav)
                          AnimatedPositioned(
                            duration: _animDuration,
                            curve: Curves.easeOutCubic,
                            left: index * itemW,
                            top: 0,
                            bottom: 0,
                            width: itemW,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.electric.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(_barHeight),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            for (var i = 0; i < navItems.length; i++)
                              Expanded(
                                child: _NavButton(item: navItems[i], active: i == index, onTap: () => onTap(i)),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: _gap),
            SizedBox(
              width: _barHeight,
              child: _Capsule(
                child: InkWell(
                  onTap: onSearch,
                  customBorder: const CircleBorder(),
                  splashColor: _splash,
                  highlightColor: _highlight,
                  child: const Center(child: Icon(Icons.search_rounded, color: AppColors.textPrimary, size: 26)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dark glass capsule — for both the tab group and the search button.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // Fully opaque: a 96% background let the text behind show faintly
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_barHeight),
        border: Border.all(color: AppColors.borderLevel2),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.onTap});

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.electric : AppColors.textSecondary;
    // The press effect is clipped to the pill shape — a soft glow, not a white square.
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      splashColor: _splash,
      highlightColor: _highlight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: active ? 1.08 : 1,
            duration: _animDuration,
            curve: Curves.easeOutBack,
            child: Icon(active ? item.activeIcon : item.icon, color: color, size: 22),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: AppTypography.labelSm.copyWith(color: color, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
