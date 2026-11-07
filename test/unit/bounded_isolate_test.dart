import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonar/core/utils/bounded_isolate.dart';

int _forever() {
  var i = 0;
  while (true) {
    i++;
    if (i < 0) return i;
  }
}

Never _throws() => throw StateError('corrupt file');

int _diesSilently() {
  Isolate.current.kill(priority: Isolate.immediate);
  return _forever();
}

void main() {
  const plenty = Duration(seconds: 20);

  test('returns the result, of any sendable type', () async {
    final paths = ['a', 'b'];
    final result = await runBounded(() => {for (final p in paths) p: p.length}, timeout: plenty);
    expect(result, {'a': 1, 'b': 1});
  });

  test('null is a result too', () async {
    expect(await runBounded<int?>(() => null, timeout: plenty), isNull);
  });

  test('work that never ends is killed and reported', () async {
    final sw = Stopwatch()..start();
    await expectLater(
      runBounded(_forever, timeout: const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('work that throws is reported', () async {
    await expectLater(
      runBounded(_throws, timeout: plenty),
      throwsA(isA<IsolateFailed>().having((e) => e.reason, 'reason', contains('corrupt file'))),
    );
  });

  test('an isolate that dies without an answer is reported, not waited for', () async {
    await expectLater(runBounded(_diesSilently, timeout: plenty), throwsA(isA<IsolateFailed>()));
  });
}
