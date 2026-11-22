import 'package:flutter/material.dart';

import '../domain/text_file_rules.dart';

/// A deliberately small, regex-free syntax highlighter for the
/// built-in editor (Edit File spec §2.2): a single-pass scanner
/// that understands line/block comments, string literals,
/// numbers, keywords, key–value heads (yaml/ini/env/json) and
/// markup tags. It is not a parser — it favours never crashing
/// and never mis-colouring plain text over completeness.
final class _LangSpec {
  const _LangSpec({
    this.lineComments = const [],
    this.blockComment,
    this.strings = const ['"', "'"],
    this.keywords = const {},
    this.keyValue = false,
    this.tags = false,
  });

  final List<String> lineComments;
  final (String, String)? blockComment;
  final List<String> strings;
  final Set<String> keywords;
  final bool keyValue;
  final bool tags;
}

const _cKeywords = {
  'if',
  'else',
  'for',
  'while',
  'do',
  'switch',
  'case',
  'default',
  'break',
  'continue',
  'return',
  'function',
  'class',
  'extends',
  'new',
  'var',
  'let',
  'const',
  'static',
  'final',
  'void',
  'int',
  'double',
  'bool',
  'true',
  'false',
  'null',
  'this',
  'import',
  'from',
  'export',
  'try',
  'catch',
  'throw',
  'async',
  'await',
};

_LangSpec _specFor(EditorLanguage language) {
  switch (language) {
    case EditorLanguage.shell:
      return const _LangSpec(
        lineComments: ['#'],
        keywords: {
          'if',
          'then',
          'else',
          'elif',
          'fi',
          'for',
          'while',
          'do',
          'done',
          'case',
          'esac',
          'function',
          'return',
          'exit',
          'export',
          'local',
          'readonly',
          'echo',
          'cd',
          'source',
        },
      );
    case EditorLanguage.php:
      return _LangSpec(
        lineComments: const ['//', '#'],
        blockComment: ('/*', '*/'),
        keywords: {
          ..._cKeywords,
          'echo',
          'foreach',
          'as',
          'public',
          'private',
          'protected',
          'namespace',
          'use',
          'fn',
          'match',
        },
      );
    case EditorLanguage.javascript:
    case EditorLanguage.typescript:
    case EditorLanguage.vue:
      return _LangSpec(
        lineComments: const ['//'],
        blockComment: ('/*', '*/'),
        strings: const ['"', "'", '`'],
        keywords: {
          ..._cKeywords,
          'typeof',
          'instanceof',
          'of',
          'in',
          'interface',
          'type',
          'enum',
          'implements',
          'readonly',
        },
        tags: language == EditorLanguage.vue,
      );
    case EditorLanguage.dart:
      return _LangSpec(
        lineComments: const ['//'],
        blockComment: ('/*', '*/'),
        keywords: {
          ..._cKeywords,
          'late',
          'required',
          'override',
          'get',
          'set',
          'mixin',
          'extension',
          'is',
          'in',
          'super',
          'factory',
        },
      );
    case EditorLanguage.python:
      return const _LangSpec(
        lineComments: ['#'],
        strings: ['"', "'"],
        keywords: {
          'def',
          'class',
          'return',
          'if',
          'elif',
          'else',
          'for',
          'while',
          'try',
          'except',
          'finally',
          'with',
          'as',
          'import',
          'from',
          'pass',
          'break',
          'continue',
          'lambda',
          'yield',
          'async',
          'await',
          'True',
          'False',
          'None',
          'and',
          'or',
          'not',
          'in',
          'is',
          'global',
          'raise',
          'print',
        },
      );
    case EditorLanguage.go:
      return _LangSpec(
        lineComments: const ['//'],
        blockComment: ('/*', '*/'),
        strings: const ['"', "'", '`'],
        keywords: {
          'func',
          'var',
          'const',
          'type',
          'struct',
          'interface',
          'map',
          'chan',
          'go',
          'defer',
          'if',
          'else',
          'for',
          'range',
          'switch',
          'case',
          'default',
          'return',
          'break',
          'continue',
          'package',
          'import',
          'true',
          'false',
          'nil',
        },
      );
    case EditorLanguage.html:
    case EditorLanguage.xml:
      return const _LangSpec(blockComment: ('<!--', '-->'), tags: true);
    case EditorLanguage.css:
    case EditorLanguage.scss:
      return _LangSpec(
        lineComments: language == EditorLanguage.scss ? const ['//'] : const [],
        blockComment: ('/*', '*/'),
      );
    case EditorLanguage.yaml:
    case EditorLanguage.ini:
    case EditorLanguage.env:
      return const _LangSpec(lineComments: ['#'], keyValue: true);
    case EditorLanguage.json:
      return const _LangSpec(keyValue: true);
    case EditorLanguage.sql:
      return const _LangSpec(
        lineComments: ['--'],
        blockComment: ('/*', '*/'),
        keywords: {
          'select',
          'from',
          'where',
          'insert',
          'into',
          'values',
          'update',
          'set',
          'delete',
          'create',
          'table',
          'drop',
          'alter',
          'join',
          'left',
          'right',
          'inner',
          'outer',
          'on',
          'group',
          'by',
          'order',
          'limit',
          'offset',
          'having',
          'union',
          'and',
          'or',
          'not',
          'null',
          'primary',
          'key',
        },
      );
    case EditorLanguage.markdown:
    case EditorLanguage.plain:
      return const _LangSpec(strings: []);
  }
}

/// Token colours, chosen per brightness.
final class HighlightPalette {
  HighlightPalette(Brightness brightness)
    : comment = brightness == Brightness.dark
          ? const Color(0xFF7A8699)
          : const Color(0xFF6A737D),
      string = brightness == Brightness.dark
          ? const Color(0xFFA5D6A7)
          : const Color(0xFF22863A),
      number = brightness == Brightness.dark
          ? const Color(0xFFFFCC80)
          : const Color(0xFFB76B01),
      keyword = brightness == Brightness.dark
          ? const Color(0xFF82AAFF)
          : const Color(0xFF005CC5),
      key = brightness == Brightness.dark
          ? const Color(0xFF7FDBCA)
          : const Color(0xFF6F42C1),
      tag = brightness == Brightness.dark
          ? const Color(0xFF82AAFF)
          : const Color(0xFF22863A),
      searchMatch = brightness == Brightness.dark
          ? const Color(0xFF6D5E00)
          : const Color(0xFFFFF59D);

  final Color comment;
  final Color string;
  final Color number;
  final Color keyword;
  final Color key;
  final Color tag;
  final Color searchMatch;
}

/// A [TextEditingController] that renders its text with syntax
/// highlighting (and optional find-match highlighting) through
/// buildTextSpan — the standard hook [TextField] uses.
final class HighlightingController extends TextEditingController {
  HighlightingController({required this.language, super.text});

  final EditorLanguage language;

  /// Current find query; empty = no match highlighting.
  String searchQuery = '';

  /// Re-renders spans (e.g. after [searchQuery] changed).
  void refreshSpans() => notifyListeners();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final text = this.text;
    if (text.isEmpty) return TextSpan(style: base, text: '');
    final palette = HighlightPalette(Theme.of(context).brightness);
    final spec = _specFor(language);
    var spans = _tokenize(text, spec, base, palette);
    if (language == EditorLanguage.markdown) {
      spans = _markdownPass(text, spans, base, palette);
    }
    if (searchQuery.isNotEmpty) {
      spans = _searchPass(spans, searchQuery, palette);
    }
    return TextSpan(style: base, children: spans);
  }
}

bool _isWordChar(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    unit == 0x5F ||
    unit == 0x24;

List<TextSpan> _tokenize(
  String text,
  _LangSpec spec,
  TextStyle base,
  HighlightPalette palette,
) {
  final spans = <TextSpan>[];
  final plain = StringBuffer();
  void flush([TextStyle? extra]) {
    if (plain.isEmpty) return;
    spans.add(TextSpan(text: plain.toString(), style: extra));
    plain.clear();
  }

  var i = 0;
  var atLineStart = true;
  final n = text.length;
  while (i < n) {
    // Line comments.
    var matched = false;
    for (final marker in spec.lineComments) {
      if (text.startsWith(marker, i)) {
        var end = text.indexOf('\n', i);
        if (end < 0) end = n;
        flush();
        spans.add(
          TextSpan(
            text: text.substring(i, end),
            style: TextStyle(color: palette.comment),
          ),
        );
        i = end;
        matched = true;
        break;
      }
    }
    if (matched) continue;
    // Block comments.
    final block = spec.blockComment;
    if (block != null && text.startsWith(block.$1, i)) {
      var end = text.indexOf(block.$2, i + block.$1.length);
      end = end < 0 ? n : end + block.$2.length;
      flush();
      spans.add(
        TextSpan(
          text: text.substring(i, end),
          style: TextStyle(color: palette.comment),
        ),
      );
      i = end;
      continue;
    }
    final ch = text[i];
    // String literals (escapes honoured; no multi-line strings
    // except backtick literals, which may span lines).
    if (spec.strings.contains(ch)) {
      var j = i + 1;
      while (j < n) {
        final c = text[j];
        if (c == '\\') {
          j += 2;
          continue;
        }
        if (c == ch) {
          j++;
          break;
        }
        if (c == '\n' && ch != '`') break;
        j++;
      }
      if (j > n) j = n;
      flush();
      spans.add(
        TextSpan(
          text: text.substring(i, j),
          style: TextStyle(color: palette.string),
        ),
      );
      i = j;
      atLineStart = false;
      continue;
    }
    // Markup tags: colour <...> as one run.
    if (spec.tags && ch == '<') {
      var end = text.indexOf('>', i);
      if (end >= 0 && end - i < 200) {
        end += 1;
        flush();
        spans.add(
          TextSpan(
            text: text.substring(i, end),
            style: TextStyle(color: palette.tag),
          ),
        );
        i = end;
        atLineStart = false;
        continue;
      }
    }
    // Numbers.
    if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
      var j = i;
      while (j < n && (_isWordChar(text.codeUnitAt(j)) || text[j] == '.')) {
        j++;
      }
      flush();
      spans.add(
        TextSpan(
          text: text.substring(i, j),
          style: TextStyle(color: palette.number),
        ),
      );
      i = j;
      atLineStart = false;
      continue;
    }
    // Identifiers: keyword match, or a key-value head at line
    // start / after whitespace in yaml/ini/env/json.
    if (_isWordChar(ch.codeUnitAt(0))) {
      var j = i;
      while (j < n && _isWordChar(text.codeUnitAt(j))) {
        j++;
      }
      final word = text.substring(i, j);
      if (spec.keywords.contains(word) ||
          spec.keywords.contains(word.toLowerCase())) {
        flush();
        spans.add(
          TextSpan(
            text: word,
            style: TextStyle(
              color: palette.keyword,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else if (spec.keyValue && _followedByKeySeparator(text, j)) {
        flush();
        spans.add(
          TextSpan(
            text: word,
            style: TextStyle(color: palette.key),
          ),
        );
      } else {
        plain.write(word);
      }
      i = j;
      atLineStart = false;
      continue;
    }
    plain.write(ch);
    atLineStart = ch == '\n' || (atLineStart && (ch == ' ' || ch == '\t'));
    i++;
  }
  flush();
  return spans;
}

/// For key–value formats: a word directly followed by `:` or `=`
/// (the json case requires the colon before a quote-aware value,
/// approximated by the same rule).
bool _followedByKeySeparator(String text, int end) {
  var j = end;
  while (j < text.length && (text[j] == ' ' || text[j] == '\t')) {
    j++;
  }
  if (j >= text.length) return false;
  return text[j] == ':' || text[j] == '=';
}

/// Markdown: headings and bold get emphasis on top of plain runs.
/// (The tokenizer produced unstyled spans; re-split lines here.)
List<TextSpan> _markdownPass(
  String text,
  List<TextSpan> spans,
  TextStyle base,
  HighlightPalette palette,
) {
  final out = <TextSpan>[];
  for (final line in text.split('\n')) {
    // split() drops the newline; spans are rebuilt per line, so
    // this pass REPLACES the incoming spans entirely.
    if (line.startsWith('#')) {
      out.add(
        TextSpan(
          text: line,
          style: TextStyle(color: palette.keyword, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      out.add(TextSpan(text: line));
    }
    out.add(const TextSpan(text: '\n'));
  }
  if (out.isNotEmpty) out.removeLast();
  return out;
}

/// Splits existing spans on case-insensitive matches of [query]
/// and paints the matches.
List<TextSpan> _searchPass(
  List<TextSpan> spans,
  String query,
  HighlightPalette palette,
) {
  final lowerQuery = query.toLowerCase();
  final out = <TextSpan>[];
  for (final span in spans) {
    final text = span.text ?? '';
    if (text.isEmpty || span.children != null) {
      out.add(span);
      continue;
    }
    var index = 0;
    while (true) {
      final hit = text.toLowerCase().indexOf(lowerQuery, index);
      if (hit < 0) {
        if (index < text.length) {
          out.add(TextSpan(text: text.substring(index), style: span.style));
        }
        break;
      }
      if (hit > index) {
        out.add(TextSpan(text: text.substring(index, hit), style: span.style));
      }
      out.add(
        TextSpan(
          text: text.substring(hit, hit + query.length),
          style: (span.style ?? const TextStyle()).copyWith(
            backgroundColor: palette.searchMatch,
          ),
        ),
      );
      index = hit + query.length;
    }
  }
  return out;
}
