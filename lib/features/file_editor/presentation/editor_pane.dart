import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_actions.dart';
import 'editor_controller.dart';
import 'highlighting.dart';

const _editorTextStyle = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['SF Mono', 'Consolas', 'Courier New', 'monospace'],
  fontSize: 13,
  height: 1.45,
);

/// All open documents kept mounted in an [IndexedStack] so
/// switching between file tabs preserves scroll, selection, undo
/// history and find state (the same pattern as terminal tabs).
final class EditorSurface extends ConsumerWidget {
  const EditorSurface({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final docs = state.documents;
    if (docs.isEmpty) return const SizedBox.shrink();
    var index = docs.indexWhere((d) => d.id == state.activeDocumentId);
    if (index < 0) index = 0;
    return IndexedStack(
      index: index,
      children: [
        for (final doc in docs)
          doc.kind == EditorDocKind.builtin
              ? EditorPane(key: ValueKey('editor-${doc.id}'), docId: doc.id)
              : ExternalDocPane(
                  key: ValueKey('editor-${doc.id}'),
                  docId: doc.id,
                ),
      ],
    );
  }
}

/// The built-in editor for one document (Edit File spec §2.2):
/// header with path + status, find/replace bar, line-number
/// gutter, and a highlighting text field with undo/redo.
final class EditorPane extends ConsumerStatefulWidget {
  const EditorPane({super.key, required this.docId});

  final String docId;

  @override
  ConsumerState<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends ConsumerState<EditorPane> {
  final _textScroll = ScrollController();
  final _gutterScroll = ScrollController();
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final _editorFocus = FocusNode();
  bool _findVisible = false;
  int _currentMatch = -1;
  bool _syncingScroll = false;

  @override
  void initState() {
    super.initState();
    _textScroll.addListener(() {
      if (_syncingScroll || !_gutterScroll.hasClients) return;
      _syncingScroll = true;
      _gutterScroll.jumpTo(_textScroll.offset);
      _syncingScroll = false;
    });
  }

  @override
  void dispose() {
    _textScroll.dispose();
    _gutterScroll.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  EditorDocument? get _doc => ref.read(editorProvider).docById(widget.docId);

  HighlightingController? get _highlight {
    final controller = _doc?.textController;
    return controller is HighlightingController ? controller : null;
  }

  List<int> _matches() {
    final doc = _doc;
    final query = _findController.text;
    if (doc == null || query.isEmpty) return const [];
    final text = doc.textController!.text.toLowerCase();
    final needle = query.toLowerCase();
    final result = <int>[];
    var from = 0;
    while (true) {
      final hit = text.indexOf(needle, from);
      if (hit < 0) break;
      result.add(hit);
      from = hit + 1;
    }
    return result;
  }

  void _goToMatch(int index) {
    final doc = _doc;
    final matches = _matches();
    if (doc == null || matches.isEmpty) return;
    final wrapped =
        ((index % matches.length) + matches.length) % matches.length;
    _currentMatch = wrapped;
    final controller = doc.textController!;
    final start = matches[wrapped];
    controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + _findController.text.length,
    );
    _editorFocus.requestFocus();
    setState(() {});
  }

  void _onQueryChanged(String query) {
    final highlight = _highlight;
    if (highlight != null) {
      highlight.searchQuery = query;
      highlight.refreshSpans();
    }
    _currentMatch = -1;
    setState(() {});
    if (query.isNotEmpty) _goToMatch(0);
  }

  void _replaceCurrent() {
    final doc = _doc;
    final query = _findController.text;
    if (doc == null || query.isEmpty) return;
    final controller = doc.textController!;
    final selection = controller.selection;
    final text = controller.text;
    if (selection.isCollapsed ||
        selection.start < 0 ||
        text.substring(selection.start, selection.end).toLowerCase() !=
            query.toLowerCase()) {
      _goToMatch(_currentMatch < 0 ? 0 : _currentMatch);
      return;
    }
    final replacement = _replaceController.text;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
    );
    setState(() {});
    _goToMatch(_currentMatch);
  }

  void _replaceAll() {
    final doc = _doc;
    final query = _findController.text;
    if (doc == null || query.isEmpty) return;
    final controller = doc.textController!;
    final text = controller.text;
    final lower = text.toLowerCase();
    final needle = query.toLowerCase();
    final replacement = _replaceController.text;
    final out = StringBuffer();
    var from = 0;
    var count = 0;
    while (true) {
      final hit = lower.indexOf(needle, from);
      if (hit < 0) {
        out.write(text.substring(from));
        break;
      }
      out.write(text.substring(from, hit));
      out.write(replacement);
      from = hit + query.length;
      count++;
    }
    if (count == 0) return;
    controller.value = TextEditingValue(
      text: out.toString(),
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Replaced $count occurrence(s).')));
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(editorProvider).docById(widget.docId);
    if (doc == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(saveDocumentWithFlow(context, ref, doc.id)),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(saveDocumentWithFlow(context, ref, doc.id)),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            setState(() => _findVisible = true),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _findVisible = true),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
            unawaited(closeDocumentWithGuard(context, ref, doc.id)),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
            unawaited(closeDocumentWithGuard(context, ref, doc.id)),
      },
      child: Material(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, doc),
            if (_findVisible) _findBar(context, doc),
            if (doc.errorMessage != null)
              Container(
                color: theme.colorScheme.errorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  doc.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            const Divider(height: 1),
            Expanded(child: _body(context, doc)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, EditorDocument doc) {
    final theme = Theme.of(context);
    final status = doc.isLoading
        ? 'Loading…'
        : doc.isSaving
        ? 'Saving…'
        : doc.errorMessage != null
        ? 'Save failed — changes kept'
        : doc.isDirty
        ? 'Unsaved changes'
        : 'Saved';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 17),
          const SizedBox(width: 8),
          Text(
            doc.fileName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (doc.isDirty)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.circle, size: 8, color: Colors.orange),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Tooltip(
              message: '${doc.remotePath} — ${doc.profileName}',
              child: Text(
                doc.remotePath,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: doc.errorMessage != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 6),
          ListenableBuilder(
            listenable: doc.undoController!,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('editor-undo-${doc.id}'),
                  icon: const Icon(Icons.undo, size: 18),
                  tooltip: 'Undo (⌘Z)',
                  onPressed: doc.undoController!.value.canUndo
                      ? () => doc.undoController!.undo()
                      : null,
                ),
                IconButton(
                  key: Key('editor-redo-${doc.id}'),
                  icon: const Icon(Icons.redo, size: 18),
                  tooltip: 'Redo (⌘⇧Z)',
                  onPressed: doc.undoController!.value.canRedo
                      ? () => doc.undoController!.redo()
                      : null,
                ),
              ],
            ),
          ),
          TextButton.icon(
            key: Key('editor-save-${doc.id}'),
            onPressed: doc.isDirty && !doc.isSaving
                ? () => unawaited(saveDocumentWithFlow(context, ref, doc.id))
                : null,
            icon: const Icon(Icons.save_outlined, size: 17),
            label: const Text('Save'),
          ),
          IconButton(
            key: Key('editor-find-${doc.id}'),
            icon: const Icon(Icons.search, size: 19),
            tooltip: 'Find & Replace (⌘F)',
            onPressed: () => setState(() => _findVisible = !_findVisible),
          ),
          IconButton(
            key: Key('editor-close-${doc.id}'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close file',
            onPressed: () =>
                unawaited(closeDocumentWithGuard(context, ref, doc.id)),
          ),
        ],
      ),
    );
  }

  Widget _findBar(BuildContext context, EditorDocument doc) {
    final matches = _matches();
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 190,
            child: TextField(
              key: Key('editor-find-field-${doc.id}'),
              controller: _findController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Find',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _goToMatch(_currentMatch + 1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _findController.text.isEmpty
                ? ''
                : matches.isEmpty
                ? 'No results'
                : '${_currentMatch + 1} / ${matches.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 19),
            tooltip: 'Previous',
            onPressed: matches.isEmpty
                ? null
                : () => _goToMatch(_currentMatch - 1),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 19),
            tooltip: 'Next',
            onPressed: matches.isEmpty
                ? null
                : () => _goToMatch(_currentMatch + 1),
          ),
          SizedBox(
            width: 190,
            child: TextField(
              key: Key('editor-replace-field-${doc.id}'),
              controller: _replaceController,
              decoration: const InputDecoration(
                hintText: 'Replace',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          TextButton(onPressed: _replaceCurrent, child: const Text('Replace')),
          TextButton(onPressed: _replaceAll, child: const Text('Replace All')),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close find',
            onPressed: () {
              final highlight = _highlight;
              if (highlight != null) {
                highlight.searchQuery = '';
                highlight.refreshSpans();
              }
              setState(() => _findVisible = false);
            },
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, EditorDocument doc) {
    final theme = Theme.of(context);
    final controller = doc.textController!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Line-number gutter, scroll-synced with the text.
        Container(
          color: theme.colorScheme.surfaceContainerLow,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final lines = '\n'.allMatches(value.text).length + 1;
              final digits = '$lines'.length;
              return SizedBox(
                width: digits * 9 + 18,
                child: SingleChildScrollView(
                  controller: _gutterScroll,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 8, 24),
                    child: Text(
                      [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
                      textAlign: TextAlign.right,
                      style: _editorTextStyle.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      strutStyle: StrutStyle.fromTextStyle(
                        _editorTextStyle,
                        forceStrutHeight: true,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: doc.isLoading
              ? const Center(child: CircularProgressIndicator())
              : TextField(
                  key: Key('editor-text-${doc.id}'),
                  controller: controller,
                  undoController: doc.undoController,
                  focusNode: _editorFocus,
                  scrollController: _textScroll,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: _editorTextStyle,
                  strutStyle: StrutStyle.fromTextStyle(
                    _editorTextStyle,
                    forceStrutHeight: true,
                  ),
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 24),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Status pane for an externally edited document (§2.3): shows
/// the temp copy, the sync state, and the actions to relaunch,
/// sync, or close the session.
final class ExternalDocPane extends ConsumerWidget {
  const ExternalDocPane({super.key, required this.docId});

  final String docId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(editorProvider).docById(docId);
    if (doc == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (statusText, statusColor) = switch (doc.syncState) {
      ExternalSyncState.watching => (
        doc.isSaving ? 'Syncing…' : 'In sync — watching for changes',
        null,
      ),
      ExternalSyncState.changed => (
        'Changes are waiting to sync',
        Colors.orange,
      ),
      ExternalSyncState.syncing => ('Syncing…', null),
      ExternalSyncState.error => (
        'Sync failed — the local copy is kept',
        theme.colorScheme.error,
      ),
    };
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                const Icon(Icons.open_in_new, size: 17),
                const SizedBox(width: 8),
                Text(
                  doc.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Chip(
                  label: Text('External editor'),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    doc.remotePath,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                IconButton(
                  key: Key('editor-close-${doc.id}'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close session',
                  onPressed: () =>
                      unawaited(closeDocumentWithGuard(context, ref, doc.id)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                      if (doc.errorMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          doc.errorMessage!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'This file is being edited in an external '
                        'application. HeroTerm downloaded it to a '
                        'private temporary copy and uploads changes '
                        'back to ${doc.profileName} when the file '
                        'settles after a save.',
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        'Temporary copy: ${doc.localPath}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (doc.lastSyncedAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Last synced: ${doc.lastSyncedAt!.toLocal()}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        children: [
                          FilledButton.icon(
                            key: Key('external-relaunch-${doc.id}'),
                            onPressed: () => unawaited(
                              ref
                                  .read(editorProvider.notifier)
                                  .relaunchExternal(doc.id),
                            ),
                            icon: const Icon(Icons.open_in_new, size: 17),
                            label: const Text('Open in external app'),
                          ),
                          OutlinedButton.icon(
                            key: Key('external-sync-${doc.id}'),
                            onPressed: doc.hasUnsyncedChanges
                                ? () => unawaited(
                                    saveDocumentWithFlow(context, ref, doc.id),
                                  )
                                : null,
                            icon: const Icon(Icons.sync, size: 17),
                            label: const Text('Sync now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
