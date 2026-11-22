import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/session_label.dart';
import 'session_dialogs.dart';
import 'sessions_controller.dart';

/// Label manager (ADR-013): create, rename, recolour and delete
/// the library's labels. Deleting a label detaches it from every
/// session (the sessions themselves are kept).
Future<void> showLabelManagerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _LabelManagerDialog(),
  );
}

class _LabelManagerDialog extends ConsumerWidget {
  const _LabelManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    final notifier = ref.read(sessionsProvider.notifier);
    return AlertDialog(
      title: const Text('Manage labels'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.labels.isEmpty)
              const Text('No labels yet. Create one to tag sessions.'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final label in state.labels)
                    ListTile(
                      dense: true,
                      leading: PopupMenuButton<int>(
                        key: Key('label-color-${label.id}'),
                        tooltip: 'Label colour',
                        initialValue: label.colorValue,
                        onSelected: (v) => notifier.setLabelColor(label.id, v),
                        itemBuilder: (context) => [
                          for (final value in labelPalette)
                            PopupMenuItem(
                              value: value,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Color(value),
                                    radius: 8,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    value == label.colorValue
                                        ? 'Current'
                                        : 'Colour',
                                  ),
                                ],
                              ),
                            ),
                        ],
                        child: CircleAvatar(
                          backgroundColor: label.color,
                          radius: 10,
                        ),
                      ),
                      title: Text(label.name),
                      subtitle: Text(
                        'Used by ${state.sessions.where((s) => s.labelIds.contains(label.id)).length} session(s)',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('label-rename-${label.id}'),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            tooltip: 'Rename',
                            onPressed: () async {
                              final name = await _askName(
                                context,
                                title: 'Rename label',
                                initial: label.name,
                              );
                              if (name != null) {
                                await notifier.renameLabel(label.id, name);
                              }
                            },
                          ),
                          IconButton(
                            key: Key('label-delete-${label.id}'),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Delete label',
                            onPressed: () async {
                              final confirmed = await showConfirmDialog(
                                context,
                                title: 'Delete label "${label.name}"?',
                                message:
                                    'The label is removed from every '
                                    'session. Sessions themselves are '
                                    'not deleted.',
                                confirmLabel: 'Delete label',
                              );
                              if (confirmed) {
                                await notifier.deleteLabel(label.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('label-manager-create'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New label'),
                onPressed: () async {
                  final spec = await showCreateLabelDialog(context);
                  if (spec != null) {
                    await notifier.addLabel(
                      spec.name,
                      colorValue: spec.colorValue,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('label-rename-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
          decoration: const InputDecoration(labelText: 'Label name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
