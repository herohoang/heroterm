import 'dart:convert';

/// Rules deciding what the built-in editor may open and how it is
/// highlighted (Edit File spec §2.2 and §4): a hard size ceiling, a
/// binary sniff test, and strict UTF-8 — an unsupported encoding is
/// refused, never "repaired" into corrupted content.
const int maxEditableBytes = 2 * 1024 * 1024;

/// Language identifiers understood by the syntax highlighter.
/// Detection is by file extension (plus a few well-known names);
/// anything unrecognised is [EditorLanguage.plain] but still
/// editable when the content checks pass.
enum EditorLanguage {
  plain,
  shell,
  php,
  javascript,
  typescript,
  vue,
  dart,
  python,
  go,
  html,
  css,
  scss,
  markdown,
  yaml,
  json,
  xml,
  ini,
  env,
  sql,
}

EditorLanguage languageForPath(String path) {
  final name = path.split('/').last;
  if (name == '.env' || name.startsWith('.env.')) {
    return EditorLanguage.env;
  }
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return EditorLanguage.plain;
  return switch (name.substring(dot + 1).toLowerCase()) {
    'sh' || 'bash' || 'zsh' => EditorLanguage.shell,
    'php' => EditorLanguage.php,
    'js' || 'mjs' || 'cjs' => EditorLanguage.javascript,
    'ts' || 'tsx' => EditorLanguage.typescript,
    'vue' => EditorLanguage.vue,
    'dart' => EditorLanguage.dart,
    'py' => EditorLanguage.python,
    'go' => EditorLanguage.go,
    'html' || 'htm' => EditorLanguage.html,
    'css' => EditorLanguage.css,
    'scss' => EditorLanguage.scss,
    'md' || 'markdown' => EditorLanguage.markdown,
    'yaml' || 'yml' => EditorLanguage.yaml,
    'json' => EditorLanguage.json,
    'xml' || 'svg' => EditorLanguage.xml,
    'ini' || 'conf' || 'cfg' => EditorLanguage.ini,
    'env' => EditorLanguage.env,
    'sql' => EditorLanguage.sql,
    _ => EditorLanguage.plain,
  };
}

/// Extensions the spec lists as editable text formats (§2.2). The
/// context menu uses this only as a hint for its error message —
/// the decisive checks are size, binary content, and UTF-8 below.
bool isListedTextExtension(String path) =>
    languageForPath(path) != EditorLanguage.plain ||
    path.toLowerCase().endsWith('.txt') ||
    path.toLowerCase().endsWith('.log');

/// A file is treated as binary when a NUL byte appears in its
/// first 8 KB — the classic text/binary sniff.
bool looksBinary(List<int> bytes) {
  final limit = bytes.length < 8192 ? bytes.length : 8192;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Result of decoding remote bytes for the editor.
final class DecodedTextFile {
  const DecodedTextFile(this.text, {this.hasBom = false});

  final String text;

  /// A UTF-8 BOM was present and stripped; saving re-adds it so
  /// the round trip is byte-stable for BOM-carrying files.
  final bool hasBom;
}

/// Strictly decodes UTF-8 (throws [FormatException] on malformed
/// input — callers turn that into a clear "unsupported encoding"
/// message rather than lossy-decoding someone's config file).
DecodedTextFile decodeTextFile(List<int> bytes) {
  var hasBom = false;
  var body = bytes;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    hasBom = true;
    body = bytes.sublist(3);
  }
  return DecodedTextFile(utf8.decode(body), hasBom: hasBom);
}

/// Encodes editor text back to the exact bytes to upload.
List<int> encodeTextFile(String text, {required bool hasBom}) {
  final body = utf8.encode(text);
  if (!hasBom) return body;
  return [0xEF, 0xBB, 0xBF, ...body];
}
