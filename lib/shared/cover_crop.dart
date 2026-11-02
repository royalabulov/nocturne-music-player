import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where the picture really is inside a cover file. Covers taken from videos
/// often carry black bars (a 16:9 frame inside a 4:3 or square image) —
/// AlbumArt zooms past them (design review, 2026-11-02). Files stay untouched.
@immutable
class CoverCrop {
  const CoverCrop(this.aspect, this.content);

  /// Width / height of the whole image.
  final double aspect;

  /// The picture without the bars, as fractions (0–1) of the image.
  final Rect content;
}

/// Results per cover path for this session (null = no bars).
final _known = <String, CoverCrop?>{};
final _running = <String, Future<CoverCrop?>>{};

/// Already checked? Then [cachedCoverCrop] is the answer, without waiting.
bool isCoverCropKnown(String path) => _known.containsKey(path);
CoverCrop? cachedCoverCrop(String path) => _known[path];

/// Checks a cover once (a 64px copy is enough to see bars).
Future<CoverCrop?> coverCrop(String path) => _running[path] ??= _detect(path).then((c) {
      _known[path] = c;
      _running.remove(path);
      return c;
    });

Future<CoverCrop?> _detect(String path) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await File(path).readAsBytes());
    var (w, h) = (0, 0);
    final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (iw, ih) {
      (w, h) = (iw, ih);
      final s = 64 / max(iw, ih);
      return ui.TargetImageSize(width: max(1, (iw * s).round()), height: max(1, (ih * s).round()));
    });
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final (sw, sh) = (img.width, img.height);
    img.dispose();
    codec.dispose();
    if (data == null || w == 0 || h == 0) return null;
    final content = letterboxOf(data.buffer.asUint8List(), sw, sh);
    return content == null ? null : CoverCrop(w / h, content);
  } catch (_) {
    return null; // unreadable cover → shown as it is
  }
}

/// The picture area inside matching black bars on two opposite sides, or null.
/// Bars must be on both sides, about the same size and at least 5% each — so
/// a dark sky or a black frame line in real artwork isn't cut away.
@visibleForTesting
Rect? letterboxOf(Uint8List rgba, int w, int h) {
  bool dark(int x, int y) {
    final i = (y * w + x) * 4;
    return rgba[i] < 28 && rgba[i + 1] < 28 && rgba[i + 2] < 28;
  }

  // 97%: JPEG noise leaves a few lighter pixels in a black bar
  bool row(int y) => List.generate(w, (x) => dark(x, y)).where((d) => d).length >= w * .97;
  bool col(int x) => List.generate(h, (y) => dark(x, y)).where((d) => d).length >= h * .97;

  (int, int)? bars(int n, bool Function(int) bar) {
    var a = 0;
    while (a < n && bar(a)) {
      a++;
    }
    var b = n;
    while (b > a && bar(b - 1)) {
      b--;
    }
    final (lead, trail) = (a, n - b);
    if (min(lead, trail) < n * .05 || (lead - trail).abs() > max(2, n * .03) || b - a < n * .4) return null;
    // One more line each side: the edge row is half bar, half picture after scaling
    return (a + 1, b - 1);
  }

  final v = bars(h, row);
  if (v != null) return Rect.fromLTRB(0, v.$1 / h, 1, v.$2 / h);
  final hz = bars(w, col);
  if (hz != null) return Rect.fromLTRB(hz.$1 / w, 0, hz.$2 / w, 1);
  return null;
}
