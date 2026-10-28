// ignore_for_file: experimental_member_use
import 'package:audio_session/audio_session.dart';
import 'package:rxdart/rxdart.dart';

/// Output type. Auto EQ preset + the Settings "Output" row.
enum OutputKind {
  headphones('Wired headphones', 'WIRED'),
  bluetooth('Bluetooth', 'BT'),
  speaker('Phone speaker', 'SPEAKER');

  const OutputKind(this.label, this.chip);
  final String label;
  final String chip;
}

class OutputDetector {
  OutputDetector() {
    _init();
  }

  final _kind = BehaviorSubject<OutputKind>.seeded(OutputKind.speaker);
  Stream<OutputKind> get stream => _kind.stream.distinct();
  OutputKind get current => _kind.value;

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      await _refresh(session);
      session.devicesChangedEventStream.listen((_) => _refresh(session));
    } catch (_) {
      // Web / unsupported platform → treated as speaker
    }
  }

  Future<void> _refresh(AudioSession session) async {
    try {
      final devices = await session.getDevices(includeInputs: false);
      _kind.add(_classify(devices));
    } catch (_) {
      // Some devices give no list — treated as speaker
    }
  }

  static OutputKind _classify(Set<AudioDevice> devices) {
    final types = devices.map((d) => d.type).toSet();
    const bt = {AudioDeviceType.bluetoothA2dp, AudioDeviceType.bluetoothLe, AudioDeviceType.hearingAid};
    const wired = {
      AudioDeviceType.wiredHeadset,
      AudioDeviceType.wiredHeadphones,
      AudioDeviceType.usbAudio,
      AudioDeviceType.lineAnalog,
      AudioDeviceType.lineDigital,
    };
    // If Bluetooth is connected, audio usually goes there; then wired; then the speaker
    if (types.any(bt.contains)) return OutputKind.bluetooth;
    if (types.any(wired.contains)) return OutputKind.headphones;
    return OutputKind.speaker;
  }

  void dispose() => _kind.close();
}
