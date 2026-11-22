import 'package:flutter/material.dart';

import '../domain/remote_entry.dart';
import 'explorer_controller.dart';
import '../domain/remote_path.dart';

/// Rename dialog with inline validation (Milestone 4). Returns the
/// validated new name, or null when cancelled.
Future<String?> showRenameDialog(
  BuildContext context, {
  required RemoteEntry entry,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(entry: entry),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.entry});

  final RemoteEntry entry;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.entry.name,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text;
    final error = RemotePath.validateNewName(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rename ${widget.entry.name}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('In ${RemotePath.parentOf(widget.entry.path)}'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('rename-name'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New name',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('rename-confirm'),
          onPressed: _submit,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

/// Delete confirmation showing the full target path (destructive
/// actions always confirm first; directories warn about recursion).
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required RemoteEntry entry,
}) async {
  final isDirectory = entry.kind == RemoteEntryKind.directory;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${entry.name}?'),
      content: SizedBox(
        width: 380,
        child: Text(
          isDirectory
              ? 'This permanently deletes the folder and everything '
                    'inside it:\n\n${entry.path}'
              : 'This permanently deletes:\n\n${entry.path}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Collision resolution for one dropped file (Milestone 5): keep
/// both (rename), overwrite, or skip — optionally applied to all
/// remaining collisions in the batch. Null = cancel the batch.
Future<CollisionAnswer?> showCollisionDialog(
  BuildContext context, {
  required String fileName,
  required String remotePath,
}) {
  return showDialog<CollisionAnswer>(
    context: context,
    builder: (context) =>
        _CollisionDialog(fileName: fileName, remotePath: remotePath),
  );
}

class _CollisionDialog extends StatefulWidget {
  const _CollisionDialog({required this.fileName, required this.remotePath});

  final String fileName;
  final String remotePath;

  @override
  State<_CollisionDialog> createState() => _CollisionDialogState();
}

class _CollisionDialogState extends State<_CollisionDialog> {
  bool _applyToAll = false;

  void _answer(CollisionChoice choice) {
    Navigator.of(context).pop((choice: choice, applyToAll: _applyToAll));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('File already exists'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.fileName}" already exists at:\n'
              '${widget.remotePath}',
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _applyToAll,
              onChanged: (v) => setState(() => _applyToAll = v ?? false),
              title: const Text('Apply to all remaining files'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel upload'),
        ),
        TextButton(
          key: const Key('collision-skip'),
          onPressed: () => _answer(CollisionChoice.skip),
          child: const Text('Skip'),
        ),
        TextButton(
          key: const Key('collision-rename'),
          onPressed: () => _answer(CollisionChoice.rename),
          child: const Text('Keep both'),
        ),
        FilledButton(
          key: const Key('collision-overwrite'),
          onPressed: () => _answer(CollisionChoice.overwrite),
          child: const Text('Overwrite'),
        ),
      ],
    );
  }
}
