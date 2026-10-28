import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/data/datasources/tag_reader.dart';

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

/// UTF-16 big-endian with a doubled BOM, like Snaptube writes.
List<int> _doubleBom(String s) => [
      1, 0xFE, 0xFF, 0xFE, 0xFF,
      for (final u in s.codeUnits) ...[u >> 8, u & 0xFF],
      0, 0,
    ];

void main() {
  test('Snaptube double-BOM title keeps Ü (was "?ç Kalp")', () {
    // Faylda olan baytlar: 01 FE FF FE FF 00 DC 00 E7 00 20 ...
    final tag = _id3({'TIT2': _doubleBom('Üç Kalp'), 'TPE1': _doubleBom('Hepsi'), 'TALB': _doubleBom('Hepsi Bir')});
    expect(TagReader.parseId3TextFrames(tag), {'TIT2': 'Üç Kalp', 'TPE1': 'Hepsi', 'TALB': 'Hepsi Bir'});
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
    final dir = Directory.systemTemp.createTempSync('sonar_tag');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/kalp.mp3')
      ..writeAsBytesSync([..._id3({'TIT2': _doubleBom('Üç Kalp'), 'TPE1': _doubleBom('Hepsi')}), ...List.filled(2048, 0)]);
    final tag = TagReader.read(file.path)!;
    expect(tag.title, 'Üç Kalp');
    expect(tag.artist, 'Hepsi');
  });

  group('guessArtist', () {
    ({String title, String? artist}) g(String t, [String? a]) => TagReader.guessArtist(t, a);

    test('splits "Artist - Title" when the artist is unknown', () {
      expect(g('2PAC - Only Fear of Death'), (title: 'Only Fear of Death', artist: '2PAC'));
      expect(g('Mareux - The Perfect Girl', 'Unknown Artist'), (title: 'The Perfect Girl', artist: 'Mareux'));
      expect(g('Hepsi – Üç Kalp', '<unknown>'), (title: 'Üç Kalp', artist: 'Hepsi'));
    });

    test('drops a leading track number and YouTube noise', () {
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

  test('stripTopic cleans YouTube auto-channel album names', () {
    expect(TagReader.stripTopic('Michael Tai - Topic'), 'Michael Tai');
    expect(TagReader.stripTopic('Hepsi Bir'), 'Hepsi Bir');
    expect(TagReader.stripTopic(null), isNull);
  });
}
