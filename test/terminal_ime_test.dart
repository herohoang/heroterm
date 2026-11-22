import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Regression tests for the vendored xterm IME patch
/// (third_party/xterm/VENDORED.md): Vietnamese Telex toggling
/// (w -> ư -> w) must produce exactly one committed character, and
/// re-sent IME values must not duplicate input.
void main() {
  Future<(Terminal, StringBuffer)> pumpTerminal(WidgetTester tester) async {
    final terminal = Terminal();
    final output = StringBuffer();
    terminal.onOutput = output.write;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalView(terminal, autofocus: true)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    return (terminal, output);
  }

  void send(WidgetTester tester, TextEditingValue value) {
    tester.testTextInput.updateEditingValue(value);
  }

  TextEditingValue composing(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
    composing: TextRange(start: 0, end: text.length),
  );

  TextEditingValue committed(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  testWidgets('plain typing inserts each character once', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('a'));
    await tester.pump();
    send(tester, committed('ab'));
    await tester.pump();
    expect(output.toString(), 'ab');
  });

  testWidgets('Telex toggle w -> ư -> w commits a single w', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    // First w: IME composes ư (provisional, nothing sent yet).
    send(tester, composing('ư'));
    await tester.pump();
    expect(output.toString(), isEmpty);
    // Second w: the IM replaces the composing text with w.
    send(tester, composing('w'));
    await tester.pump();
    expect(output.toString(), isEmpty);
    // Commit: exactly one 'w' reaches the terminal — not ưư, not ưw.
    send(tester, committed('w'));
    await tester.pump();
    expect(output.toString(), 'w');
  });

  testWidgets('an IME restarted by a state reset cannot duplicate '
      'the committed character (the original ưư bug)', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    // Platform sequence observed on macOS with the upstream code:
    // the app reset the editing state after the first commit, the
    // Vietnamese IM lost its toggle state, treated the next w as a
    // fresh keystroke and committed ư a second time.
    send(tester, composing('ư'));
    await tester.pump();
    send(tester, committed('ư'));
    await tester.pump();
    send(tester, composing('ư'));
    await tester.pump();
    send(tester, committed('ư'));
    await tester.pump();
    expect(output.toString(), 'ư');
  });

  testWidgets('composing a diacritic syllable commits it once', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, composing('a'));
    await tester.pump();
    send(tester, composing('á'));
    await tester.pump();
    send(tester, committed('á'));
    await tester.pump();
    expect(output.toString(), 'á');
  });

  testWidgets('re-sent identical editing values are no-ops', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('x'));
    await tester.pump();
    send(tester, committed('x'));
    await tester.pump();
    expect(output.toString(), 'x');
  });

  testWidgets('shrinking the committed text sends one backspace', (
    tester,
  ) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('ab'));
    await tester.pump();
    expect(output.toString(), 'ab');
    send(tester, committed('a'));
    await tester.pump();
    expect(output.toString(), 'ab\x7f');
  });

  // ADR-014 regression tests: the original patch never resynced
  // its committed-text tracking when the platform buffer restarted
  // (new input connection after a focus round-trip), so the next
  // keystroke was diffed against the whole typing history —
  // swallowing matching prefix characters and flooding the shell
  // with backspaces that deleted the line being typed.

  testWidgets('focus round-trip restarts the buffer without eating '
      'characters or flooding backspaces', (tester) async {
    final terminal = Terminal();
    final output = StringBuffer();
    terminal.onOutput = output.write;
    final otherFocus = FocusNode();
    addTearDown(otherFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: otherFocus, child: const SizedBox(height: 40)),
              Expanded(child: TerminalView(terminal, autofocus: true)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    send(tester, committed('docker'));
    await tester.pump();
    expect(output.toString(), 'docker');

    // Focus leaves the terminal (the input connection closes) and
    // comes back (a new connection restarts the platform buffer
    // at empty).
    otherFocus.requestFocus();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(TerminalView));
    await tester.pump();
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);

    // The first keystroke in the fresh buffer must arrive whole —
    // 'd' starts the old history, so the old diff swallowed it and
    // emitted six backspaces.
    send(tester, committed('d'));
    await tester.pump();
    send(tester, committed('do'));
    await tester.pump();
    expect(output.toString(), 'dockerdo');
    // Flush gesture/cursor timers left over from the tap so the
    // test framework's teardown invariant holds.
    await tester.pump(const Duration(seconds: 2));
  });

  // ADR-017: ADR-014/015 resynced silently on a large divergence
  // and SWALLOWED the characters the user had just typed — the
  // "first letter of the command breaks" report. A divergence
  // that reaches deep into already-sent text is a platform buffer
  // restart, and the new snapshot holds exactly what was typed
  // since: it must be forwarded as fresh input, with no deletes.
  testWidgets('a mid-connection restart forwards the retyped '
      'characters instead of swallowing them', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    const line = 'docker compose build queue-worker';
    send(tester, committed(line));
    await tester.pump();
    expect(output.toString(), line);
    // The platform buffer restarts behind our back; the next
    // snapshot shares nothing with the accumulated history.
    send(tester, committed('d'));
    await tester.pump();
    expect(output.toString(), '${line}d');
    send(tester, committed('do'));
    await tester.pump();
    expect(output.toString(), '${line}do');
  });

  testWidgets('a restart mid-line appends the keystrokes and '
      'never backspaces the visible line', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('docker com'));
    await tester.pump();
    // Buffer restarts; the user types the next letter of the word.
    send(tester, committed('p'));
    await tester.pump();
    expect(output.toString(), 'docker comp');
    expect(output.toString().contains('\x7f'), isFalse);
  });

  testWidgets('a restart followed by a different word appends it '
      'whole (keystroke-faithful)', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('docker'));
    await tester.pump();
    send(tester, committed('nano'));
    await tester.pump();
    expect(output.toString(), 'dockernano');
  });

  testWidgets('a phantom empty snapshot does not wipe the line', (
    tester,
  ) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('docker'));
    await tester.pump();
    send(tester, committed(''));
    await tester.pump();
    expect(output.toString(), 'docker');
    // The genuine buffer still holds the line; typing continues
    // from it as a plain append.
    send(tester, committed('docker '));
    await tester.pump();
    expect(output.toString(), 'docker ');
  });

  testWidgets('submitting a line rebases the buffer and a late '
      'echo of the line is swallowed', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('ls'));
    await tester.pump();
    expect(output.toString(), 'ls');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final afterEnter = output.toString();
    // A platform update generated before the rebase replays the
    // submitted line: it must not be typed again at the new prompt.
    send(tester, committed('ls'));
    await tester.pump();
    expect(output.toString(), afterEnter);
    // Typing on the fresh line flows normally.
    send(tester, committed('w'));
    await tester.pump();
    expect(output.toString(), '${afterEnter}w');
  });

  testWidgets('an Enter delivered as text rebases too, and an '
      'echo coalesced with fresh typing is stripped', (tester) async {
    final (_, output) = await pumpTerminal(tester);
    send(tester, committed('docker'));
    await tester.pump();
    send(tester, committed('docker\n'));
    await tester.pump();
    final afterEnter = output.toString();
    // The platform coalesces its replay of the submitted line
    // with the first keystroke of the next one: only the fresh
    // keystroke may reach the shell.
    send(tester, committed('dockerx'));
    await tester.pump();
    expect(output.toString(), '${afterEnter}x');
  });
}
