import 'dart:ui';

import 'package:xterm/xterm.dart';

/// A MobaXterm-style keyword highlighting rule (ADR-024): when a
/// match of [pattern] appears in terminal output text that the
/// shell itself left uncolored, the matched range is painted
/// with [foreground] (and optionally underlined) instead of the
/// theme's default foreground.
class TerminalHighlightRule {
  const TerminalHighlightRule(
    this.pattern,
    this.foreground, {
    this.underline = false,
  });

  final RegExp pattern;
  final Color foreground;
  final bool underline;
}

/// A resolved highlight over a range of cells of one line.
class TerminalHighlightSpan {
  const TerminalHighlightSpan(this.startCell, this.endCell, this.rule);

  /// First highlighted cell (inclusive).
  final int startCell;

  /// End of the highlight (exclusive, in cells — a wide final
  /// character covers two).
  final int endCell;

  final TerminalHighlightRule rule;
}

/// The default rule set, modelled on MobaXterm's built-in
/// syntax highlighting (its MOTD/log look: links underlined,
/// IPv4 in pink, quantities amber, error/warning/success/info
/// keywords in their level colours). Order is priority: the
/// first rule to claim a range wins, so structural patterns
/// (URLs, addresses) precede generic ones (bare numbers), and
/// numbers precede keywords.
final terminalHighlightRules = <TerminalHighlightRule>[
  TerminalHighlightRule(
    RegExp(r'''https?://[^\s<>"']+'''),
    const Color(0xFF4FC3F7),
    underline: true,
  ),
  TerminalHighlightRule(
    RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+'),
    const Color(0xFF4FC3F7),
    underline: true,
  ),
  TerminalHighlightRule(
    RegExp(
      r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}'
      r'(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
    ),
    const Color(0xFFF06292),
  ),
  // Quantities: percentages and sizes/rates with units.
  TerminalHighlightRule(
    RegExp(
      r'\b\d+(?:[.,]\d+)?(?:\s?(?:%|GiB|MiB|KiB|GB|MB|KB|TB|Mb/s|MB/s))',
    ),
    const Color(0xFFFFD54F),
  ),
  // Bare numbers, but never a fragment of an IP, a time, a
  // version or a path (guarded by the neighbouring characters).
  TerminalHighlightRule(
    RegExp(r'(?<![\w.:/])\d+(?:\.\d+)?(?![\w.:/])'),
    const Color(0xFFFFF59D),
  ),
  TerminalHighlightRule(
    RegExp(
      r'\b(?:error|errors|failed|failure|fatal|critical|denied|refused|'
      r'invalid|exception|panic|traceback)\b',
      caseSensitive: false,
    ),
    const Color(0xFFEF5350),
  ),
  TerminalHighlightRule(
    RegExp(
      r'\b(?:warning|warn|could not|cannot|deprecated|unreachable|'
      r'timed out|timeout)\b',
      caseSensitive: false,
    ),
    const Color(0xFFFFB74D),
  ),
  TerminalHighlightRule(
    RegExp(
      r'\b(?:success|successful|successfully|ok|done|enabled|active|'
      r'running|passed|connected|complete|completed|ready|online)\b',
      caseSensitive: false,
    ),
    const Color(0xFF81C784),
  ),
  TerminalHighlightRule(
    RegExp(
      r'\b(?:info|information|note|notice|debug)\b',
      caseSensitive: false,
    ),
    const Color(0xFF64B5F6),
  ),
];

/// Computes the highlight spans for [line], in cell coordinates.
///
/// Only cells the shell left at the default colours are
/// eligible: a cell with an explicit foreground/background (or
/// the inverse flag) is the program's own colouring and is
/// never overridden — so `ls --color`, vim and friends keep
/// exactly their colours, and highlighting lands on the plain
/// output (MOTDs, logs, command results) it exists for.
List<TerminalHighlightSpan> computeTerminalHighlights(
  BufferLine line, [
  List<TerminalHighlightRule>? rules,
]) {
  final effectiveRules = rules ?? terminalHighlightRules;
  if (effectiveRules.isEmpty || line.length == 0) return const [];

  final (s, cellOfChar, widthOfChar, eligible) = _collectLine(line);
  if (s.trim().isEmpty) return const [];
  return _spansFor(s, cellOfChar, widthOfChar, eligible, effectiveRules);
}

/// One pass over [line] collecting its text plus, per character,
/// the cell it starts in, its cell width, and whether the cell
/// is eligible for highlighting (see [computeTerminalHighlights]).
(String, List<int>, List<int>, List<bool>) _collectLine(BufferLine line) {
  final cellData = CellData.empty();
  final text = StringBuffer();
  final cellOfChar = <int>[];
  final widthOfChar = <int>[];
  final eligible = <bool>[];
  for (var i = 0; i < line.length; i++) {
    line.getCellData(i, cellData);
    final width = cellData.content >> CellContent.widthShift;
    if (width == 0) continue; // continuation cell of a wide char
    final code = cellData.content & CellContent.codepointMask;
    text.writeCharCode(code == 0 ? 0x20 : code);
    cellOfChar.add(i);
    widthOfChar.add(width == 2 ? 2 : 1);
    eligible.add(
      (cellData.foreground & CellColor.typeMask) == CellColor.normal &&
          (cellData.background & CellColor.typeMask) == CellColor.normal &&
          (cellData.flags & CellFlags.inverse) == 0,
    );
  }
  return (text.toString(), cellOfChar, widthOfChar, eligible);
}

/// The claiming pass: rules in priority order take the ranges
/// they match, provided every character is unclaimed and
/// eligible.
List<TerminalHighlightSpan> _spansFor(
  String s,
  List<int> cellOfChar,
  List<int> widthOfChar,
  List<bool> eligible,
  List<TerminalHighlightRule> rules,
) {
  final claimed = List<bool>.filled(s.length, false);
  final spans = <TerminalHighlightSpan>[];
  for (final rule in rules) {
    for (final match in rule.pattern.allMatches(s)) {
      if (match.start == match.end) continue;
      var clear = true;
      for (var j = match.start; j < match.end; j++) {
        if (claimed[j] || !eligible[j]) {
          clear = false;
          break;
        }
      }
      if (!clear) continue;
      for (var j = match.start; j < match.end; j++) {
        claimed[j] = true;
      }
      final lastChar = match.end - 1;
      spans.add(
        TerminalHighlightSpan(
          cellOfChar[match.start],
          cellOfChar[lastChar] + widthOfChar[lastChar],
          rule,
        ),
      );
    }
  }
  spans.sort((a, b) => a.startCell.compareTo(b.startCell));
  return spans;
}

/// Stateful highlighter for the painter: caches spans per line
/// content (text + eligibility mask), so repaint-heavy moments
/// (cursor blink, scrolling over static text) do not re-run the
/// rule set for lines that did not change.
class TerminalHighlighter {
  TerminalHighlighter([List<TerminalHighlightRule>? rules])
      : rules = rules ?? terminalHighlightRules;

  final List<TerminalHighlightRule> rules;

  final _cache = <String, List<TerminalHighlightSpan>>{};

  List<TerminalHighlightSpan> highlightsFor(BufferLine line) {
    if (rules.isEmpty || line.length == 0) return const [];
    final (s, cellOfChar, widthOfChar, eligible) = _collectLine(line);
    if (s.trim().isEmpty) return const [];
    final mask = StringBuffer();
    for (final e in eligible) {
      mask.write(e ? '1' : '0');
    }
    final key = '$s\u{0}$mask';
    final cached = _cache[key];
    if (cached != null) return cached;
    final spans = _spansFor(s, cellOfChar, widthOfChar, eligible, rules);
    if (_cache.length >= 512) _cache.clear();
    _cache[key] = spans;
    return spans;
  }
}
