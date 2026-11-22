import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/highlight.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('computeTerminalHighlights (ADR-024)', () {
    BufferLine lineOf(String text) {
      final terminal = Terminal(maxLines: 100)..resize(200, 24, 0, 0);
      terminal.write('$text\r\n');
      return terminal.buffer.lines[0];
    }

    List<String> matchedTexts(BufferLine line) {
      return [
        for (final span in computeTerminalHighlights(line))
          line.getText(span.startCell, span.endCell),
      ];
    }

    test('MOTD line: URL, IPv4 and quantities are highlighted', () {
      final line = lineOf(
        'Usage of /: 65.2% of 18.33GB, IPv4 103.82.192.240, '
        'see https://ubuntu.com/pro',
      );
      final texts = matchedTexts(line);
      expect(texts, contains('https://ubuntu.com/pro'));
      expect(texts, contains('103.82.192.240'));
      expect(texts, contains('65.2%'));
      expect(texts, contains('18.33GB'));
    });

    test('keyword levels get their own spans', () {
      expect(
        matchedTexts(lineOf('error: failed to connect')),
        containsAll(['error', 'failed']),
      );
      expect(
        matchedTexts(lineOf('Warning: could not save the file')),
        containsAll(['Warning', 'could not']),
      );
      expect(
        matchedTexts(lineOf('service is enabled and running')),
        containsAll(['enabled', 'running']),
      );
      expect(
        matchedTexts(lineOf('System information as of today')),
        contains('information'),
      );
    });

    test('an IP inside a URL stays one URL span', () {
      final texts = matchedTexts(lineOf('go to https://103.82.192.240/x'));
      expect(texts, ['https://103.82.192.240/x']);
    });

    test('times are not fragmented into numbers', () {
      final texts = matchedTexts(
        lineOf('Last login: Fri Nov 20 13:03:15 2026 from 118.69.66.237'),
      );
      expect(texts, contains('118.69.66.237'));
      expect(texts, isNot(contains('13')));
      expect(texts, isNot(contains('03')));
      expect(texts, isNot(contains('15')));
    });

    test('shell-colored text is never overridden', () {
      final terminal = Terminal(maxLines: 100)..resize(200, 24, 0, 0);
      terminal.write('\x1B[1;31merror\x1B[0m error\r\n');
      final line = terminal.buffer.lines[0];
      final spans = computeTerminalHighlights(line);
      // Only the second, default-colored "error" may highlight.
      expect(spans, hasLength(1));
      expect(
        line.getText(spans.single.startCell, spans.single.endCell),
        'error',
      );
      expect(spans.single.startCell, 6);
    });

    test('email addresses highlight like links', () {
      expect(
        matchedTexts(lineOf('contact admin@example.com for help')),
        contains('admin@example.com'),
      );
    });

    test('plain prose without keywords stays clean', () {
      expect(
        matchedTexts(lineOf('Welcome to Ubuntu (GNU/Linux generic)')),
        isEmpty,
      );
    });
  });
  viewPlumbingTests();
}

void viewPlumbingTests() {
  testWidgets('TerminalView paints highlighted output and toggles cleanly', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 100)..resize(120, 24, 0, 0);
    terminal.write('error: failed to reach 103.82.192.240 (65.2%)\r\n');
    Widget app(bool enabled) => MaterialApp(
      home: Scaffold(
        body: TerminalView(terminal, highlightingEnabled: enabled),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 350));
  });
}
