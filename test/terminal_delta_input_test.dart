import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Regression tests for the delta input adapter (ADR-020): the
/// platform narrates each edit as a [TextEditingDelta] and the
/// terminal must forward exactly those edits — including the
/// Vietnamese-IME commit-at-space flow that broke repeatedly
/// under the snapshot-diff model (ADR-014..018).
void main() {
  const noComposing = TextRange(start: -1, end: -1);

  TextSelection sel(int offset) => TextSelection.collapsed(offset: offset);

  TextEditingDeltaInsertion insert(
    String oldText,
    String text,
    int offset, {
    TextRange composing = noComposing,
  }) {
    return TextEditingDeltaInsertion(
      oldText: oldText,
      textInserted: text,
      insertionOffset: offset,
      selection: sel(offset + text.length),
      composing: composing,
    );
  }

  Future<(CustomTextEditState, StringBuffer)> pumpTerminal(
    WidgetTester tester,
  ) async {
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
    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );
    return (state, output);
  }

  void typeByDeltas(CustomTextEditState state, String text) {
    var doc = '';
    for (var i = 0; i < text.length; i++) {
      state.updateEditingValueWithDeltas([insert(doc, text[i], i)]);
      doc += text[i];
    }
  }

  testWidgets('plain typing via insertion deltas arrives verbatim', (
    tester,
  ) async {
    final (state, output) = await pumpTerminal(tester);
    typeByDeltas(state, 'docker compose ');
    await tester.pump();
    expect(output.toString(), 'docker compose ');
  });

  testWidgets('one batched insertion delta arrives verbatim', (tester) async {
    final (state, output) = await pumpTerminal(tester);
    state.updateEditingValueWithDeltas([insert('', 'docker compose ', 0)]);
    await tester.pump();
    expect(output.toString(), 'docker compose ');
  });

  testWidgets('Telex commit at space: held while composing, emitted once', (
    tester,
  ) async {
    final (state, output) = await pumpTerminal(tester);
    // Compose 'w' the Telex way: provisional ư, revised to w,
    // then the composition commits by clearing the range, and
    // the space follows as its own insertion.
    state.updateEditingValueWithDeltas([
      insert('', 'ư', 0, composing: const TextRange(start: 0, end: 1)),
    ]);
    await tester.pump();
    expect(output.toString(), isEmpty);
    state.updateEditingValueWithDeltas([
      TextEditingDeltaReplacement(
        oldText: 'ư',
        replacedRange: const TextRange(start: 0, end: 1),
        replacementText: 'w',
        selection: sel(1),
        composing: const TextRange(start: 0, end: 1),
      ),
    ]);
    await tester.pump();
    expect(output.toString(), isEmpty);
    state.updateEditingValueWithDeltas([
      TextEditingDeltaNonTextUpdate(
        oldText: 'w',
        selection: sel(1),
        composing: noComposing,
      ),
    ]);
    await tester.pump();
    expect(output.toString(), 'w');
    state.updateEditingValueWithDeltas([insert('w', ' ', 1)]);
    await tester.pump();
    expect(output.toString(), 'w ');
  });

  testWidgets('word composed after "docker ", committed at space', (
    tester,
  ) async {
    final (state, output) = await pumpTerminal(tester);
    typeByDeltas(state, 'docker ');
    // The whole second word arrives as one composing insertion,
    // is revised once inside the composition, then commits.
    state.updateEditingValueWithDeltas([
      insert(
        'docker ',
        'compos',
        7,
        composing: const TextRange(start: 7, end: 13),
      ),
    ]);
    state.updateEditingValueWithDeltas([
      TextEditingDeltaReplacement(
        oldText: 'docker compos',
        replacedRange: const TextRange(start: 7, end: 13),
        replacementText: 'compose',
        selection: sel(14),
        composing: const TextRange(start: 7, end: 14),
      ),
    ]);
    await tester.pump();
    expect(output.toString(), 'docker ');
    state.updateEditingValueWithDeltas([
      TextEditingDeltaNonTextUpdate(
        oldText: 'docker compose',
        selection: sel(14),
        composing: noComposing,
      ),
      insert('docker compose', ' ', 14),
    ]);
    await tester.pump();
    expect(output.toString(), 'docker compose ');
  });

  testWidgets('deletion deltas emit one backspace per committed char', (
    tester,
  ) async {
    final terminal = Terminal();
    final output = StringBuffer();
    var deletes = 0;
    terminal.onOutput = output.write;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalView(terminal, autofocus: true)),
      ),
    );
    await tester.pump();
    await tester.pump();
    final state = tester.state<CustomTextEditState>(
      find.byType(CustomTextEdit),
    );
    // Count deletes at the onDelete level via the terminal's
    // backspace output: TerminalView emits \x7f per delete.
    typeByDeltas(state, 'ab');
    state.updateEditingValueWithDeltas([
      TextEditingDeltaDeletion(
        oldText: 'ab',
        deletedRange: const TextRange(start: 1, end: 2),
        selection: sel(1),
        composing: noComposing,
      ),
    ]);
    state.updateEditingValueWithDeltas([
      TextEditingDeltaDeletion(
        oldText: 'a',
        deletedRange: const TextRange(start: 0, end: 1),
        selection: sel(0),
        composing: noComposing,
      ),
    ]);
    await tester.pump();
    deletes = '\x7f'.allMatches(output.toString()).length;
    expect(output.toString(), 'ab\x7f\x7f');
    expect(deletes, 2);
  });

  testWidgets('deleting inside a composition emits nothing', (tester) async {
    final (state, output) = await pumpTerminal(tester);
    state.updateEditingValueWithDeltas([
      insert('', 'compose', 0, composing: const TextRange(start: 0, end: 7)),
    ]);
    state.updateEditingValueWithDeltas([
      TextEditingDeltaDeletion(
        oldText: 'compose',
        deletedRange: const TextRange(start: 6, end: 7),
        selection: sel(6),
        composing: const TextRange(start: 0, end: 6),
      ),
    ]);
    await tester.pump();
    expect(output.toString(), isEmpty);
    // Committing what remains forwards it exactly once.
    state.updateEditingValueWithDeltas([
      TextEditingDeltaNonTextUpdate(
        oldText: 'compos',
        selection: sel(6),
        composing: noComposing,
      ),
    ]);
    await tester.pump();
    expect(output.toString(), 'compos');
  });

  testWidgets('in-flight delta across the submit rebase is echo-guarded', (
    tester,
  ) async {
    final (state, output) = await pumpTerminal(tester);
    typeByDeltas(state, 'docker compose');
    // Enter arrives as an insertion of the newline: the line is
    // emitted and the adapter rebases to a fresh buffer.
    state.updateEditingValueWithDeltas([insert('docker compose', '\n', 14)]);
    await tester.pump();
    expect(output.toString(), 'docker compose\n');
    output.clear();
    // A delta generated BEFORE the rebase (its basis is the
    // submitted line) arrives late: folding rebuilds from its
    // own basis, and the echo guard strips the replayed line,
    // forwarding only the genuinely new character.
    state.updateEditingValueWithDeltas([insert('docker compose', 'x', 14)]);
    await tester.pump();
    expect(output.toString(), 'x');
  });
}
