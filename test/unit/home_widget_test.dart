import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/theme/app_colors.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';
import 'package:nocturne/features/home_widget/home_widget_sync.dart';

void main() {
  const track = Track(
    id: 7,
    path: '/music/a.mp3',
    title: 'Üç Kalp',
    artist: 'Sezen Aksu',
    album: 'X',
    duration: Duration(minutes: 3),
    format: AudioFormat.mp3,
    coverPath: '/covers/7.jpg',
    fileSize: 1,
  );

  Map<String, Object?> state({Track? t = track, bool playing = true}) => widgetState(
        track: t,
        playing: playing,
        shuffle: true,
        repeat: AudioServiceRepeatMode.one,
        favorite: true,
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 3),
        cover: AppColors.electric,
      );

  test('the widgets get the song, the buttons and their names', () {
    final s = state();
    expect(s['track'], isTrue);
    expect(s['title'], 'Üç Kalp');
    // Through artistLabel ("Unknown Artist" would be translated)
    expect(s['artist'], 'Sezen Aksu');
    expect(s['cover'], '/covers/7.jpg');
    expect(s['repeat'], 'one');
    expect(s['position'], 42000);
    expect(s['duration'], 180000);
    final labels = s['labels']! as Map;
    // Every name HomeWidgets.kt asks for
    for (final key in ['play', 'pause', 'previous', 'next', 'shuffleOn', 'shuffleOff', 'repeat_none', 'repeat_all', 'repeat_one', 'addFavorite', 'removeFavorite', 'emptyTitle', 'emptyHint']) {
      expect(labels[key], isNotEmpty, reason: key);
    }
    expect(() => jsonEncode(s), returnsNormally);
  });

  test('nothing queued: no song and never "playing"', () {
    final s = state(t: null);
    expect(s['track'], isFalse);
    expect(s['playing'], isFalse);
    expect(s['title'], '');
  });

  test('the body is the glass with 16 % of the cover colour, opaque', () {
    final tint = widgetTint(AppColors.electric);
    expect(tint.a, 1);
    final glass = AppColors.glassLevel2Solid.withValues(alpha: 1);
    // Between the glass and the cover colour, much nearer the glass
    expect(tint.b, greaterThan(glass.b));
    expect(tint.b, lessThan(glass.b + .16 * (AppColors.electric.b - glass.b) + .01));
  });

  test('widget layouts use only what a launcher may inflate (Android 10+)', () {
    // Anything else (even a plain View spacer) and the launcher refuses the whole widget:
    // "Couldn't add widget" (2026-11-13, the large widget)
    const allowed = {
      'FrameLayout', 'LinearLayout', 'RelativeLayout', 'GridLayout', 'AnalogClock', 'Button', 'Chronometer',
      'ImageButton', 'ImageView', 'ProgressBar', 'TextView', 'ViewFlipper', 'ListView', 'GridView',
      'StackView', 'AdapterViewFlipper', 'ViewStub',
    };
    final layouts = Directory('android/app/src/main/res/layout')
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('widget_'))
        .toList();
    expect(layouts, hasLength(3));
    final tag = RegExp(r'<([A-Za-z][\w.]*)[\s>/]');
    for (final f in layouts) {
      final used = tag.allMatches(f.readAsStringSync()).map((m) => m[1]!).toSet();
      expect(used.difference(allowed), isEmpty, reason: f.path);
    }
  });

  test('every key the Dart side sends is read by the Kotlin side', () {
    final kotlin = File('android/app/src/main/kotlin/com/nocturne/HomeWidgets.kt').readAsStringSync();
    for (final key in state().keys.where((k) => k != 'labels')) {
      expect(kotlin, contains('"$key"'), reason: key);
    }
  });
}
