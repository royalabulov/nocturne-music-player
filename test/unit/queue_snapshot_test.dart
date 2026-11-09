import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/queue_snapshot.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/track.dart';

/// The queue is stored so it survives Android ending the app; before, it was lost.
void main() {
  Track track(int id) => Track(
        id: id,
        path: '/m/$id.mp3',
        title: 'T$id',
        artist: 'A',
        album: 'B',
        duration: const Duration(minutes: 3),
        format: AudioFormat.mp3,
      );

  const snap = QueueSnapshot(
    trackIds: [10, 20, 30, 40],
    order: [2, 0, 3, 1],
    pos: 1,
    shuffle: true,
    repeat: AudioServiceRepeatMode.all,
  );

  test('comes back as it was stored', () {
    final back = QueueSnapshot.decode(snap.encode())!;
    expect(back.trackIds, snap.trackIds);
    expect(back.order, snap.order);
    expect(back.pos, 1);
    expect(back.shuffle, isTrue);
    expect(back.repeat, AudioServiceRepeatMode.all);
    expect(back.closed, isFalse);
    expect(back.currentId, 10);
    expect(QueueSnapshot.decode(snap.asClosed().encode())!.closed, isTrue);
  });

  test('a broken or half-written value is no queue, not a crash at start', () {
    for (final raw in [
      null,
      '',
      'not json',
      '[]',
      '{"ids":[1,2],"order":[0],"pos":0,"shuffle":false,"repeat":"none"}', // order too short
      '{"ids":[1,2],"order":[0,0],"pos":0,"shuffle":false,"repeat":"none"}', // index twice
      '{"ids":[1,2],"order":[0,5],"pos":0,"shuffle":false,"repeat":"none"}', // index outside
      '{"ids":[1,2],"order":[0,1],"pos":2,"shuffle":false,"repeat":"none"}', // pos outside
      '{"ids":[1,2],"order":[0,1],"pos":0,"shuffle":false,"repeat":"sometimes"}',
      '{"ids":[],"order":[],"pos":0,"shuffle":false,"repeat":"none"}',
      '{"ids":["a"],"order":[0],"pos":0,"shuffle":false,"repeat":"none"}',
    ]) {
      expect(QueueSnapshot.decode(raw), isNull, reason: '$raw');
    }
  });

  group('made of the songs still in the library', () {
    final all = {for (final id in [10, 20, 30, 40]) id: track(id)};

    test('all there: same order, same place in the song', () {
      final q = SavedQueue.from(snap, all, position: const Duration(seconds: 7))!;
      expect([for (final i in q.order) q.tracks[i].id], [30, 10, 40, 20]);
      expect(q.tracks[q.order[q.pos]].id, 10);
      expect(q.position, const Duration(seconds: 7));
    });

    test('a deleted song drops out, the current one keeps its place', () {
      final q = SavedQueue.from(snap, {...all}..remove(30), position: const Duration(seconds: 7))!;
      expect([for (final i in q.order) q.tracks[i].id], [10, 40, 20]);
      expect(q.tracks[q.order[q.pos]].id, 10);
      expect(q.position, const Duration(seconds: 7));
    });

    test('the current song deleted: the next one, from the start', () {
      final q = SavedQueue.from(snap, {...all}..remove(10), position: const Duration(seconds: 7))!;
      expect(q.tracks[q.order[q.pos]].id, 40);
      expect(q.position, Duration.zero);
    });

    test('the current and everything after it deleted: the last one left', () {
      final q = SavedQueue.from(snap, {30: track(30)})!;
      expect(q.tracks[q.order[q.pos]].id, 30);
    });

    test('nothing left: no queue', () {
      expect(SavedQueue.from(snap, const {}), isNull);
    });
  });
}
