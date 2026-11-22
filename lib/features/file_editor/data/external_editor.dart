import 'dart:async';
import 'dart:io';

import '../../../core/errors/app_error.dart';

/// A macOS editor application found on this machine.
final class ExternalAppCandidate {
  const ExternalAppCandidate({required this.name, required this.bundlePath});

  final String name;

  /// Absolute path of the `.app` bundle (what `open -a` receives
  /// when the user picks this candidate).
  final String bundlePath;
}

/// Well-known editors, by bundle name. TextEdit ships with macOS,
/// so at least one candidate exists on every machine.
const _knownBundles = <(String, String)>[
  ('Visual Studio Code', 'Visual Studio Code.app'),
  ('Cursor', 'Cursor.app'),
  ('Sublime Text', 'Sublime Text.app'),
  ('Zed', 'Zed.app'),
  ('BBEdit', 'BBEdit.app'),
  ('Nova', 'Nova.app'),
  ('TextEdit', 'TextEdit.app'),
];

/// Finds installed editors in the standard application folders.
List<ExternalAppCandidate> detectExternalApps() {
  final searchDirs = [
    '/Applications',
    '/System/Applications',
    '${Platform.environment['HOME'] ?? ''}/Applications',
  ];
  final found = <ExternalAppCandidate>[];
  final seen = <String>{};
  for (final (name, bundle) in _knownBundles) {
    if (seen.contains(name)) continue;
    for (final dir in searchDirs) {
      final path = '$dir/$bundle';
      if (Directory(path).existsSync()) {
        found.add(ExternalAppCandidate(name: name, bundlePath: path));
        seen.add(name);
        break;
      }
    }
  }
  return found;
}

/// OS interactions of the external-edit flow, behind an interface
/// so the sync logic is testable without launching real apps.
abstract interface class ExternalEditorRuntime {
  /// Opens [filePath] in the application named or pathed [app]
  /// (the `open -a` contract). Throws an [AppError] on failure.
  Future<void> launch(String app, String filePath);

  /// Watches a directory for changes (watching the directory —
  /// not the file — survives editors that save by atomic rename).
  Stream<FileSystemEvent> watchDirectory(String directoryPath);
}

final class ProcessExternalEditorRuntime implements ExternalEditorRuntime {
  const ProcessExternalEditorRuntime();

  @override
  Future<void> launch(String app, String filePath) async {
    try {
      final result = await Process.run('/usr/bin/open', ['-a', app, filePath]);
      if (result.exitCode != 0) {
        throw AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'Could not open the external editor ($app).',
          diagnostic: '${result.stderr}'.trim(),
        );
      }
    } on AppError {
      rethrow;
    } catch (e) {
      throw AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'Could not open the external editor ($app).',
        diagnostic: e.runtimeType.toString(),
      );
    }
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String directoryPath) =>
      Directory(directoryPath).watch();
}

/// Debounced, stability-checked change notification for one
/// externally edited file (Edit File spec §2.3): editors often
/// write in bursts or via rename, so a change is reported only
/// after the file has stayed byte-identical (size + mtime) across
/// a stability window following the last event.
final class LocalFileWatch {
  LocalFileWatch(
    this.file, {
    required this.onStableChange,
    this.debounce = const Duration(milliseconds: 700),
    this.stabilityWindow = const Duration(milliseconds: 350),
  });

  final File file;
  final void Function() onStableChange;
  final Duration debounce;
  final Duration stabilityWindow;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _timer;
  bool _disposed = false;

  void start(Stream<FileSystemEvent> events) {
    _subscription = events.listen((event) {
      if (event.path == file.path || event.path.endsWith('/$_basename')) {
        _schedule();
      }
    });
  }

  String get _basename => file.path.split('/').last;

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, _checkStable);
  }

  Future<void> _checkStable() async {
    try {
      final first = await file.stat();
      await Future<void>.delayed(stabilityWindow);
      if (_disposed) return;
      final second = await file.stat();
      if (first.size == second.size &&
          first.modified == second.modified &&
          second.type != FileSystemEntityType.notFound) {
        onStableChange();
      } else {
        _schedule();
      }
    } catch (_) {
      // The file vanished mid-save (rename dance): wait for the
      // next event instead of reporting a phantom change.
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
  }
}
