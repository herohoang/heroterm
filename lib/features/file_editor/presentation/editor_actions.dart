import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_preferences.dart';
import '../../remote_explorer/domain/remote_entry.dart';
import 'file_editor_settings.dart';
import '../../connection/presentation/terminal_sessions.dart';
import 'editor_controller.dart';

/// UI-level orchestration for the editor flows that need dialogs
/// (Edit File spec §2.4/§2.5/§4): the controller stays
/// dialog-free; everything that asks the user lives here.

/// Opens [entry] in the built-in editor using the active
/// terminal tab's connection; shows a dialog on failure.
Future<void> openInBuiltinEditor(
  BuildContext context,
  WidgetRef ref,
  RemoteEntry entry,
) async {
  final tab = ref.read(sessionManagerProvider).activeTab;
  if (tab == null) return;
  final error = await ref
      .read(editorProvider.notifier)
      .openFile(tabId: tab.id, profile: tab.profile, entry: entry);
  if (error != null && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot open file'),
        content: Text(error.userMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// The full save flow for a built-in document: optional
/// before-save confirmation (Smart Save may exempt the file),
/// the save itself, and the conflict dialog when the remote file
/// changed underneath (§4). Returns true when the document is
/// saved (or was already clean).
Future<bool> saveDocumentWithFlow(
  BuildContext context,
  WidgetRef ref,
  String docId,
) async {
  final notifier = ref.read(editorProvider.notifier);
  final doc = ref.read(editorProvider).docById(docId);
  if (doc == null) return false;
  if (doc.kind == EditorDocKind.external) {
    final (outcome, _) = await notifier.syncExternal(docId);
    return outcome == SaveOutcome.saved;
  }
  if (!doc.isDirty) return true;

  if (notifier.saveNeedsConfirmation(doc)) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save file?'),
        content: Text(
          'Upload the changes to ${doc.remotePath} on '
          '${doc.profileName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-save-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }

  var (outcome, _) = await notifier.save(docId);
  if (outcome == SaveOutcome.conflict && context.mounted) {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remote file changed'),
        content: Text(
          '${doc.remotePath} was modified on the server after you '
          'opened it. Overwriting would lose those changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('reload'),
            child: const Text('Reload remote'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('overwrite'),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    if (choice == 'overwrite') {
      (outcome, _) = await notifier.save(docId, force: true);
    } else if (choice == 'reload') {
      final error = await notifier.reload(docId);
      return error == null;
    }
  }
  return outcome == SaveOutcome.saved;
}

/// Closes a document honouring the unsaved-changes rules (§2.4):
/// dirty documents always ask — "Don't ask again" (Smart Save)
/// never suppresses this warning.
Future<void> closeDocumentWithGuard(
  BuildContext context,
  WidgetRef ref,
  String docId,
) async {
  final notifier = ref.read(editorProvider.notifier);
  final doc = ref.read(editorProvider).docById(docId);
  if (doc == null) return;

  if (doc.kind == EditorDocKind.external) {
    if (!doc.hasUnsyncedChanges) {
      await notifier.closeDocument(docId, deleteTempFile: true);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsynced changes'),
        content: Text(
          '${doc.fileName} has changes in the temporary copy that '
          'have not been uploaded to the server yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard changes'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('sync'),
            child: const Text('Sync now'),
          ),
        ],
      ),
    );
    if (choice == 'sync') {
      final (outcome, _) = await notifier.syncExternal(docId);
      if (outcome == SaveOutcome.saved) {
        await notifier.closeDocument(docId, deleteTempFile: true);
      }
    } else if (choice == 'discard') {
      await notifier.closeDocument(docId, deleteTempFile: true);
    }
    return;
  }

  if (!doc.isDirty) {
    await notifier.closeDocument(docId);
    return;
  }
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unsaved Changes'),
      content: Text(
        'File đã có thay đổi chưa được lưu. Bạn có muốn lưu các '
        'thay đổi này không?\n\n'
        '"${doc.fileName}" has unsaved changes. Do you want to '
        'save them before closing?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('discard'),
          child: const Text("Don't Save"),
        ),
        FilledButton(
          key: const Key('unsaved-save-button'),
          onPressed: () => Navigator.of(context).pop('save'),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (choice == 'save') {
    // Save directly (no second confirmation — the user just
    // chose Save in this dialog); close only on success (§2.4).
    final (outcome, _) = await notifier.save(docId);
    if (outcome == SaveOutcome.saved) {
      await notifier.closeDocument(docId);
    } else if (outcome == SaveOutcome.conflict && context.mounted) {
      final saved = await saveDocumentWithFlow(context, ref, docId);
      if (saved) await notifier.closeDocument(docId);
    }
  } else if (choice == 'discard') {
    await notifier.closeDocument(docId);
  }
}

/// The one-time Smart Save offer (§2.5), shown after a file's
/// third confirmed successful save.
Future<void> showSmartSavePrompt(
  BuildContext context,
  WidgetRef ref,
  String docId,
) async {
  final doc = ref.read(editorProvider).docById(docId);
  if (doc == null) return;
  final dontAsk = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remember this file?'),
      content: Text(
        'You have saved "${doc.fileName}" several times. Should '
        'HeroTerm stop asking for confirmation before saving this '
        'file?\n\n'
        'The warning when closing a file with unsaved changes '
        'always stays on.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Continue Asking'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("Don't Ask Again for This File"),
        ),
      ],
    ),
  );
  if (dontAsk != null) {
    ref
        .read(editorProvider.notifier)
        .answerSmartSavePrompt(docId, dontAskAgain: dontAsk);
  }
}

/// Opens [entry] in the configured external application, showing
/// a dialog on failure. Shared by the Open With chooser and the
/// default-editor double-click path.
Future<void> openInExternalEditor(
  BuildContext context,
  WidgetRef ref,
  RemoteEntry entry,
  String app,
) async {
  final tab = ref.read(sessionManagerProvider).activeTab;
  if (tab == null) return;
  final error = await ref
      .read(editorProvider.notifier)
      .openWithExternal(
        tabId: tab.id,
        profile: tab.profile,
        entry: entry,
        app: app,
      );
  if (error != null && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cannot open file'),
        content: Text(error.userMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Double-click behaviour for a file (§2.6 "Default Editor"):
/// built-in editor, or the configured external application —
/// falling back to the chooser when none is configured.
Future<void> openWithDefaultEditor(
  BuildContext context,
  WidgetRef ref,
  RemoteEntry entry,
) async {
  final settings = ref.read(uiPreferencesProvider).fileEditor;
  if (settings.defaultEditor == DefaultEditorKind.builtin) {
    await openInBuiltinEditor(context, ref, entry);
    return;
  }
  if (settings.externalApp.isEmpty) {
    await showOpenWithDialog(context, ref, entry);
    return;
  }
  await openInExternalEditor(context, ref, entry, settings.externalApp);
}
