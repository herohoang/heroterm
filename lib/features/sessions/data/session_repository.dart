import 'dart:convert';
import 'dart:io';

import '../domain/session_folder.dart';
import '../domain/session_label.dart';
import '../domain/ssh_session.dart';

/// The full persisted session-library snapshot: non-secret metadata only.
///
/// [legacyLabelNames] is a LOAD-TIME migration channel (ADR-013):
/// when a library file predates labels, the repository extracts
/// each session's old `environment`/`tags` values as label names
/// (session id → names); the controller turns them into real
/// labels, assigns them, and persists the migrated library. It is
/// always empty on save and for current-format files.
typedef SessionLibrary = ({
  List<SshSession> sessions,
  List<SessionFolder> folders,
  List<SessionLabel> labels,
  Map<String, List<String>> legacyLabelNames,
});

const emptyLibrary = (
  sessions: <SshSession>[],
  folders: <SessionFolder>[],
  labels: <SessionLabel>[],
  legacyLabelNames: <String, List<String>>{},
);

/// Persistence boundary for session metadata (ARCHITECTURE: session
/// repository). Secrets never pass through this interface.
abstract interface class SessionRepository {
  Future<SessionLibrary> load();
  Future<void> save(SessionLibrary library);
}

/// In-memory repository for tests and previews.
final class InMemorySessionRepository implements SessionRepository {
  InMemorySessionRepository([SessionLibrary initial = emptyLibrary])
    : _library = initial;

  SessionLibrary _library;
  int saveCount = 0;

  @override
  Future<SessionLibrary> load() async => _library;

  @override
  Future<void> save(SessionLibrary library) async {
    _library = library;
    saveCount++;
  }
}

/// JSON-file repository (ADR-006).
///
/// Stores session/folder metadata as a single JSON document in the
/// application support directory. Writes are atomic (write to a temp
/// file, then rename) so a crash mid-write cannot truncate the library.
/// If the file cannot be parsed, it is preserved as `<name>.corrupt`
/// and the library starts empty rather than crashing the app.
final class JsonFileSessionRepository implements SessionRepository {
  JsonFileSessionRepository(this._resolveDirectory);

  /// Resolves the directory holding `heroterm-sessions.json`
  /// (the app support directory in production; a temp directory in
  /// tests).
  final Future<Directory> Function() _resolveDirectory;

  Future<File> _file() async {
    final dir = await _resolveDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/heroterm-sessions.json');
  }

  @override
  Future<SessionLibrary> load() async {
    final file = await _file();
    if (!await file.exists()) return emptyLibrary;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return emptyLibrary;
      final rawSessions = (decoded['sessions'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .toList();
      final sessions = rawSessions.map(SshSession.fromJson).toList();
      final folders = (decoded['folders'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(SessionFolder.fromJson)
          .toList();
      final labels = (decoded['labels'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(SessionLabel.fromJson)
          .toList();
      // ADR-013 migration seeds: legacy environment (except the
      // unspecified 'other') and tags become label names.
      final legacyLabelNames = <String, List<String>>{};
      for (final raw in rawSessions) {
        final names = <String>[];
        final env = raw['environment'];
        if (env is String && env.isNotEmpty && env != 'other') {
          names.add('${env[0].toUpperCase()}${env.substring(1)}');
        }
        final tags = raw['tags'];
        if (tags is List) {
          for (final t in tags) {
            if (t is String && t.trim().isNotEmpty) names.add(t.trim());
          }
        }
        final id = raw['id'];
        if (names.isNotEmpty && id is String) legacyLabelNames[id] = names;
      }
      return (
        sessions: sessions,
        folders: folders,
        labels: labels,
        legacyLabelNames: legacyLabelNames,
      );
    } on FormatException {
      final backup = File('${file.path}.corrupt');
      if (await file.exists()) await file.rename(backup.path);
      return emptyLibrary;
    }
  }

  @override
  Future<void> save(SessionLibrary library) async {
    final file = await _file();
    final payload = <String, Object?>{
      'version': 1,
      'sessions': library.sessions.map((s) => s.toJson()).toList(),
      'folders': library.folders.map((f) => f.toJson()).toList(),
      'labels': library.labels.map((l) => l.toJson()).toList(),
    };
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(payload), flush: true);
    await tmp.rename(file.path);
  }
}
