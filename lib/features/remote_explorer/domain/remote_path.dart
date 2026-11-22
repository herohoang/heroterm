/// Utilities for remote POSIX paths (ARCHITECTURE: remote file service
/// treats paths as remote POSIX paths, not local macOS paths;
/// TEST_PLAN: path normalization and breadcrumb ancestors).
abstract final class RemotePath {
  /// Normalizes an absolute POSIX path: collapses duplicate slashes and
  /// `.` segments and resolves `..` without going above the root.
  static String normalize(String path) {
    final segments = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(part);
    }
    return '/${segments.join('/')}';
  }

  static String parentOf(String path) {
    final normalized = normalize(path);
    if (normalized == '/') return '/';
    final idx = normalized.lastIndexOf('/');
    return idx == 0 ? '/' : normalized.substring(0, idx);
  }

  /// Ancestors for breadcrumb navigation, root first, including [path]
  /// itself as the last element. E.g. `/a/b` -> `[/, /a, /a/b]`.
  static List<String> ancestorsOf(String path) {
    final normalized = normalize(path);
    if (normalized == '/') return const ['/'];
    final result = <String>['/'];
    var current = '';
    for (final part in normalized.split('/').where((p) => p.isNotEmpty)) {
      current = '$current/$part';
      result.add(current);
    }
    return result;
  }

  static String join(String base, String child) {
    if (child.startsWith('/')) return normalize(child);
    final normalizedBase = normalize(base);
    return normalize(
      normalizedBase == '/' ? '/$child' : '$normalizedBase/$child',
    );
  }

  /// Validation for a new file/folder name (FEATURE_SPEC section 6):
  /// rejects empty names, `.`/`..`, and path separators.
  static String? validateNewName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name must not be empty.';
    if (trimmed == '.' || trimmed == '..') {
      return 'Name must not be "." or "..".';
    }
    if (trimmed.contains('/') || trimmed.contains(r'\')) {
      return 'Name must not contain path separators.';
    }
    if (trimmed.contains('\x00')) return 'Name must not contain NUL.';
    return null;
  }

  /// Parses an OSC 7 working-directory report payload
  /// (`file://host/path`, path percent-encoded) into a plain remote
  /// path. Returns null when the payload is not a usable file URL.
  static String? parseOsc7(String payload) {
    final trimmed = payload.trim();
    if (!trimmed.startsWith('file://')) return null;
    final afterScheme = trimmed.substring('file://'.length);
    final slash = afterScheme.indexOf('/');
    if (slash < 0) return null;
    final rawPath = afterScheme.substring(slash);
    String decoded;
    try {
      decoded = Uri.decodeComponent(rawPath);
    } on ArgumentError {
      decoded = rawPath;
    } on FormatException {
      decoded = rawPath;
    }
    if (decoded.isEmpty) return null;
    return normalize(decoded);
  }
}
