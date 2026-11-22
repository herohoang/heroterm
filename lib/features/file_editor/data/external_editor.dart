import 'dart:async';
import 'dart:io';

import '../../../core/errors/app_error.dart';

/// An editor application found on this machine.
final class ExternalAppCandidate {
  const ExternalAppCandidate({required this.name, required this.bundlePath});

  final String name;

  /// Absolute path of the application: the `.app` bundle on
  /// macOS (what `open -a` receives), the executable on Windows.
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

/// Well-known Windows editors, as candidate executable paths in
/// preference order (per-user installs before machine installs).
List<(String, List<String>)> get _knownWindowsApps {
  final env = Platform.environment;
  final localAppData = env['LOCALAPPDATA'] ?? '';
  final programFiles = env['ProgramFiles'] ?? r'C:\Program Files';
  final programFilesX86 = env['ProgramFiles(x86)'] ?? '';
  final systemRoot = env['SystemRoot'] ?? r'C:\Windows';
  return [
    (
      'Visual Studio Code',
      [
        '$localAppData\\Programs\\Microsoft VS Code\\Code.exe',
        '$programFiles\\Microsoft VS Code\\Code.exe',
        '$programFilesX86\\Microsoft VS Code\\Code.exe',
      ],
    ),
    (
      'Cursor',
      [
        '$localAppData\\Programs\\Cursor\\Cursor.exe',
        '$programFiles\\Cursor\\Cursor.exe',
      ],
    ),
    ('Sublime Text', ['$programFiles\\Sublime Text\\sublime_text.exe']),
    (
      'Notepad++',
      [
        '$programFiles\\Notepad++\\notepad++.exe',
        '$programFilesX86\\Notepad++\\notepad++.exe',
      ],
    ),
    ('Zed', ['$localAppData\\Programs\\Zed\\Zed.exe']),
    // Ships with Windows, so at least one candidate exists on
    // every machine (the TextEdit equivalent).
    ('Notepad', ['$systemRoot\\System32\\notepad.exe']),
  ];
}

/// Finds installed editors in the standard application folders
/// (macOS) or install locations (Windows). Empty elsewhere.
List<ExternalAppCandidate> detectExternalApps() {
  final found = <ExternalAppCandidate>[];
  if (Platform.isWindows) {
    for (final (name, candidates) in _knownWindowsApps) {
      for (final path in candidates) {
        if (path.length > 3 && File(path).existsSync()) {
          found.add(ExternalAppCandidate(name: name, bundlePath: path));
          break;
        }
      }
    }
    return found;
  }
  if (!Platform.isMacOS) return found;
  final searchDirs = [
    '/Applications',
    '/System/Applications',
    '${Platform.environment['HOME'] ?? ''}/Applications',
  ];
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
  /// (the `open -a` contract on macOS, the executable path on
  /// Windows). An empty [app] opens the operating system's
  /// default handler for the file. Throws an [AppError] on
  /// failure.
  Future<void> launch(String app, String filePath);

  /// Watches a directory for changes (watching the directory —
  /// not the file — survives editors that save by atomic rename).
  Stream<FileSystemEvent> watchDirectory(String directoryPath);
}

final class ProcessExternalEditorRuntime implements ExternalEditorRuntime {
  const ProcessExternalEditorRuntime();

  @override
  Future<void> launch(String app, String filePath) async {
    final label = app.isEmpty ? 'the default editor' : app;
    try {
      if (Platform.isMacOS) {
        final args = app.isEmpty ? [filePath] : ['-a', app, filePath];
        final result = await Process.run('/usr/bin/open', args);
        if (result.exitCode != 0) {
          throw AppError(
            category: AppErrorCategory.unknown,
            userMessage: 'Could not open the external editor ($label).',
            diagnostic: '${result.stderr}'.trim(),
          );
        }
        return;
      }
      if (Platform.isWindows) {
        if (app.isNotEmpty) {
          // Detached: the editor outlives the launch call, and
          // its exit code says nothing about the edit session.
          await Process.start(app, [filePath], mode: ProcessStartMode.detached);
        } else {
          final result = await Process.run('cmd', [
            '/c',
            'start',
            '',
            filePath,
          ]);
          if (result.exitCode != 0) {
            throw AppError(
              category: AppErrorCategory.unknown,
              userMessage: 'Could not open the external editor ($label).',
              diagnostic: '${result.stderr}'.trim(),
            );
          }
        }
        return;
      }
      throw AppError(
        category: AppErrorCategory.unknown,
        userMessage:
            'External editors are not supported on this '
            'platform yet.',
        diagnostic: Platform.operatingSystem,
      );
    } on AppError {
      rethrow;
    } catch (e) {
      throw AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'Could not open the external editor ($label).',
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
      if (event.path == file.path ||
          event.path.endsWith('/$_basename') ||
          event.path.endsWith('\\$_basename')) {
        _schedule();
      }
    });
  }

  String get _basename => file.path.split(RegExp(r'[/\\]')).last;

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
