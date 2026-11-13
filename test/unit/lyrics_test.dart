import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/lrc_parser.dart';
import 'package:nocturne/data/datasources/lrclib_source.dart';
import 'package:nocturne/data/datasources/lyrics_file_source.dart';
import 'package:nocturne/data/db/app_database.dart';
import 'package:nocturne/data/repositories/lyrics_repository_impl.dart';
import 'package:nocturne/domain/entities/audio_format.dart';
import 'package:nocturne/domain/entities/lyrics.dart';
import 'package:nocturne/domain/entities/track.dart';

class _File extends LyricsFileSource {
  const _File([this.lyrics]);
  final Lyrics? lyrics;
  @override
  Future<Lyrics?> read(String path) async => lyrics;
}

void main() {
  group('parseLrc', () {
    test('times, fractions, several times per line, sorted', () {
      final l = parseLrc('[00:10.4]b\n[00:05.40] a\n[01:02.345][00:20]chorus\n');
      expect(l.map((x) => x.text), ['a', 'b', 'chorus', 'chorus']);
      expect(l.map((x) => x.time.inMilliseconds), [5400, 10400, 20000, 62345]);
    });

    test('offset shifts lines earlier, tags are skipped', () {
      final l = parseLrc('[ar:Someone]\n[ti:Song]\n[offset:+500]\n[00:01.00]x\n[00:00.20]y');
      expect(l.map((x) => x.text), ['y', 'x']);
      expect(l.map((x) => x.time.inMilliseconds), [0, 500]);
    });

    test('plain text → no timed lines', () {
      expect(parseLrc('just words\nmore words'), isEmpty);
    });

    test('activeLyricLine: the last line that started', () {
      final l = parseLrc('[00:05]a\n[00:10]b\n[00:20]c');
      expect(activeLyricLine(l, const Duration(seconds: 2)), -1);
      expect(activeLyricLine(l, const Duration(seconds: 10)), 1);
      expect(activeLyricLine(l, const Duration(seconds: 15)), 1);
      expect(activeLyricLine(l, const Duration(minutes: 3)), 2);
    });
  });

  group('old .lrc files', () {
    test('UTF-8 is read as UTF-8', () {
      expect(LyricsFileSource.decodeLrc(Uint8List.fromList(utf8.encode('[00:01]Şəhər ğüöç'))), '[00:01]Şəhər ğüöç');
    });

    test('the Windows code page keeps the letters it has', () {
      // "Gönül şarkısı, ĞİŞ" and a typographic quote, in Windows-1254
      final bytes = [0x47, 0xF6, 0x6E, 0xFC, 0x6C, 0x20, 0xFE, 0x61, 0x72, 0x6B, 0xFD, 0x73, 0xFD, 0x2C, 0x20, 0xD0, 0xDD, 0xDE, 0x92];
      expect(LyricsFileSource.decodeLrc(Uint8List.fromList(bytes)), 'Gönül şarkısı, ĞİŞ’');
    });

    test('such a file is found and shown, it used to count as no file', () {
      final dir = Directory.systemTemp.createTempSync('nocturne_lrc');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/song.mp3').writeAsBytesSync(List.filled(16, 0));
      File('${dir.path}/song.lrc').writeAsBytesSync([...'[00:01.00]'.codeUnits, 0xFE, 0x61, 0x72, 0x6B, 0xFD]);
      expect(LyricsFileSource.readSync('${dir.path}/song.mp3')?.lines.single.text, 'şarkı');
    });
  });

  group('half a character in lyrics, which go to the screen without passing the database', () {
    const broken = [1, 0xFF, 0xFE, 0x41, 0x00, 0x3D, 0xD8, 0x42, 0x00, 0, 0];

    bool isClean(String s) => s.codeUnits.every((c) => c < 0xD800 || c > 0xDFFF);

    test('from a tag', () {
      final dir = Directory.systemTemp.createTempSync('nocturne_lrc');
      addTearDown(() => dir.deleteSync(recursive: true));
      // USLT: encoding, language, an empty description, then the text; here in ID3v2.4
      final data = [1, ...'eng'.codeUnits, 0xFF, 0xFE, 0, 0, ...broken.sublist(1)];
      final n = data.length;
      final frame = [...'USLT'.codeUnits, (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F, 0, 0, ...data];
      final s = frame.length;
      File('${dir.path}/song.mp3').writeAsBytesSync([
        ...'ID3'.codeUnits, 4, 0, 0, (s >> 21) & 0x7F, (s >> 14) & 0x7F, (s >> 7) & 0x7F, s & 0x7F,
        ...frame, ...List.filled(256, 0),
      ]);
      final lyrics = LyricsFileSource.readSync('${dir.path}/song.mp3');
      expect(lyrics?.plain, isNotNull);
      expect(isClean(lyrics!.plain!), isTrue);
    });

    test('from the server', () async {
      final source = LrclibSource(get: (_) async => (200, [
            {'duration': 180, 'plainLyrics': 'abc\uD83Ddef'},
          ]));
      final answer = await source.find(title: 't', artist: 'a', duration: const Duration(seconds: 180));
      expect((answer as LrclibFound).plain, 'abc�def');
    });
  });

  group('hostile lyrics', () {
    test('a line of endless time stamps takes linear time', () {
      final sw = Stopwatch()..start();
      final lines = parseLrc('${'[00:01]' * 200000}x');
      expect(lines, hasLength(200000));
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('spaces between stamps still work', () {
      final lines = parseLrc('[00:01] [00:02]  word');
      expect(lines.map((l) => l.text), ['word', 'word']);
      expect(lines.map((l) => l.time.inSeconds), [1, 2]);
    });

    test('a huge .lrc next to a song is not read', () {
      final dir = Directory.systemTemp.createTempSync('nocturne_lrc');
      addTearDown(() => dir.deleteSync(recursive: true));
      final song = '${dir.path}/song.mp3';

      File('${dir.path}/song.lrc').writeAsStringSync('[00:01]small');
      expect(LyricsFileSource.readSync(song)?.lines.single.text, 'small');

      File('${dir.path}/song.lrc').writeAsStringSync('[00:01]big\n' * 200000);
      expect(LyricsFileSource.readSync(song), isNull);
    });

    group('a response over the limit', () {
      Stream<List<int>> chunks(int count, {void Function()? onCancel}) {
        final c = StreamController<List<int>>(onCancel: onCancel);
        c.onListen = () async {
          for (var i = 0; i < count && !c.isClosed; i++) {
            c.add(List.filled(1024, 65));
            await Future<void>.delayed(Duration.zero);
          }
          await c.close();
        };
        return c.stream;
      }

      test('within the limit it arrives whole', () async {
        expect(await LrclibSource.readBounded(chunks(3), maxBytes: 4096), hasLength(3072));
      });

      test('is refused, and the download stops', () async {
        var stopped = false;
        await expectLater(
          LrclibSource.readBounded(chunks(1000000, onCancel: () => stopped = true), maxBytes: 4096),
          throwsFormatException,
        );
        expect(stopped, isTrue);
      });
    });
  });

  test('auto captions from video downloads are not lyrics', () {
    expect(LyricsFileSource.isAutoCaptions(['This is AI generated content', '[Music]', 'oh']), isTrue);
    expect(LyricsFileSource.isAutoCaptions(['[Music]', 'take', '[Applause]', 'foreign', 'up']), isTrue);
    expect(LyricsFileSource.isAutoCaptions(['Bir gün', '[Chorus]', 'gel bana', 'üç kalp', 'yine']), isFalse);
  });

  test('firstArtist keeps duos, drops collaborators', () {
    expect(LyricsRepositoryImpl.firstArtist('Paster x OD'), 'Paster');
    expect(LyricsRepositoryImpl.firstArtist('Artz × Bugy'), 'Artz');
    expect(LyricsRepositoryImpl.firstArtist('OGB feat. XXXPERT'), 'OGB');
    expect(LyricsRepositoryImpl.firstArtist('Simon & Garfunkel'), 'Simon & Garfunkel');
  });

  group('LyricsRepository', () {
    late AppDatabase db;
    late Track track;
    late List<Uri> calls;
    var now = DateTime(2026, 11, 3);
    // path → (status, body)
    late Map<String, (int, Object?)> server;

    LyricsRepositoryImpl repo([Lyrics? inFile]) => LyricsRepositoryImpl(
          db,
          files: _File(inFile),
          lrclib: LrclibSource(retryDelays: const [Duration.zero, Duration.zero], get: (uri) async {
            calls.add(uri);
            return server[uri.path] ?? (404, null);
          }),
          now: () => now,
        );

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      calls = [];
      server = {};
      now = DateTime(2026, 11, 3);
      final id = await db.into(db.tracks).insert(TracksCompanion.insert(
            path: '/x/a.mp3',
            title: 'Üç Kalp',
            artist: 'Hepsi',
            album: 'Hepsi Bir',
            format: 'mp3',
            durationMs: const Value(215000),
            dateAdded: 1,
            dateModified: 1,
          ));
      track = Track(
        id: id,
        path: '/x/a.mp3',
        title: 'Üç Kalp',
        artist: 'Hepsi',
        album: 'Hepsi Bir',
        duration: const Duration(milliseconds: 215000),
        format: AudioFormat.mp3,
      );
    });
    tearDown(() => db.close());

    test('lyrics in the file win, nothing is sent', () async {
      final r = await repo(const Lyrics(source: LyricsSource.file, plain: 'words'))
          .load(track, online: true, onlineSearch: true);
      expect(r.status, LyricsStatus.found);
      expect(r.lyrics!.source, LyricsSource.file);
      expect(calls, isEmpty);
    });

    test('offline / search off → says why, nothing is sent', () async {
      expect((await repo().load(track, online: false, onlineSearch: true)).status, LyricsStatus.needsOnline);
      expect((await repo().load(track, online: true, onlineSearch: false)).status, LyricsStatus.onlineSearchOff);
      expect(calls, isEmpty);
    });

    test('found on LRCLIB → saved, shown offline later', () async {
      server['/api/search'] = (200, [
        {'duration': 215.4, 'syncedLyrics': '[00:01.00]Bir\n[00:03.00]İki', 'plainLyrics': 'Bir\nİki'},
      ]);
      final r = await repo().load(track, online: true, onlineSearch: true);
      expect(r.lyrics!.synced, isTrue);
      // Only title and artist leave the phone
      expect(calls.single.queryParameters, {'track_name': 'Üç Kalp', 'artist_name': 'Hepsi'});

      final again = await repo().load(track, online: false, onlineSearch: true);
      expect(again.lyrics!.lines.map((l) => l.text), ['Bir', 'İki']);
      expect(calls, hasLength(1));
    });

    test('another version (different length) is not taken', () async {
      server['/api/search'] = (200, [
        {'duration': 260, 'syncedLyrics': '[00:01]remix'},
      ]);
      final r = await repo().load(track, online: true, onlineSearch: true);
      expect(r.status, LyricsStatus.notFound);
    });

    test('not found is remembered for a week; Search again asks anyway', () async {
      server['/api/search'] = (200, <Object>[]);
      await repo().load(track, online: true, onlineSearch: true);
      expect(calls, hasLength(1));
      await repo().load(track, online: true, onlineSearch: true);
      expect(calls, hasLength(1));
      await repo().load(track, online: true, onlineSearch: true, force: true);
      expect(calls, hasLength(2));
      now = now.add(const Duration(days: 8));
      await repo().load(track, online: true, onlineSearch: true);
      expect(calls, hasLength(3));
    });

    test('server busy → asked 3 times, then error, nothing saved', () async {
      server['/api/search'] = (503, null);
      expect((await repo().load(track, online: true, onlineSearch: true)).status, LyricsStatus.error);
      expect(calls, hasLength(3));
      // The song changed → no more retries
      calls.clear();
      await repo().load(track, online: true, onlineSearch: true, isCancelled: () => true);
      expect(calls, hasLength(1));
      expect(await db.select(db.trackLyrics).get(), isEmpty);
    });

    test('instrumental', () async {
      server['/api/search'] = (200, [
        {'duration': 215, 'instrumental': true},
      ]);
      final r = await repo().load(track, online: true, onlineSearch: true);
      expect(r.lyrics!.instrumental, isTrue);
    });
  });
}
