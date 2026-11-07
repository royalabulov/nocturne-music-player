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

void main() {
  late PlayQueue q;
  final five = [for (var i = 1; i <= 5; i++) _t(i)];

  setUp(() => q = PlayQueue(random: Random(1)));

  /// The ids in the order they would play.
  List<int> played() => [for (final i in q.order) q.tracks[i].id];

  group('next', () {
    setUp(() => q.replace(five, startIndex: 4));

    test('an empty queue has no next', () {
      expect(PlayQueue().next(), isNull);
      expect(PlayQueue().next(manual: true), isNull);
    });

    test('the last song ends the queue', () {
      expect(q.next(), isNull);
      expect(q.next(manual: true), isNull);
    });

    test('repeat all goes back to the start', () {
      q.repeat = AudioServiceRepeatMode.all;
      expect(q.next(), 0);
    });

    test('repeat one stays when a song ends, moves when the user asks', () {
      q
        ..repeat = AudioServiceRepeatMode.one
        ..pos = 2;
      expect(q.next(), 2);
      expect(q.next(manual: true), 3);
    });
  });

  test('previous wraps from the first song to the last', () {
    q.replace(five);
    expect(q.previous, 4);
    q.pos = 3;
    expect(q.previous, 2);
  });

  group('replace', () {
    test('an empty list changes nothing', () {
      q
        ..replace(five, startIndex: 2)
        ..replace(const []);
      expect(q.current?.id, 3);
    });

    test('a start beyond the list is the last song', () {
      q.replace(five, startIndex: 99);
      expect(q.current?.id, 5);
    });

    test('shuffle starts with the chosen song and keeps every song once', () {
      q.replace(five, startIndex: 2, shuffled: true);
      expect(q.pos, 0);
      expect(q.current?.id, 3);
      expect(played().toSet(), {1, 2, 3, 4, 5});
      expect(played(), hasLength(5));
    });

    test('the caller\'s list is not touched later', () {
      final mine = [_t(1)];
      q
        ..replace(mine)
        ..append([_t(2)]);
      expect(mine, hasLength(1));
    });
  });

  group('adding', () {
    setUp(() => q.replace(five, startIndex: 1));

    test('play next goes right after the current song', () {
      q.insertNext(_t(9));
      expect(q.trackAt(q.next())?.id, 9);
      expect(q.current?.id, 2);
    });

    test('in shuffle too', () {
      q
        ..setModes(shuffled: true, repeatMode: AudioServiceRepeatMode.none)
        ..insertNext(_t(9));
      expect(q.trackAt(q.next())?.id, 9);
    });

    test('enqueue goes to the end', () {
      q.append([_t(8), _t(9)]);
      expect(played().sublist(5), [8, 9]);
      expect(q.current?.id, 2);
    });
  });

  group('remove', () {
    test('an unknown song', () {
      q.replace(five);
      expect(q.remove(42), isNull);
      expect(q.tracks, hasLength(5));
    });

    test('before the current song: the same song keeps playing', () {
      q.replace(five, startIndex: 2);
      expect(q.remove(1), isFalse);
      expect(q.current?.id, 3);
    });

    test('after the current song', () {
      q.replace(five, startIndex: 2);
      expect(q.remove(5), isFalse);
      expect(q.current?.id, 3);
      expect(played(), [1, 2, 3, 4]);
    });

    test('the current song: the next one takes its place', () {
      q.replace(five, startIndex: 2);
      expect(q.remove(3), isTrue);
      expect(q.current?.id, 4);
    });

    test('the current song at the end: the new last one', () {
      q.replace(five, startIndex: 4);
      expect(q.remove(5), isTrue);
      expect(q.current?.id, 4);
    });

    test('the only song leaves an empty queue', () {
      q.replace([_t(1)]);
      expect(q.remove(1), isTrue);
      expect(q.isEmpty, isTrue);
      expect(q.current, isNull);
      expect(q.currentIndex, isNull);
    });

    test('in shuffle the rest of the order stays', () {
      q.replace(five, shuffled: true);
      final before = played();
      final gone = before[3];
      q.remove(gone);
      expect(played(), [...before]..remove(gone));
    });
  });

  group('modes', () {
    test('turning shuffle on and off keeps the current song', () {
      q.replace(five, startIndex: 3);
      expect(q.setModes(shuffled: true, repeatMode: AudioServiceRepeatMode.none), isTrue);
      expect(q.current?.id, 4);
      expect(q.setModes(shuffled: false, repeatMode: AudioServiceRepeatMode.none), isTrue);
      expect(q.current?.id, 4);
      expect(played(), [1, 2, 3, 4, 5]);
    });

    test('changing only repeat keeps the order', () {
      q.replace(five, shuffled: true);
      final before = played();
      expect(q.setModes(shuffled: true, repeatMode: AudioServiceRepeatMode.all), isFalse);
      expect(played(), before);
      expect(q.repeat, AudioServiceRepeatMode.all);
    });

    test('an empty queue remembers the modes without failing', () {
      expect(q.setModes(shuffled: true, repeatMode: AudioServiceRepeatMode.one), isFalse);
      expect(q.shuffle, isTrue);
      expect(q.repeat, AudioServiceRepeatMode.one);
    });
  });

  test('clear leaves nothing playing but keeps the modes', () {
    q
      ..replace(five, shuffled: true)
      ..clear();
    expect(q.isEmpty, isTrue);
    expect(q.current, isNull);
    expect(q.next(), isNull);
    expect(q.shuffle, isTrue);
  });
}
