import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../build_info.dart';

/// Opt-in terminal input diagnostics (ADR-015).
///
/// Off by default and completely inert until the user turns it on
/// (⌘⇧L in the app). While on, input-path events — platform
/// editing-value updates, what the terminal emits toward the
/// shell, what the shell sends back, and resize events — are
/// appended to `heroterm-input-log.txt` in the application
/// support directory so a typing-corruption report can be
/// diagnosed from the actual event stream instead of guesswork.
///
/// The log contains everything typed in the terminal while it is
/// on (commands and their output). It never leaves the machine
/// unless the user sends the file, and the start banner in the
/// file itself warns against typing passwords while recording.
final class InputDebugLog {
  InputDebugLog._();

  static bool enabled = false;

  static File? _file;
  static Future<void> _tail = Future.value();
  static final Stopwatch _clock = Stopwatch()..start();

  static Future<String> filePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/heroterm-input-log.txt';
  }

  static Future<void> setEnabled(bool on) async {
    enabled = on;
    if (!on) return;
    _file = File(await filePath());
    log(
      '=== input log started ${DateTime.now().toIso8601String()} — '
      'build $buildId on ${Platform.operatingSystem} — '
      'WARNING: everything typed in the terminal is recorded; '
      'do not type passwords while this is on ===',
    );
  }

  static void log(String line) {
    if (!enabled) return;
    final file = _file;
    if (file == null) return;
    final stamped = '[${_clock.elapsedMilliseconds}ms] $line\n';
    // Serialize appends so concurrent events cannot interleave.
    _tail = _tail.then(
      (_) => file.writeAsString(stamped, mode: FileMode.append),
    );
    _tail = _tail.catchError((_) {});
  }
}
