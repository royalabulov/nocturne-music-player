import 'app_runner.dart';
import 'demo/demo_audio.dart';
import 'demo/demo_overrides.dart';

/// The web preview: an in-memory library and synthesized sound instead of the phone's files.
/// `flutter build web -t lib/main_demo.dart`
Future<void> main() => runNocturne(sourceBuilder: DemoAudio.sourceFor, overrides: demoOverrides());
