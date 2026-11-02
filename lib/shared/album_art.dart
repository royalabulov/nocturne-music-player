import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import 'cover_crop.dart';

/// Album art: 16px radius + 1px inset hairline. Without a cover,
/// a gradient placeholder + note icon. Black video bars are zoomed past (CoverCrop).
class AlbumArt extends StatefulWidget {
  const AlbumArt({
    super.key,
    this.path,
    this.size = 56,
    this.radius = AppRadius.lg,
    this.seed = 0,
  });

  final String? path;
  final double size;
  final double radius;

  /// Used to vary the placeholder colour (track id).
  final int seed;

  @override
  State<AlbumArt> createState() => _AlbumArtState();
}

class _AlbumArtState extends State<AlbumArt> {
  @override
  void initState() {
    super.initState();
    _checkBars();
  }

  @override
  void didUpdateWidget(AlbumArt old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _checkBars();
  }

  /// First time a cover shows up this session: look for bars, then redraw.
  void _checkBars() {
    final p = widget.path;
    if (kIsWeb || p == null || p.isEmpty || isCoverCropKnown(p)) return;
    coverCrop(p).then((c) {
      if (c != null && mounted && widget.path == p) setState(() {});
    });
  }

  double get size => widget.size;

  @override
  Widget build(BuildContext context) {
    final p = widget.path;
    final Widget content;
    if (!kIsWeb && p != null && p.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final crop = cachedCoverCrop(p);
      if (crop == null) {
        // Decode at on-screen size: full size (1000×1000+) for 400 tiles means
        // hundreds of MB of RAM + jank. Only the height is given so the aspect
        // ratio stays — width + height squashed non-square covers (mostly wide
        // video frames, hence height).
        content = Image.file(
          File(p),
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheHeight: (size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _placeholder(),
        );
      } else {
        // Scale the whole image so the picture (without bars) covers the square
        final c = crop.content;
        final h = size / min(c.width * crop.aspect, c.height);
        final w = h * crop.aspect;
        content = SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              Positioned(
                left: size / 2 - c.center.dx * w,
                top: size / 2 - c.center.dy * h,
                width: w,
                height: h,
                child: Image.file(
                  File(p),
                  fit: BoxFit.fill,
                  cacheHeight: (h * dpr).round(),
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _placeholder(),
                ),
              ),
            ],
          ),
        );
      }
    } else {
      content = _placeholder();
    }
    final radius = widget.radius;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderArt),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _placeholder() {
    final hue = (widget.seed * 47) % 360;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue.toDouble(), .45, .22).toColor(),
            AppColors.void_,
          ],
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        color: AppColors.cyan.withValues(alpha: .7),
        size: size * .4,
      ),
    );
  }
}
