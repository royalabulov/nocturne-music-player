// ignore_for_file: experimental_member_use, close_sinks (each test closes its session)
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocturne/core/audio/output_detector.dart';

/// Only what the detector uses; everything else isn't called.
class _Session implements AudioSession {
  final changes = StreamController<AudioDevicesChangedEvent>.broadcast();
  Set<AudioDevice> devices = {};

  @override
  Stream<AudioDevicesChangedEvent> get devicesChangedEventStream => changes.stream;

  @override
  Future<Set<AudioDevice>> getDevices({bool includeInputs = true, bool includeOutputs = true}) async => devices;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AudioDevice _device(AudioDeviceType type) =>
    AudioDevice(id: '$type', name: '$type', isInput: false, isOutput: true, type: type);

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('follows headphones being plugged in', () async {
    final session = _Session();
    final d = OutputDetector(session: () async => session);
    addTearDown(d.dispose);
    addTearDown(session.changes.close);
    await settle();
    expect(d.current, OutputKind.speaker);

    session.devices = {_device(AudioDeviceType.wiredHeadphones)};
    session.changes.add(AudioDevicesChangedEvent());
    await settle();
    expect(d.current, OutputKind.headphones);
  });

  // The listener used to outlive the detector and add to its closed stream on every plug-in
  test('once disposed it stops listening to the devices', () async {
    final session = _Session();
    final d = OutputDetector(session: () async => session);
    addTearDown(session.changes.close);
    await settle();
    expect(session.changes.hasListener, isTrue);

    d.dispose();
    await settle();
    expect(session.changes.hasListener, isFalse);
  });
}
