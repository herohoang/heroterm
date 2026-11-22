# Vendored: xterm 4.0.0

This is a vendored copy of the `xterm` package, version 4.0.0
(MIT license, see `LICENSE`), taken from pub.dev because HeroTerm
carries local patches that have not landed upstream.

## Local patch

**File:** `lib/src/ui/custom_text_edit.dart`

Upstream `updateEditingValue` inserted the full editing text on
every IME commit and then reset the platform editing state to
empty. The reset destroys the input method's internal state, which
breaks IMEs that carry state across keystrokes. Reproduced with
Vietnamese Telex on macOS: typing `w` composes `ư`, typing `w`
again should toggle back to `w`, but the restarted IM produced a
second `ư` — the terminal received `ưư`.

The patch forwards only the diff between committed text snapshots
(the composing region is excluded while composition is active) and
never resets the platform editing state. Re-sent identical values
are no-ops.

Covered by `test/terminal_ime_test.dart` in the app repository.

## Upgrading

When upgrading the upstream package, re-apply this patch if the
same `updateEditingValue` implementation is still present, then
re-run the IME regression tests.

## Patch addendum (ADR-014, 2026-10-26): desync hardening

User report from macOS: while typing ordinary commands,
characters were dropped, the cursor jumped to the line start,
text overlapped, and commands were split mid-word (e.g.
`docker compose build queue` executed, then `-worker` ran as its
own command). Root cause: the ADR-009 patch tracked the committed
text but never resynced that tracking when the platform text
buffer restarted. A fresh input connection (opened every time the
terminal regains focus) restarts the buffer at the initial empty
state, while `_committedText` still held the whole typing
history — the next keystroke diffed against that history,
swallowing any prefix-matching character and emitting a burst of
backspaces as long as the history, which deleted the shell's
current input line.

Additions on top of the ADR-009 patch, same file:

- `_resetCommittedTracking()` runs when a NEW input connection is
  opened and on `connectionClosed()`; `setEditingState` keeps the
  tracking in sync with the value it pushes.
- Divergences larger than 8 runes are treated as a resync (adopt
  the new snapshot, emit nothing) instead of a backspace flood; a
  Vietnamese syllable is ≤ ~7 runes, so legitimate IME
  corrections still go through the diff path.
- `_rebaseIfLong`: once the committed buffer passes 128 chars,
  the next word boundary (space/newline, no composition active)
  rebases the platform buffer to empty — bounding diff cost and
  desync blast radius without resetting mid-word (which is what
  broke Telex upstream).

Covered by the ADR-014 regression tests in
`test/terminal_ime_test.dart` (focus round-trip, large-divergence
resync, long-buffer rebase) alongside the ADR-009 tests.

## Patch addendum (ADR-015, 2026-10-26)

The ADR-014 word-boundary rebase was withdrawn: the corruption
persisted on macOS, and the rebase was the only remaining
mid-session `setEditingState` call — itself a suspect. Added
instead: an opt-in `CustomTextEdit.debugLog` sink (null and
inert by default) reporting connection lifecycle, every
`updateEditingValue`, emitted inserts/deletes and actions, plus
a `CustomTextEditState.escapeForLog` helper; `lib/ui.dart` now
exports this file so the host app can wire the sink.

## Patch addendum (ADR-017, 2026-11-08): lossless restarts, per-line buffer

The release build still corrupted typing (`docker compose`:
cursor to line start) while debug runs did not; the ADR-015 log
was never captured, so this round removes the lossy paths
instead of chasing the trigger. Same file:

- A divergence reaching deep into already-sent text is a
  **platform buffer restart**: the new snapshot is forwarded
  whole as fresh input (ADR-014/015 adopted it silently and
  swallowed the retyped characters). A large shrink to a short
  surviving snapshot is treated the same; a large shrink to a
  long prefix still resyncs silently.
- A snapshot dropping a multi-character baseline to `""` in one
  update is a phantom: ignored entirely (it previously emitted
  one backspace per character and wiped short lines).
- The platform buffer is **rebased at line submission**
  (`performAction`, or an emitted insert containing a newline):
  `setEditingState` once per command, composition never in
  flight — the baseline only ever holds the current line. The
  submitted text is kept as an **echo guard**: a late replay of
  the line is swallowed, or stripped when coalesced with fresh
  typing.

Covered by the ADR-017 tests in `test/terminal_ime_test.dart`.

## Patch addendum (ADR-018, 2026-11-08): cursor anchored across reflow

**File:** `lib/src/core/buffer/buffer.dart`

`Buffer.resize` reflowed wrapped lines on a width change but
only clamped the cursor into the new bounds (once midway,
before the reflow), so the cursor ended up pointing at the
wrong line/cell while the shell kept redrawing at the true
position: redraws landed on the wrong row (duplicated prompt
lines) and the visible cursor was stranded at a line start with
the typed line intact. `resize` now captures a `CellAnchor` at
the cursor before any adjustment and restores the cursor from
the anchor's reparented position after `lines.replaceWith` —
the reflow engine already reparents anchors; the cursor just
never used one. Falls back to the upstream clamp when no anchor
can be captured. Covered by
`test/terminal_reflow_cursor_test.dart` in the app repository,
which drives the terminal with byte streams captured from a
real bash/readline pty session.

## Patch addendum (ADR-020, 2026-11-08): delta input model

**File:** `lib/src/ui/custom_text_edit.dart`

`CustomTextEditState` additionally implements
`DeltaTextInputClient` and the input connection is opened with
`enableDeltaModel: true`. Platforms that support it now send
granular `TextEditingDelta`s (insert/delete/replace/non-text)
instead of full editing-value snapshots; the state folds them
into its shadow value via `TextEditingDelta.apply` (each delta
rebuilds from its own `oldText` basis, so drift self-heals)
and feeds the result through the same processing core as the
classic `updateEditingValue`, which remains as the fallback
for snapshot-delivering platforms. This retires the
snapshot-diff as the primary input model — the layer behind
the ADR-014..018 typing-corruption rounds — while keeping its
guards as the safety net. Covered by
`test/terminal_delta_input_test.dart` in the app repository.

## Patch addendum (ADR-024, 2026-11-20): keyword highlighting

New file `lib/src/ui/highlight.dart` (rules, matcher,
`TerminalHighlighter` cache) plus three surgical changes:
`TerminalPainter` consults the highlighter in `paintLine` and
takes an optional rule in `paintCell`/`paintCellForeground`
(highlight colour + underline join the paragraph cache key);
`RenderTerminal` gains a `highlightingEnabled` property and
passes `highlight: enabled && !buffer.isAltBuffer` per line;
`TerminalView`/`_TerminalView` gain the `highlightingEnabled`
widget property (default true). On an upstream upgrade, the
painter/render changes are the only hunks to re-apply — the
matcher file carries over as-is.
