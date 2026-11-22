import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_transfer.dart';
import '../domain/ssh_session.dart';
import 'session_dialogs.dart';
import 'sessions_controller.dart';

/// Export flow (profile spec 6.5): warn that the file contains
/// connection configuration only, then write through the native
/// save dialog. Exported JSON never contains secrets or Keychain
/// reference IDs.
Future<void> exportProfiles(
  BuildContext context,
  WidgetRef ref, {
  required List<SshSession> profiles,
  required String suggestedName,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Export profiles?',
    message:
        'The export file contains connection settings only — no '
        'passwords, passphrases, private keys or Keychain references '
        'are included. Imported profiles will ask for credentials '
        'again.',
    confirmLabel: 'Export',
  );
  if (!confirmed || !context.mounted) return;
  final state = ref.read(sessionsProvider);
  final foldersById = {for (final f in state.folders) f.id: f};
  final labelsById = {for (final l in state.labels) l.id: l};
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (location == null) return;
  final json = ProfileTransfer.exportJson(
    profiles: profiles,
    foldersById: foldersById,
    labelsById: labelsById,
    exportedAt: DateTime.now(),
  );
  try {
    await File(location.path).writeAsString(json);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${profiles.length} profile(s).')),
      );
    }
  } on FileSystemException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not write the export file.')),
      );
    }
  }
}

/// Import flow (profile spec 6.5): pick a file, validate it
/// strictly, preview the profiles with their duplicate status,
/// let the user choose the conflict strategy, then apply. Nothing
/// is written before the preview is confirmed.
Future<void> importProfiles(BuildContext context, WidgetRef ref) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (file == null) return;
  final List<ImportedProfile> parsed;
  try {
    final size = await file.length();
    if (size > ProfileTransfer.maxImportBytes) {
      throw const ProfileImportException(
        'The file is too large to be a profile export.',
      );
    }
    parsed = ProfileTransfer.parseImport(await file.readAsString());
  } on ProfileImportException catch (e) {
    if (context.mounted) {
      await showConfirmDialog(
        context,
        title: 'Import failed',
        message: e.message,
        confirmLabel: 'OK',
      );
    }
    return;
  } catch (e) {
    if (context.mounted) {
      await showConfirmDialog(
        context,
        title: 'Import failed',
        message: 'The file could not be read.',
        confirmLabel: 'OK',
      );
    }
    return;
  }
  if (!context.mounted) return;

  final existing = ref.read(sessionsProvider).sessions;
  String keyOf(SshSession s) =>
      '${s.name.toLowerCase()}|${s.host.toLowerCase()}|'
      '${s.username}|${s.port}';
  final existingKeys = existing.map(keyOf).toSet();

  final strategy = await showDialog<ImportConflictStrategy>(
    context: context,
    builder: (context) => _ImportPreviewDialog(
      profiles: parsed,
      duplicateKeys: {
        for (final p in parsed)
          if (existingKeys.contains(p.conflictKey)) p.conflictKey,
      },
    ),
  );
  if (strategy == null || !context.mounted) return;
  final result = await ref
      .read(sessionsProvider.notifier)
      .importProfiles(parsed, strategy);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Import done: ${result.added} added, ${result.updated} updated, '
          '${result.skipped} skipped.',
        ),
      ),
    );
  }
}

class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.profiles,
    required this.duplicateKeys,
  });

  final List<ImportedProfile> profiles;
  final Set<String> duplicateKeys;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  var _strategy = ImportConflictStrategy.skip;

  @override
  Widget build(BuildContext context) {
    final duplicates = widget.profiles
        .where((p) => widget.duplicateKeys.contains(p.conflictKey))
        .length;
    return AlertDialog(
      title: const Text('Import profiles'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.profiles.length} profile(s) found'
              '${duplicates > 0 ? ', $duplicates duplicate(s)' : ''}. '
              'Imported profiles never include passwords or keys and '
              'are not connected automatically.',
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in widget.profiles)
                    ListTile(
                      dense: true,
                      title: Text(
                        p.draft.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${p.draft.username}@${p.draft.host}:${p.draft.port}'
                        '${p.groupName != null ? ' · ${p.groupName}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: widget.duplicateKeys.contains(p.conflictKey)
                          ? const Chip(
                              label: Text('Duplicate'),
                              visualDensity: VisualDensity.compact,
                            )
                          : const Chip(
                              label: Text('New'),
                              visualDensity: VisualDensity.compact,
                            ),
                    ),
                ],
              ),
            ),
            if (duplicates > 0) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<ImportConflictStrategy>(
                key: const Key('import-strategy'),
                initialValue: _strategy,
                decoration: const InputDecoration(
                  labelText: 'When a profile already exists',
                ),
                items: const [
                  DropdownMenuItem(
                    value: ImportConflictStrategy.skip,
                    child: Text('Skip duplicates'),
                  ),
                  DropdownMenuItem(
                    value: ImportConflictStrategy.copy,
                    child: Text('Import as copies'),
                  ),
                  DropdownMenuItem(
                    value: ImportConflictStrategy.update,
                    child: Text('Update existing (keeps saved passwords)'),
                  ),
                ],
                onChanged: (v) => setState(
                  () => _strategy = v ?? ImportConflictStrategy.skip,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('import-confirm'),
          onPressed: () => Navigator.of(context).pop(_strategy),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
