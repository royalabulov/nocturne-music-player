import 'dart:async';
import 'dart:isolate';

/// The isolate ended without an answer: it threw, or it was killed (out of memory).
class IsolateFailed implements Exception {
  const IsolateFailed(this.reason);
  final String reason;

  @override
  String toString() => 'IsolateFailed: $reason';
}

/// Runs [work] in its own isolate, for work on data we don't control (parsing other people's
/// files). Unlike [Isolate.run] it can stop: past [timeout] the isolate is killed and this
/// throws [TimeoutException].
///
/// [work] is sent to the isolate, so like with [Isolate.run] it can only capture sendable
/// values, and so must be what it returns.
Future<R> runBounded<R>(R Function() work, {required Duration timeout}) async {
  final done = Completer<R>();
  final port = RawReceivePort();
  port.handler = (Object? message) {
    if (done.isCompleted) return;
    switch (message) {
      case _Result(:final value):
        done.complete(value as R);
      case [final Object? error, final Object? _]: // onError: [error, stack]
        done.completeError(IsolateFailed('$error'));
      default: // onExit: null, it ended without sending a result
        done.completeError(const IsolateFailed('ended without a result'));
    }
  };

  Isolate? isolate;
  final timer = Timer(timeout, () {
    if (done.isCompleted) return;
    isolate?.kill(priority: Isolate.immediate);
    done.completeError(TimeoutException('isolate killed', timeout));
  });
  try {
    isolate = await Isolate.spawn(
      _entry,
      (port.sendPort, work),
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    return await done.future;
  } finally {
    timer.cancel();
    port.close();
  }
}

class _Result {
  const _Result(this.value);
  final Object? value;
}

void _entry((SendPort, Object? Function()) args) {
  final (port, work) = args;
  // exit: the result moves over without being copied
  Isolate.exit(port, _Result(work()));
}
