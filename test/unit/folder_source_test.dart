import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/data/datasources/folder_source.dart';
import 'package:path/path.dart' as p;

/// A .nomedia file means "keep this folder away from media apps": voice messages, private
/// recordings. MediaStore respects it, and the folder walk has to as well, except for a folder
/// the scan list names: that one was chosen.
void main() {
  late Directory root;

  File song(String path) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsBytesSync([1, 2, 3]);

  void noMedia(String folder, {String name = '.nomedia'}) =>
      File(p.join(root.path, folder, name)).createSync(recursive: true);

  Future<List<String>> found([String? folder, String? another]) async {
    final walked = await FolderSource().walk([folder ?? root.path, ?another]);
    return [for (final r in walked) p.relative(r.path, from: root.path).replaceAll(r'\', '/')]..sort();
  }

  setUp(() => root = Directory.systemTemp.createTempSync('nocturne_folders'));
  tearDown(() => root.deleteSync(recursive: true));

  test('without .nomedia every song is found, in every folder', () async {
    song('a.mp3');
    song('Album/b.flac');
    song('Album/Disc 2/c.m4a');
    expect(await found(), ['Album/Disc 2/c.m4a', 'Album/b.flac', 'a.mp3']);
  });

  test('a folder with .nomedia stays out, its subfolders too', () async {
    song('Voice/note.mp3');
    song('Voice/2026/note2.mp3');
    noMedia('Voice');
    song('Music/song.mp3');
    expect(await found(), ['Music/song.mp3']);
  });

  test('the neighbouring folders are not affected', () async {
    song('Voice Notes/a.mp3');
    noMedia('Voice Notes');
    song('Voice/b.mp3');
    expect(await found(), ['Voice/b.mp3']);
  });

  test('whatever order the walk finds them in', () async {
    noMedia('z');
    song('z/a/a/a.mp3');
    song('z/z/z/z.mp3');
    expect(await found(), isEmpty);
  });

  test('capital letters count', () async {
    song('Voice/note.mp3');
    noMedia('Voice', name: '.NOMEDIA');
    expect(await found(), isEmpty);
  });

  group('a folder on the scan list was chosen', () {
    test('its own .nomedia does not hide it', () async {
      song('a.mp3');
      song('Sub/b.mp3');
      noMedia('');
      expect(await found(), ['Sub/b.mp3', 'a.mp3']);
    });

    test('nor does one above it', () async {
      song('Private/Songs/a.mp3');
      noMedia('Private');
      expect(await found(p.join(root.path, 'Private', 'Songs')), ['Private/Songs/a.mp3']);
    });

    test('a hidden subfolder inside it stays hidden', () async {
      song('a.mp3');
      noMedia('');
      song('Voice/note.mp3');
      noMedia('Voice');
      expect(await found(), ['a.mp3']);
    });

    test('naming a hidden subfolder too brings it in, without opening the rest', () async {
      song('a.mp3');
      song('Voice/note.mp3');
      noMedia('Voice');
      song('Other/secret.mp3');
      noMedia('Other');
      expect(await found(root.path, p.join(root.path, 'Voice')), ['Voice/note.mp3', 'a.mp3']);
    });

    test('a path written with a slash at the end is the same folder', () async {
      song('a.mp3');
      noMedia('');
      expect(await found('${root.path}${p.separator}'), ['a.mp3']);
    });
  });

  // Scoped storage shuts some folders (Android/data); a single recursive listing stopped
  // there and every song after it was left out.
  test('a folder that cannot be read is skipped, the walk goes on', () async {
    song('A/a.mp3');
    song('Locked/x.mp3');
    song('Z/z.mp3');
    song('Z/Deeper/d.mp3');
    final locked = p.join(root.path, 'Locked');
    Stream<FileSystemEntity> list(Directory d) => p.equals(d.path, locked)
        ? Stream.error(FileSystemException('Permission denied', d.path))
        : d.list(followLinks: false);

    final walked = await FolderSource(list: list).walk([root.path]);

    expect(
      [for (final r in walked) p.relative(r.path, from: root.path).replaceAll(r'\', '/')]..sort(),
      ['A/a.mp3', 'Z/Deeper/d.mp3', 'Z/z.mp3'],
    );
  });

  test('a folder that does not exist is nothing', () async {
    expect(await found(p.join(root.path, 'missing')), isEmpty);
  });
}
