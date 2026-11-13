import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/cover_cache.dart';
import 'package:nocturne/data/datasources/tag_reader.dart';

/// ID3v2.4 tag: the given frames + header.
Uint8List _id3(Map<String, List<int>> frames) {
  final body = <int>[];
  for (final e in frames.entries) {
    final n = e.value.length;
    body
      ..addAll(e.key.codeUnits)
      ..addAll([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F, 0, 0])
      ..addAll(e.value);
  }
  final n = body.length;
  return Uint8List.fromList([
    ...'ID3'.codeUnits, 4, 0, 0,
    (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F,
    ...body,
  ]);
}

/// UTF-16 big-endian with a doubled BOM, like some downloaders write.
List<int> _doubleBom(String s) => [
      1, 0xFE, 0xFF, 0xFE, 0xFF,
      for (final u in s.codeUnits) ...[u >> 8, u & 0xFF],
      0, 0,
    ];

void main() {
  test('double-BOM title keeps Ü (was "?ç Kalp")', () {
    // The bytes in the file: 01 FE FF FE FF 00 DC 00 E7 00 20 ...
    final tag = _id3({'TIT2': _doubleBom('Üç Kalp'), 'TPE1': _doubleBom('Hepsi'), 'TALB': _doubleBom('Hepsi Bir')});
    expect(TagReader.parseId3TextFrames(tag), {'TIT2': 'Üç Kalp', 'TPE1': 'Hepsi', 'TALB': 'Hepsi Bir'});
  });

  test('double-BOM lyrics (USLT) keep their letters and line breaks', () {
    // encoding 1, language "tur", empty description (BOMs + NUL), then the words
    final uslt = [
      1, ...'tur'.codeUnits, 0xFE, 0xFF, 0xFE, 0xFF, 0, 0,
      ..._doubleBom('Üç kalp\nbir şarkı').skip(1),
    ];
    final tag = _id3({'TIT2': _doubleBom('Üç Kalp'), 'USLT': uslt});
    expect(TagReader.parseId3Lyrics(tag), 'Üç kalp\nbir şarkı');
    expect(TagReader.parseId3Lyrics(_id3({'TIT2': _doubleBom('x')})), isNull);
  });

  test('other letters that used to break: Ø ß Ý', () {
    final tag = _id3({'TIT2': _doubleBom('Øresund ßÝ')});
    expect(TagReader.parseId3TextFrames(tag)['TIT2'], 'Øresund ßÝ');
  });

  test('UTF-8, Latin-1 and little-endian UTF-16 frames', () {
    final tag = _id3({
      'TIT2': [3, ...utf8.encode('Gecə')],
      'TPE1': [0, ...'Müslüm'.codeUnits],
      'TALB': [1, 0xFF, 0xFE, for (final u in 'Şəki'.codeUnits) ...[u & 0xFF, u >> 8]],
    });
    expect(TagReader.parseId3TextFrames(tag), {'TIT2': 'Gecə', 'TPE1': 'Müslüm', 'TALB': 'Şəki'});
  });

  test('non-ID3 data gives nothing', () {
    expect(TagReader.parseId3TextFrames(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])), isEmpty);
  });

  test('read() repairs the title end-to-end from a real file', () {
    // audio_metadata_reader returns "\uFFFE\uFFFE\uFFFDç Kalp" here
    final dir = Directory.systemTemp.createTempSync('nocturne_tag');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/kalp.mp3')
      ..writeAsBytesSync([..._id3({'TIT2': _doubleBom('Üç Kalp'), 'TPE1': _doubleBom('Hepsi')}), ...List.filled(2048, 0)]);
    final tag = TagReader.read(file.path)!;
    expect(tag.title, 'Üç Kalp');
    expect(tag.artist, 'Hepsi');
  });

  group('tags are other people\'s data', () {
    TagInfo readFile(Map<String, List<int>> frames) {
      final dir = Directory.systemTemp.createTempSync('nocturne_tag');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/song.mp3')..writeAsBytesSync([..._id3(frames), ...List.filled(2048, 0)]);
      return TagReader.read(file.path)!;
    }

    List<int> text(String s) => [3, ...utf8.encode(s)];

    /// A JPEG of side × side as far as its header goes, [size] bytes in all.
    List<int> jpeg(int size, int side) => [0xFF, 0xD8, 0xFF, 0xC0, 0, 17, 8, side >> 8, side & 255, side >> 8, side & 255, ...List.filled(size - 11, 7)];

    /// APIC: encoding, MIME type, picture type (3 = front cover), empty description, image.
    List<int> picture(List<int> image) => [0, ...'image/jpeg'.codeUnits, 0, 3, 0, ...image];
    List<int> cover(int size, {int side = 500}) => picture(jpeg(size, side));

    test('control characters can\'t reach the UI or the notification', () {
      final tag = readFile({'TIT2': text('Bad\u0007Title'), 'TPE1': text('Ar\ntist'), 'TALB': text('Al\u001Bbum')});
      expect(tag.title, 'Bad Title');
      expect(tag.artist, 'Ar tist');
      expect(tag.album, 'Al bum');
    });

    test('an absurdly long tag is cut', () {
      final long = 'x' * 100000;
      final tag = readFile({'TIT2': text(long), 'TPE1': text(long), 'TALB': text(long), 'TCON': text(long)});
      expect(tag.title.length, TagReader.maxTextChars);
      expect(tag.artist.length, TagReader.maxTextChars);
      expect(tag.album.length, TagReader.maxTextChars);
      expect(tag.genre!.length, TagReader.maxTextChars);
    });

    test('a cut never lands between the two halves of an emoji', () {
      final tag = readFile({'TIT2': text('${'x' * (TagReader.maxTextChars - 1)}😀tail')});
      expect(tag.title, 'x' * (TagReader.maxTextChars - 1));
    });

    test('an emoji that fits stays whole', () {
      final tag = readFile({'TIT2': text('${'x' * (TagReader.maxTextChars - 2)}😀tail')});
      expect(tag.title, '${'x' * (TagReader.maxTextChars - 2)}😀');
    });

    test('half a character in a corrupt tag does not reach the screen', () {
      // UTF-16 with a first half and no second half, read through our own fallback too
      final broken = [1, 0xFF, 0xFE, 0x41, 0x00, 0x3D, 0xD8, 0x42, 0x00];
      final tag = readFile({'TIT2': broken});
      expect(tag.title.codeUnits.where((c) => c >= 0xD800 && c <= 0xDFFF), isEmpty);
    });

    test('normal tags are untouched', () {
      final tag = readFile({'TIT2': text('Üç Kalp - Canlı'), 'TPE1': text('Müslüm & Şəki'), 'TCON': text('Rock')});
      expect(tag.title, 'Üç Kalp - Canlı');
      expect(tag.artist, 'Müslüm & Şəki');
      expect(tag.genre, 'Rock');
    });

    test('readMany brings tags and cover back from its isolate; a missing file is null', () async {
      final dir = Directory.systemTemp.createTempSync('nocturne_tag');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/song.mp3')
        ..writeAsBytesSync([..._id3({'TIT2': text('Song'), 'APIC': cover(100)}), ...List.filled(2048, 0)]);
      final missing = '${dir.path}/missing.mp3';

      final tags = await TagReader.readMany([file.path, missing]);

      expect(tags[file.path]!.title, 'Song');
      expect(tags[file.path]!.cover, hasLength(100));
      expect(tags[missing], isNull);
    });

    // Hashing a few MB of cover on the UI isolate stuttered the first scan
    test('the cover\'s cache name is worked out with the tags, off the UI isolate', () {
      final tags = readFile({'TIT2': text('a'), 'APIC': cover(1000)});
      expect(tags.coverHash, coverHashOf(tags.cover!));
      expect(readFile({'TIT2': text('a')}).coverHash, isNull);
    });

    test('a normal cover is kept, an absurdly big one is dropped', () {
      expect(readFile({'TIT2': text('a'), 'APIC': cover(1000)}).cover, hasLength(1000));
      final tooBig = readFile({'TIT2': text('a'), 'APIC': cover(TagReader.maxCoverBytes + 1)});
      expect(tooBig.title, 'a');
      expect(tooBig.cover, isNull);
    });

    test('a small file holding an enormous picture is dropped: decoding it would fill the memory', () {
      final bomb = readFile({'TIT2': text('a'), 'APIC': cover(1000, side: 30000)});
      expect(bomb.title, 'a');
      expect(bomb.cover, isNull);
    });

    test('a large cover that is still a reasonable size is kept', () {
      expect(readFile({'TIT2': text('a'), 'APIC': cover(1000, side: 4000)}).cover, hasLength(1000));
    });

    test('something that is no image at all is dropped', () {
      expect(readFile({'TIT2': text('a'), 'APIC': picture(List.filled(1000, 7))}).cover, isNull);
    });
  });

  group('guessArtist', () {
    ({String title, String? artist}) g(String t, [String? a]) => TagReader.guessArtist(t, a);

    test('splits "Artist - Title" when the artist is unknown', () {
      expect(g('2PAC - Only Fear of Death'), (title: 'Only Fear of Death', artist: '2PAC'));
      expect(g('Mareux - The Perfect Girl', 'Unknown Artist'), (title: 'The Perfect Girl', artist: 'Mareux'));
      expect(g('Hepsi – Üç Kalp', '<unknown>'), (title: 'Üç Kalp', artist: 'Hepsi'));
    });

    test('drops a leading track number and video-download noise', () {
      expect(g('01 - Ice Cube - Hello'), (title: 'Hello', artist: 'Ice Cube'));
      expect(g('Mareux - The Perfect Girl(MP3_320K)'), (title: 'The Perfect Girl', artist: 'Mareux'));
      expect(g('Xpert - Möhkəm (Official Video)'), (title: 'Möhkəm', artist: 'Xpert'));
    });

    test('keeps a real artist, only cleans "- Topic"', () {
      expect(g('MOTIVE - PVG', 'Motive'), (title: 'MOTIVE - PVG', artist: 'Motive'));
      expect(g('Dünyaya Bedel', 'mor ve ötesi - Topic'), (title: 'Dünyaya Bedel', artist: 'mor ve ötesi'));
    });

    test('quoted left side is a song title, not an artist', () {
      const d = '"Dumbledore\'s Farewell" - Harry Potter and the Half-Blood Prince';
      expect(g(d), (title: d, artist: null));
      const s = "'Signal to Noise' [Cinematic] - Scott Buckley";
      expect(g(s), (title: s, artist: null));
    });

    test('zero-padded track number without a dash is dropped, real names stay', () {
      expect(g('01 Alles Ist Miteinander Verbunden - Ark Of Garuda'),
          (title: 'Ark Of Garuda', artist: 'Alles Ist Miteinander Verbunden'));
      expect(g('5 Qarish - Gecə'), (title: 'Gecə', artist: '5 Qarish'));
      expect(g('140 Vibes - Run'), (title: 'Run', artist: '140 Vibes'));
    });

    test('leaves titles without a separator alone', () {
      expect(g('Piyanist'), (title: 'Piyanist', artist: null));
      expect(g('Vals-Kantata'), (title: 'Vals-Kantata', artist: null));
      expect(g('01 - Intro'), (title: '01 - Intro', artist: null));
    });
  });


  group('findUploaders', () {
    // Real artist/title pairs from the phone (video downloads)
    Set<String> f(List<(String, String)> l) =>
        TagReader.findUploaders([for (final (a, t) in l) (artist: a, title: t)]);

    test('label and channel names are found', () {
      expect(f([
        ('Synaps Records', 'Paster — Bane'),
        ('Synaps Records', 'RIO — Təkərlər (Official Music Video)'),
        ('140 Vibes', "F'Rhyme — Absurd (Official Audio)"),
        ('140 Vibes', "F'Rhyme ft. Uran — Dal Parta (Official Audio)"),
        ('140 Vibes', 'kimsə bizi izləyir'),
        ('101 Moon Ave.', 'Xpert — DƏMLƏR'),
        ('101 Moon Ave.', 'Xpert — MÖHKEM (Official Music Video)'),
        ('EminemVEVO', 'Eminem - Mockingbird [Official Music Video]'),
      ]), {'synaps records', '140 vibes', '101 moon ave.', 'eminemvevo'});
    });

    test('real artists and sentences are left alone', () {
      expect(f([
        ('Ezhel', 'Ezhel & Murda - Made in Turkey'),
        ('Ezhel', 'Felaket'),
        ('Turkish Sound Effects', 'Merhaba Hanımefendi Hiç Basmış Mıydım Size - Deep Turkish Web - Ses Efekti'),
        ('Turkish Sound Effects', 'Merhaba Hanımefendi Hiç Basmış Mıydım Size - Deep Turkish Web - Ses Efekti'),
        ('Original Soundtrack', 'Longing (Redemptions) | The Last of Us Part II OST'),
        ('Some Band', 'Song One - Remastered 2011'),
        ('Some Band', 'Song Two - Remastered 2011'),
        ('Unknown Artist', 'Paster — Bane'),
        // the same song saved 3 times is not "one name repeating"
        ('Tame Impala', 'Let It Happen - Radio Edit'),
        ('Tame Impala', 'Let It Happen - Radio Edit'),
        ('Tame Impala', 'Let It Happen - Radio Edit'),
      ]), isEmpty);
    });

    test('isNameLike', () {
      expect(TagReader.isNameLike('PASTER × RIO × F\'RHYME × RZZA'), isTrue);
      expect(TagReader.isNameLike('F\'Rhyme x Nijat Mammadli'), isTrue);
      expect(TagReader.isNameLike('Kardeşim Arkadan Vurdun Mu Önden Sallanacak'), isFalse);
    });
  });

  test('stripTopic cleans auto-channel album names', () {
    expect(TagReader.stripTopic('Michael Tai - Topic'), 'Michael Tai');
    expect(TagReader.stripTopic('Hepsi Bir'), 'Hepsi Bir');
    expect(TagReader.stripTopic(null), isNull);
  });
}
