import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/demo/demo_library.dart';
import 'package:sonar/core/demo/demo_overrides.dart';
import 'package:sonar/data/datasources/media_store_source.dart';
import 'package:sonar/data/services/library_scanner.dart';
import 'package:sonar/features/import/audio_import.dart';
import 'package:sonar/features/library_scan/permission_gate.dart';
import 'package:sonar/features/library_scan/scan_controller.dart';

/// Without native code: the test supplies the resolve/import answers itself.
class _FakeStore extends MediaStoreSource {
  _FakeStore(this.resolved, this.importsTo);
  final Map<String, ({String? path, String name, int size})> resolved;
  final Map<String, String> importsTo;
  final imported = <String>[];
  final scanned = <String>[];

  @override
  Future<({String? path, String name, int size})> resolveAudio(String source) async =>
      resolved[source] ?? (throw const ImportFailed('cannot open'));

  @override
  Future<String> importAudio(String source) async {
    imported.add(source);
    return importsTo[source] ?? (throw const ImportFailed('copy failed'));
  }

  @override
  Future<void> scanAndWait(List<String> paths) async => scanned.addAll(paths);
}

class _FakeScan extends ScanController {
  int scans = 0;

  @override
  ScanState build() => const ScanState(permission: MediaPermission.granted, progress: ScanProgress.idle);

  @override
  Future<void> requestAndScan() async => scans++;
}

void main() {
  final demo = DemoLibrary.tracks();
  late ProviderContainer c;
  late _FakeScan scan;

  setUp(() {
    scan = _FakeScan();
    c = ProviderContainer(overrides: [...demoOverrides(), scanControllerProvider.overrideWith(() => scan)]);
  });
  tearDown(() => c.dispose());

  test('file already in library → played as-is, nothing copied or scanned', () async {
    final known = demo[3];
    final store = _FakeStore({'content://x/1': (path: known.path, name: 'a.mp3', size: known.fileSize)}, {});
    final r = await AudioImport(c.read, store: store).ingest(['content://x/1']);
    expect(r.tracks.map((t) => t.id), [known.id]);
    expect(r.copied, 0);
    expect(store.imported, isEmpty);
    expect(scan.scans, 0);
  });

  test('Telegram-style URI (no path) → copied to Music/Sonar, scanned, found', () async {
    // The "copied" file lands at the path that is in the library after the scan
    final target = demo[5];
    final store = _FakeStore(
      {'content://telegram/9': (path: null, name: 'new song.mp3', size: 1)},
      {'content://telegram/9': target.path},
    );
    final r = await AudioImport(c.read, store: store).ingest(['content://telegram/9']);
    expect(store.imported, ['content://telegram/9']);
    expect(store.scanned, [target.path]);
    expect(scan.scans, greaterThanOrEqualTo(1));
    expect(r.copied, 1);
    expect(r.tracks.single.id, target.id);
  });

  test('order is kept and failures are counted', () async {
    final a = demo[1], b = demo[2];
    final store = _FakeStore({
      'u:a': (path: a.path, name: 'a', size: a.fileSize),
      'u:bad': (path: null, name: 'bad.mp3', size: 0), // import fails
      'u:b': (path: b.path, name: 'b', size: b.fileSize),
    }, {});
    final r = await AudioImport(c.read, store: store).ingest(['u:a', 'u:bad', 'u:b', 'u:unknown']);
    expect(r.tracks.map((t) => t.id), [a.id, b.id]);
    expect(r.failed, 2);
  });
}
