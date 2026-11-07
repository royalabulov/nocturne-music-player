import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/audio_analyzer_source.dart';
import 'package:nocturne/data/datasources/media_store_source.dart';

/// Native failures arrive as PlatformException. Callers only know the app's own exceptions, and
/// a result is never read for "error:" text, so a file named like that can't look like a failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const media = MethodChannel('com.nocturne/media_store');
  const analysis = MethodChannel('com.nocturne/audio_analysis');

  void answer(MethodChannel channel, Object? Function(MethodCall) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async => reply(call));
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  Never fails(MethodCall _) => throw PlatformException(code: 'failed', message: 'IOException: disk full');

  group('import', () {
    test('a failed copy is ImportFailed, with the reason', () {
      answer(media, fails);
      expect(
        MediaStoreSource().importAudio('content://x'),
        throwsA(isA<ImportFailed>().having((e) => e.reason, 'reason', 'IOException: disk full')),
      );
    });

    test('a failed lookup is ImportFailed', () {
      answer(media, fails);
      expect(MediaStoreSource().resolveAudio('content://x'), throwsA(isA<ImportFailed>()));
    });

    test('no answer at all is ImportFailed, not a crash on null', () {
      answer(media, (_) => null);
      expect(MediaStoreSource().importAudio('content://x'), throwsA(isA<ImportFailed>()));
    });

    test('a path is returned as it is, whatever it looks like', () async {
      answer(media, (_) => '/storage/emulated/0/Music/Nocturne/error: live.mp3');
      expect(await MediaStoreSource().importAudio('content://x'), '/storage/emulated/0/Music/Nocturne/error: live.mp3');
    });

    test('a found file comes back with its details', () async {
      answer(media, (_) => {'path': null, 'name': 'a.mp3', 'size': 5});
      final info = await MediaStoreSource().resolveAudio('content://x');
      expect((info.path, info.name, info.size), (null, 'a.mp3', 5));
    });
  });

  group('analysis', () {
    test('it has its own channel', () async {
      answer(analysis, (call) {
        expect(call.method, 'analyzeAudio');
        expect(call.arguments, {'path': '/a.mp3', 'durationMs': 9});
        return {'scores': {'Music': 1}, 'rmsDb': -14.0};
      });
      final r = await AudioAnalyzerSource().analyze('/a.mp3', 9);
      expect(r.scores, {'Music': 1.0});
      expect(r.rmsDb, -14);
      expect(r.segments, isEmpty);
    });

    test('a failure is AudioAnalysisException, so the song is marked and not retried forever', () {
      answer(analysis, fails);
      expect(AudioAnalyzerSource().analyze('/a.mp3', 9), throwsA(isA<AudioAnalysisException>()));
    });
  });
}
