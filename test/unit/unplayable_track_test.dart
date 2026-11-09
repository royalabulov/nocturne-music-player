import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/features/library_scan/permission_gate.dart';
import 'package:nocturne/features/library_scan/unplayable_track.dart';

/// A song that won't play used to be marked missing whatever the reason, so with the
/// permission gone every song in the queue disappeared from the library.
void main() {
  Future<MediaPermission> granted() async => MediaPermission.granted;
  Future<MediaPermission> denied() async => MediaPermission.denied;
  Future<bool> there(String _) async => true;
  Future<bool> gone(String _) async => false;

  test('a file that is not on disk is missing', () async {
    expect(await whyUnplayable('/m/a.mp3', permission: granted, exists: gone), Unplayable.missing);
  });

  test('a file that is there but will not play is unreadable, not missing', () async {
    expect(await whyUnplayable('/m/a.ape', permission: granted, exists: there), Unplayable.unreadable);
  });

  test('without the permission nothing is called missing', () async {
    expect(await whyUnplayable('/m/a.mp3', permission: denied, exists: gone), Unplayable.noPermission);
  });

  test('a path that cannot be checked hides nothing', () async {
    expect(await whyUnplayable('content://x/1', permission: granted, exists: gone), Unplayable.unreadable);
    expect(
      await whyUnplayable('/m/a.mp3', permission: granted, exists: (_) async => throw Exception('io')),
      Unplayable.unreadable,
    );
    expect(
      await whyUnplayable('/m/a.mp3', permission: () async => throw Exception('plugin'), exists: gone),
      Unplayable.unreadable,
    );
  });
}
