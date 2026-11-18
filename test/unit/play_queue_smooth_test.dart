import 'dart:math';

import 'package:audio_service/audio_service.dart' show AudioServiceRepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/play_queue.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

Track _t(int id) => Track(
      id: id,
      path: '/m/$id.mp3',
      title: 'Song $id',
      artist: 'A',
      album: 'B',
      duration: const Duration(minutes: 3),
      format: AudioFormat.mp3,
    );

/// Smooth shuffle's part of the queue: the songs still to come take the better order.
void main() {
  late PlayQueue q;
  final six = [for (var i = 1; i <= 6; i++) _t(i)];

  setUp(() => q = PlayQueue(random: Random(1)));

  test('the songs to come follow the better order; the current one stays', () {
    q.replace(six, startIndex: 2, shuffled: true);
    expect(q.order.first, 2);

    expect(q.reorderUpcoming([2, 5, 4, 3, 1, 0]), isTrue);
    expect(q.order, [2, 5, 4, 3, 1, 0]);
    expect(q.pos, 0);
    expect(q.smooth, isTrue);
  });

  test('songs already played keep their place, whatever the better order says', () {
    q.replace(six, startIndex: 0, shuffled: true);
    final before = List.of(q.order);
    q.pos = 2; // two songs skipped while the order was worked out

    expect(q.reorderUpcoming([0, 1, 2, 3, 4, 5]), isTrue);
    expect(q.order.sublist(0, 3), before.sublist(0, 3));
    expect(q.order.toSet(), {0, 1, 2, 3, 4, 5});
    final rest = q.order.sublist(3);
    expect(rest, List.of(rest)..sort(), reason: 'in the better order');
  });

  test('an order that does not fit this queue is refused', () {
    q.replace(six, shuffled: true);
    final before = List.of(q.order);
    expect(q.reorderUpcoming([0, 1, 2]), isFalse, reason: 'too short');
    expect(q.reorderUpcoming([0, 1, 2, 3, 4, 4]), isFalse, reason: 'a song twice');
    expect(q.reorderUpcoming([0, 1, 2, 3, 4, 9]), isFalse, reason: 'no such song');
    expect(q.order, before);
    expect(q.smooth, isFalse);
    expect(PlayQueue().reorderUpcoming(const []), isFalse, reason: 'empty queue');
  });

  test('a new list, shuffle off and a restore all forget the smooth order', () {
    q.replace(six, shuffled: true);
    q.reorderUpcoming([for (final i in q.order) i]);
    q.replace(six, shuffled: true);
    expect(q.smooth, isFalse);

    q.reorderUpcoming([for (final i in q.order) i]);
    q.setModes(shuffled: false, repeatMode: AudioServiceRepeatMode.none);
    expect(q.smooth, isFalse);

    q.setModes(shuffled: true, repeatMode: AudioServiceRepeatMode.none);
    q.reorderUpcoming([for (final i in q.order) i]);
    q.restore(six, [0, 1, 2, 3, 4, 5], 0, shuffled: true, repeatMode: AudioServiceRepeatMode.none);
    expect(q.smooth, isFalse);

    q.reorderUpcoming([0, 1, 2, 3, 4, 5]);
    q.clear();
    expect(q.smooth, isFalse);
  });
}
