import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextEdit extends StatefulWidget {
  /// Opt-in diagnostic sink (HeroTerm ADR-015). When non-null,
  /// the state reports input-connection lifecycle events, every
  /// editing-value update it receives, and everything it emits
  /// toward the terminal, one line per event. The host app wires
  /// this to a user-enabled log file; it is null (and completely
  /// inert) in normal use.
  static void Function(String line)? debugLog;

  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    // this.initEditingState = TextEditingValue.empty,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.newline,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
  });

  final Widget child;

  final void Function(String) onInsert;

  final void Function() onDelete;

  final void Function(String?) onComposing;

  final void Function(TextInputAction) onAction;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  final FocusNode focusNode;

  final bool autofocus;

  final bool readOnly;

  final TextInputType inputType;

  final TextInputAction inputAction;

  final Brightness keyboardAppearance;

  final bool deleteDetection;

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit>
    with TextInputClient, DeltaTextInputClient {
  TextInputConnection? _connection;

  void _dbg(String line) => CustomTextEdit.debugLog?.call(line);

  /// Escapes a string for a one-line diagnostic record.
  static String escapeForLog(String s, [int max = 160]) {
    final out = StringBuffer();
    for (final rune in s.runes) {
      if (out.length >= max) {
        out.write('…');
        break;
      }
      if (rune == 0x1b) {
        out.write(r'\e');
      } else if (rune == 0x7f) {
        out.write(r'\x7f');
      } else if (rune < 0x20) {
        out.write('\\x${rune.toRadixString(16).padLeft(2, '0')}');
      } else {
        out.write(String.fromCharCode(rune));
      }
    }
    return out.toString();
  }

  void _emitInsert(String text) {
    _dbg('EMIT insert "${escapeForLog(text)}"');
    widget.onInsert(text);
  }

  void _emitDelete() {
    _dbg('EMIT delete');
    widget.onDelete();
  }

  @override
  void initState() {
    widget.focusNode.addListener(_onFocusChange);
    _committedText = _committedPartOf(_currentEditingState);
    super.initState();
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else {
      if (oldWidget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    if (hasInputConnection) {
      _connection?.close();
    }
  }

  void setEditingState(TextEditingValue value) {
    _currentEditingState = value;
    _committedText = _committedPartOf(value);
    _connection?.setEditingState(value);
  }

  /// Resets the committed-text tracking to the initial state.
  ///
  /// HeroTerm local patch (ADR-014): the platform text buffer
  /// provably restarts at [_initEditingState] whenever a NEW input
  /// connection is opened (the previous one was closed when focus
  /// was lost) and when the platform closes the connection. The
  /// original patch never reset [_committedText] in those moments,
  /// so the next keystroke was diffed against the whole typing
  /// history of the previous buffer: characters that happened to
  /// match the history's prefix were swallowed, and a burst of
  /// backspaces as long as the history was sent into the shell —
  /// deleting whatever command the user was in the middle of
  /// typing (dropped characters, cursor jumping to the line start,
  /// commands split in two). Tracking must restart with the buffer.
  void _resetCommittedTracking() {
    _currentEditingState = _initEditingState;
    _committedText = _committedPartOf(_currentEditingState);
  }

  /// Restarts the platform buffer now that a line has been
  /// submitted (ADR-017).
  ///
  /// ADR-014/015 left the buffer accumulating for the whole input
  /// connection, so by the time the user had typed a few commands
  /// the diff baseline was hundreds of characters of history and
  /// every platform buffer restart/replay diverged against all of
  /// it. A submitted line is a natural boundary — the shell has
  /// consumed the text and is about to print a fresh prompt — so
  /// the buffer restarts there instead: setEditingState is called
  /// once per command, at a moment when no composition can be in
  /// flight (guarded by the caller), never mid-line like the word
  /// -boundary rebase ADR-015 withdrew. The diff baseline then
  /// only ever holds the line currently being typed.
  ///
  /// The submitted text is kept in [_echoGuard] so a late platform
  /// update replaying the just-submitted line (generated before
  /// the rebase, delivered after it) is recognised and neutralised
  /// instead of being re-typed at the fresh prompt.
  void _rebaseToFreshLine() {
    final submitted = _committedText;
    // The guard matches the line's text; the newline that
    // submitted it (when Enter arrived as text) is not part of
    // what a platform echo would replay as a prefix.
    var line = submitted;
    while (line.endsWith('\n') || line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    if (line.trim().isNotEmpty) {
      _echoGuard = line;
    }
    _resetCommittedTracking();
    _dbg('REBASE after submit (line ${submitted.length} chars)');
    if (hasInputConnection) {
      _connection!.setEditingState(_initEditingState);
    }
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    _connection?.setEditableSizeAndTransform(
      rect.size,
      Matrix4.translationValues(0, 0, 0),
    );

    _connection?.setCaretRect(caretRect);
  }

  void _onFocusChange() {
    _openOrCloseInputConnectionIfNeeded();
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (_currentEditingState.composing.isCollapsed) {
      return widget.onKeyEvent(focusNode, event);
    }

    return KeyEventResult.skipRemainingHandlers;
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!widget.focusNode.hasFocus) {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (hasInputConnection) {
      _dbg('CONN show (existing)');
      _connection!.show();
    } else {
      _dbg('CONN open (new)');
      // A fresh connection restarts the platform buffer at the
      // initial state; the diff tracking restarts with it (ADR-014).
      _echoGuard = null;
      _resetCommittedTracking();
      final config = TextInputConfiguration(
        inputType: widget.inputType,
        inputAction: widget.inputAction,
        keyboardAppearance: widget.keyboardAppearance,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        // HeroTerm (ADR-020): receive granular deltas instead of
        // full snapshots wherever the platform supports them.
        enableDeltaModel: true,
      );

      _connection = TextInput.attach(this, config);

      _connection!.show();

      // setEditableRect(Rect.zero, Rect.zero);

      _connection!.setEditingState(_initEditingState);
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_connection != null && _connection!.attached) {
      _dbg('CONN close');
      _connection!.close();
      _connection = null;
    }
  }

  TextEditingValue get _initEditingState => widget.deleteDetection
      ? const TextEditingValue(
          text: '  ',
          selection: TextSelection.collapsed(offset: 2),
        )
      : const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );

  late var _currentEditingState = _initEditingState.copyWith();

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null;
  }

  /// The portion of the platform editing text that has already been
  /// forwarded to the terminal (the text outside any composing
  /// region). HeroTerm local patch — see VENDORED.md.
  String _committedText = '';

  /// The text of the line most recently submitted with Enter,
  /// remembered across the post-submit rebase (ADR-017). A platform
  /// update that replays exactly this text (or carries it as a
  /// prefix, coalesced with fresh typing) is a late echo of the
  /// submitted line, not new input: it is swallowed/stripped once.
  String? _echoGuard;

  String _committedPartOf(TextEditingValue value) {
    final composing = value.composing;
    if (composing.isCollapsed || !composing.isValid) return value.text;
    return value.text.replaceRange(composing.start, composing.end, '');
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _dbg(
      'UEV text="${escapeForLog(value.text)}" '
      'comp=${value.composing.start},${value.composing.end} '
      'sel=${value.selection.baseOffset},${value.selection.extentOffset} '
      'oldLen=${_committedText.length}',
    );
    _processEditingValue(value);
  }

  /// Granular input updates (HeroTerm ADR-020).
  ///
  /// With [TextInputConfiguration.enableDeltaModel] the platform
  /// narrates each edit — insert this, delete that range, replace
  /// that range — instead of sending a fresh snapshot of the
  /// whole buffer for the client to diff. The snapshot stream is
  /// what desynchronised for five rounds of typing bugs
  /// (ADR-014..018): restarts, replays and phantom values all had
  /// to be guessed about from two snapshots. A delta carries its
  /// own basis ([TextEditingDelta.oldText]) and
  /// [TextEditingDelta.apply] rebuilds the new value from that
  /// basis (last-write-wins), so folding the deltas into the
  /// shadow value below self-heals any drift by construction —
  /// there is no independent platform history left to reconcile.
  /// The folded value then goes through the same processing as a
  /// classic update, whose guards (composing hold, phantom and
  /// restart handling, echo guard) remain as the safety net for
  /// platforms that still deliver classic updates: those keep
  /// arriving through [updateEditingValue] unchanged.
  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    var value = _currentEditingState;
    for (final delta in deltas) {
      _dbg(
        'DELTA ${_describeDelta(delta)} '
        'basis=${delta.oldText == value.text ? 'ok' : 'resync'}',
      );
      value = delta.apply(value);
    }
    _processEditingValue(value);
  }

  String _describeDelta(TextEditingDelta delta) {
    return switch (delta) {
      TextEditingDeltaInsertion d =>
        'insert "${escapeForLog(d.textInserted)}" @${d.insertionOffset} '
            'comp=${d.composing.start},${d.composing.end}',
      TextEditingDeltaDeletion d =>
        'delete ${d.deletedRange.start},${d.deletedRange.end} '
            'comp=${d.composing.start},${d.composing.end}',
      TextEditingDeltaReplacement d =>
        'replace ${d.replacedRange.start},${d.replacedRange.end} '
            'with "${escapeForLog(d.replacementText)}" '
            'comp=${d.composing.start},${d.composing.end}',
      TextEditingDeltaNonTextUpdate d =>
        'nontext sel=${d.selection.baseOffset},${d.selection.extentOffset} '
            'comp=${d.composing.start},${d.composing.end}',
      _ => '${delta.runtimeType}',
    };
  }

  void _processEditingValue(TextEditingValue value) {
    // Echo guard (ADR-017): after a line is submitted, the buffer
    // is rebased to empty — but the platform may still deliver an
    // update it generated BEFORE the rebase, replaying the
    // submitted line. Re-typing it at the fresh prompt would
    // duplicate the command, so an exact replay is swallowed and
    // a replay coalesced with fresh typing has the submitted
    // prefix stripped; any other value expires the guard.
    var effectiveValue = value;
    final guard = _echoGuard;
    if (guard != null) {
      final committedPart = _committedPartOf(effectiveValue);
      if (committedPart == guard) {
        _echoGuard = null;
        _dbg('ECHO swallowed (replay of the submitted line)');
        _currentEditingState = effectiveValue;
        return;
      }
      if (guard.isNotEmpty &&
          committedPart.startsWith(guard) &&
          effectiveValue.composing.isCollapsed) {
        final rest = committedPart.substring(guard.length);
        _echoGuard = null;
        _dbg('ECHO prefix stripped, remainder "${escapeForLog(rest)}"');
        effectiveValue = TextEditingValue(
          text: rest,
          selection: TextSelection.collapsed(offset: rest.length),
        );
      } else {
        _echoGuard = null;
      }
    }
    _currentEditingState = effectiveValue;
    value = effectiveValue;

    final composing = value.composing;
    final composingActive = composing.isValid && !composing.isCollapsed;

    // While the IME is composing, only update the preview. The
    // composing characters are provisional and must not reach the
    // terminal yet.
    if (composingActive) {
      widget.onComposing(composing.textInside(value.text));
    } else {
      widget.onComposing(null);
    }

    // Forward only the difference between the previously committed
    // text and the newly committed text.
    //
    // The upstream implementation instead inserted the full text on
    // every commit and then reset the platform editing state to
    // empty. The reset destroyed the input method's internal state:
    // with Vietnamese Telex, for example, the toggle sequence
    // (w -> ư, w again -> w) restarted at every keystroke, and the
    // re-sent commits produced duplicated characters (ưư). Diffing
    // committed snapshots keeps the platform state intact so IM
    // state machines survive across keystrokes, and makes re-sent
    // identical values a no-op.
    //
    // While composition is active, the text before the composing
    // range is committed and stable; the previously committed tail
    // that the composing range now covers is "in flux" (the IM may
    // have taken it back for revision) and must not be deleted —
    // those characters were already sent to the terminal and can
    // only be revised when the composition actually commits.
    final visibleCommitted =
        composingActive ? value.text.substring(0, composing.start) : value.text;

    if (composingActive) {
      if (visibleCommitted.startsWith(_committedText)) {
        final inserted = visibleCommitted.substring(_committedText.length);
        if (inserted.isNotEmpty) {
          _committedText = visibleCommitted;
          _emitInsert(inserted);
        }
      }
      // Otherwise the difference is inside/behind the composing
      // range: hold until the composition resolves.
      return;
    }

    final newCommitted = visibleCommitted;
    if (newCommitted == _committedText) return;

    final oldText = _committedText;

    // Fast path: a pure append — the overwhelmingly common case
    // while typing.
    if (newCommitted.startsWith(oldText)) {
      _committedText = newCommitted;
      final inserted = newCommitted.substring(oldText.length);
      _emitInsert(inserted);
      if (inserted.contains('\n') || inserted.contains('\r')) {
        _rebaseToFreshLine();
      }
      return;
    }

    // A snapshot that is suddenly EMPTY while a line is on screen
    // is never a keystroke (ADR-017): emptying the buffer takes
    // one update per backspace, so a multi-character drop to ""
    // in a single update is a phantom/restart artefact. Emitting
    // it as backspaces wiped the shell line the user was typing
    // (the reported "cursor jumps to the start of the line").
    // Ignore it entirely — baseline and shell stay as they are,
    // and the next genuine update resolves from a known state.
    // (A one-character baseline still falls through: "" after "a"
    // is the final backspace of a line being deleted.)
    if (newCommitted.isEmpty && oldText.runes.length > 1) {
      _dbg('PHANTOM empty snapshot ignored');
      return;
    }

    // Prefix/suffix decomposition of the divergence.
    var start = 0;
    final maxPrefix = oldText.length < newCommitted.length
        ? oldText.length
        : newCommitted.length;
    while (start < maxPrefix &&
        oldText.codeUnitAt(start) == newCommitted.codeUnitAt(start)) {
      start++;
    }
    var oldEnd = oldText.length;
    var newEnd = newCommitted.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText.codeUnitAt(oldEnd - 1) == newCommitted.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }

    final removedRunes = oldText.substring(start, oldEnd).runes.length;
    final inserted = newCommitted.substring(start, newEnd);
    final isPureShrink = start == newCommitted.length;
    final prefixRunes = oldText.substring(0, start).runes.length;
    final oldRunes = oldText.runes.length;

    // RESTART (ADR-017): the divergence reaches deep into text
    // that was already sent — the common prefix is far from the
    // tail, or nothing at all is shared while several characters
    // would have to be "removed". No single keystroke does that:
    // genuine edits (backspace, an IME's final correction) only
    // ever touch the tail. What actually happened is that the
    // platform restarted its buffer mid-connection and the new
    // snapshot holds just what the user typed since — restarting
    // is invisible to us because the connection never closed.
    // ADR-014/015 resynced silently here and SWALLOWED those
    // characters (the "first letter of the command breaks"
    // report). The invariant that matters is that the shell
    // receives exactly the keystrokes, in order: forward the new
    // snapshot as fresh input, delete nothing, and adopt it as
    // the baseline.
    if (!isPureShrink &&
        (prefixRunes < oldRunes - _maxTakeBackRunes ||
            (start == 0 && removedRunes >= 3))) {
      _committedText = newCommitted;
      _dbg('RESTART snapshot forwarded as new input');
      if (newCommitted.isNotEmpty) {
        _emitInsert(newCommitted);
      }
      if (newCommitted.contains('\n') || newCommitted.contains('\r')) {
        _rebaseToFreshLine();
      }
      return;
    }

    // Anything else edits the tail of what was already sent: a
    // small shrink or revision near the end (an IME's final
    // correction, a deleted character). Only a SHORT take-back is
    // applied, by deleting the diverged tail and inserting its
    // replacement.
    //
    // A LARGE pure shrink cannot be a keystroke-level edit either
    // (ADR-014): emitting one backspace per removed character
    // flooded the shell and wiped the line being typed. But it is
    // not automatically a shrink at all (ADR-017): when the
    // surviving snapshot is SHORT, it is the first snapshot of a
    // restarted buffer holding just what the user typed — the
    // restart above excluded pure shrinks, and a one-character
    // restart whose character happens to match the line's first
    // character lands here ('d' after a long 'docker ...' line).
    // Forward it as new input. A LONG surviving prefix, instead,
    // can only be a replay or a coalesced backspace burst: adopt
    // it silently — the shell already shows that text, and adding
    // anything would duplicate it.
    _committedText = newCommitted;
    if (removedRunes > _maxTakeBackRunes) {
      if (newCommitted.isNotEmpty &&
          newCommitted.runes.length <= _maxTakeBackRunes) {
        _dbg('RESTART (shrink-shaped) snapshot forwarded as new input');
        _emitInsert(newCommitted);
        if (newCommitted.contains('\n') || newCommitted.contains('\r')) {
          _rebaseToFreshLine();
        }
      }
      return;
    }
    for (var i = 0; i < removedRunes; i++) {
      _emitDelete();
    }
    if (inserted.isNotEmpty) {
      _emitInsert(inserted);
      if (inserted.contains('\n') || inserted.contains('\r')) {
        _rebaseToFreshLine();
      }
    }

    // Deliberately do NOT reset the platform editing state on
    // every commit (that is what broke stateful IMEs upstream).
    // The buffer restarts only at line submission (ADR-017), so
    // it never grows past the current command line; the take-back
    // bound above caps the damage any single desync can do.
  }

  /// The largest take-back (in runes) the diff path will emit as
  /// backspaces. A Vietnamese syllable is at most ~7 runes, so 8
  /// covers legitimate IME corrections while making a backspace
  /// flood impossible (ADR-014).
  static const _maxTakeBackRunes = 8;

  @override
  void performAction(TextInputAction action) {
    _dbg('ACTION $action');
    widget.onAction(action);
    // Submitting the line ends this buffer's useful life
    // (ADR-017). Only when no composition is in flight — Enter
    // during an active composition commits it first, and that
    // commit arrives as its own update before this action.
    if (_currentEditingState.composing.isCollapsed) {
      _rebaseToFreshLine();
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // print('updateFloatingCursor $point');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // print('showAutocorrectionPromptRect');
  }

  @override
  void connectionClosed() {
    _dbg('CONN closed-by-platform');
    // The platform buffer is gone; the next connection starts
    // from the initial state, and so does the tracking (ADR-014).
    _echoGuard = null;
    _resetCommittedTracking();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // print('performPrivateCommand $action');
  }

  @override
  void insertTextPlaceholder(Size size) {
    // print('insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    // print('removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    // print('showToolbar');
  }
}
