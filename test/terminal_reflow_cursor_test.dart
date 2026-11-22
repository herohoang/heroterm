import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Regression tests for ADR-018: the vendored buffer's resize
/// reflowed wrapped lines but only CLAMPED the cursor, leaving it
/// pointing at the wrong line/cell. The shell's SIGWINCH redraw
/// (`\r`, erase, reprint) then landed on the wrong row —
/// duplicated prompt lines and a cursor stranded at a line start
/// with the typed line intact, in the middle of ordinary typing.
///
/// The byte streams below are the ones a real bash/readline emits
/// (captured from a pty): plain appends while typing, and the
/// redraw `\r\x1b[K\r<prompt+text>` after a size change.
void main() {
  const prompt = 'root@host:/var/www/html/bigsale.pro/staging# ';

  String logicalLine(Terminal t, int start) {
    // In this buffer, isWrapped marks a line as the CONTINUATION
    // of the previous one, so a logical line extends while the
    // NEXT line carries the flag.
    final out = StringBuffer();
    var i = start;
    while (true) {
      out.write(t.buffer.lines[i].toString().trimRight());
      if (i + 1 >= t.buffer.lines.length ||
          !t.buffer.lines[i + 1].isWrapped) {
        break;
      }
      i++;
    }
    return out.toString();
  }

  int nonEmptyLines(Terminal t) {
    var n = 0;
    for (var i = 0; i < t.buffer.lines.length; i++) {
      if (t.buffer.lines[i].toString().trim().isNotEmpty) n++;
    }
    return n;
  }

  test('growing the width keeps the cursor on its cell, and the '
      'shell redraw lands on the same row', () {
    final t = Terminal(maxLines: 100);
    t.resize(40, 24, 400, 480);
    t.write(
      '$prompt'
      'docker co',
    ); // 54 cells: wraps at 40
    expect(t.buffer.cursorX, 14);
    expect(t.buffer.cursorY, 1);

    t.resize(80, 24, 800, 480);
    // The logical line merged into row 0; the cursor must follow
    // its cell to (54, 0) — upstream left it at (14, 1), pointing
    // at an empty row.
    expect(t.buffer.cursorX, 54);
    expect(t.buffer.cursorY, 0);
    expect(
      logicalLine(t, 0),
      '$prompt'
      'docker co',
    );

    // bash's redraw after SIGWINCH, then the rest of the word.
    t.write(
      '\r\x1b[K\r$prompt'
      'docker co',
    );
    t.write('mpose');
    expect(
      logicalLine(t, 0),
      '$prompt'
      'docker compose',
    );
    expect(t.buffer.cursorX, 59);
    expect(t.buffer.cursorY, 0);
    expect(nonEmptyLines(t), 1); // no duplicated prompt line
  });

  test('shrinking the width keeps the cursor on its cell', () {
    final t = Terminal(maxLines: 100);
    t.resize(80, 24, 800, 480);
    t.write(
      '$prompt'
      'docker compose',
    ); // 59 cells, no wrap
    expect(t.buffer.cursorX, 59);
    expect(t.buffer.cursorY, 0);

    t.resize(50, 24, 500, 480);
    // 59 cells at width 50: the cursor's cell is the last cell of
    // the second segment — (9, absolute row 1). Upstream clamped
    // the cursor to (49, 0), inside the text of the first
    // segment, so the shell's redraw compounded from there.
    expect(t.buffer.cursorX, 9);
    expect(t.buffer.absoluteCursorY, 1);
    // The full logical line survives across the two segments.
    expect(
      logicalLine(t, 0),
      '$prompt'
      'docker compose',
    );
  });

  test('a resize without wrapped content leaves the cursor put', () {
    final t = Terminal(maxLines: 100);
    t.resize(80, 24, 800, 480);
    t.write('hello');
    t.resize(100, 24, 1000, 480);
    expect(t.buffer.cursorX, 5);
    expect(t.buffer.cursorY, 0);
    expect(logicalLine(t, 0), 'hello');
  });
}
