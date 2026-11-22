import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// The Windows input mode (ADR-023): TerminalView with
/// hardwareKeyboardOnly reads key events directly instead of the
/// platform text-input connection. These tests lock the behavior
/// the Windows build depends on — plain typing, the exact
/// `docker compose ` + space case from the bug reports, and
/// backspace as a mapped key.
void main() {
  testWidgets('hardware mode: typed characters reach onOutput', (tester) async {
    final terminal = Terminal();
    final out = StringBuffer();
    terminal.onOutput = out.write;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            hardwareKeyboardOnly: true,
            autofocus: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(TerminalView));
    await tester.pump();

    Future<void> type(LogicalKeyboardKey key, String character) async {
      await tester.sendKeyDownEvent(key, character: character);
      await tester.sendKeyUpEvent(key);
    }

    await type(LogicalKeyboardKey.keyD, 'd');
    await type(LogicalKeyboardKey.keyO, 'o');
    await type(LogicalKeyboardKey.keyC, 'c');
    await type(LogicalKeyboardKey.keyK, 'k');
    await type(LogicalKeyboardKey.keyE, 'e');
    await type(LogicalKeyboardKey.keyR, 'r');
    await type(LogicalKeyboardKey.space, ' ');
    await type(LogicalKeyboardKey.keyC, 'c');
    await type(LogicalKeyboardKey.keyO, 'o');
    await type(LogicalKeyboardKey.keyM, 'm');
    await type(LogicalKeyboardKey.keyP, 'p');
    await type(LogicalKeyboardKey.keyO, 'o');
    await type(LogicalKeyboardKey.keyS, 's');
    await type(LogicalKeyboardKey.keyE, 'e');
    await type(LogicalKeyboardKey.space, ' ');
    expect(out.toString(), 'docker compose ');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    expect(out.toString(), 'docker compose \x7f');

    // Unmount so the view's cursor-blink timer is released before
    // the test's pending-timer invariant runs.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 350));
  });
}
