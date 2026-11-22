import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui_preferences.dart';
import '../../connection/presentation/terminal_sessions.dart';
import '../../remote_explorer/domain/remote_entry.dart';
import '../data/external_editor.dart';
import 'editor_actions.dart';

/// The File Editor settings group (Edit File spec §2.6), opened
/// from the header gear. Changes apply (and persist) immediately.
Future<void> showFileEditorSettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _FileEditorSettingsDialog(),
  );
}

final class _FileEditorSettingsDialog extends ConsumerStatefulWidget {
  const _FileEditorSettingsDialog();

  @override
  ConsumerState<_FileEditorSettingsDialog> createState() =>
      _FileEditorSettingsDialogState();
}

class _FileEditorSettingsDialogState
    extends ConsumerState<_FileEditorSettingsDialog> {
  late final TextEditingController _customAppController;
  late final TextEditingController _tempDirController;
  List<ExternalAppCandidate> _detected = const [];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(uiPreferencesProvider).fileEditor;
    _customAppController = TextEditingController(text: settings.externalApp);
    _tempDirController = TextEditingController(text: settings.tempDirectory);
    _detected = detectExternalApps();
  }

  @override
  void dispose() {
    _customAppController.dispose();
    _tempDirController.dispose();
    super.dispose();
  }

  void _update(FileEditorSettings Function(FileEditorSettings) change) {
    final notifier = ref.read(uiPreferencesProvider.notifier);
    notifier.setFileEditorSettings(
      change(ref.read(uiPreferencesProvider).fileEditor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(uiPreferencesProvider).fileEditor;
    final highlighting = ref.watch(uiPreferencesProvider).terminalHighlighting;
    final skipped = settings.smartSaveRecords.entries
        .where((e) => e.value.dontAskAgain)
        .toList();
    final detectedPaths = _detected.map((a) => a.bundlePath).toSet();
    final dropdownValue = detectedPaths.contains(settings.externalApp)
        ? settings.externalApp
        : '';

    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Terminal', style: Theme.of(context).textTheme.titleSmall),
              SwitchListTile(
                key: const Key('settings-terminal-highlighting'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Syntax highlighting'),
                subtitle: const Text(
                  'Colours keywords, IP addresses, links and numbers '
                  'in shell output, like MobaXterm. Text a program '
                  'colours itself is never overridden.',
                ),
                value: highlighting,
                onChanged: (value) => ref
                    .read(uiPreferencesProvider.notifier)
                    .setTerminalHighlighting(value),
              ),
              if (highlighting) const _HighlightPreview(),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'File Editor',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text('Default editor (double-click a file)'),
              const SizedBox(height: 6),
              SegmentedButton<DefaultEditorKind>(
                segments: const [
                  ButtonSegment(
                    value: DefaultEditorKind.builtin,
                    label: Text('Built-in'),
                    icon: Icon(Icons.edit_note),
                  ),
                  ButtonSegment(
                    value: DefaultEditorKind.external,
                    label: Text('External'),
                    icon: Icon(Icons.open_in_new),
                  ),
                ],
                selected: {settings.defaultEditor},
                onSelectionChanged: (selection) =>
                    _update((s) => s.copyWith(defaultEditor: selection.first)),
              ),
              const SizedBox(height: 16),
              const Text('External application'),
              const SizedBox(height: 6),
              DropdownButton<String>(
                key: const Key('settings-external-app'),
                isExpanded: true,
                value: dropdownValue,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Not configured'),
                  ),
                  for (final app in _detected)
                    DropdownMenuItem(
                      value: app.bundlePath,
                      child: Text('${app.name} — ${app.bundlePath}'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _customAppController.text = value;
                  _update((s) => s.copyWith(externalApp: value));
                },
              ),
              TextField(
                key: const Key('settings-external-app-custom'),
                controller: _customAppController,
                decoration: InputDecoration(
                  hintText: Platform.isWindows
                      ? '…or an editor path (e.g. "C:\\Program Files\\Microsoft VS Code\\Code.exe")'
                      : '…or an app name / .app path (e.g. "Sublime Text")',
                  isDense: true,
                ),
                onSubmitted: (value) =>
                    _update((s) => s.copyWith(externalApp: value.trim())),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('settings-auto-sync'),
                title: const Text('Auto Sync'),
                subtitle: const Text(
                  'Upload external-editor changes automatically '
                  'once the file settles',
                ),
                value: settings.autoSync,
                onChanged: (value) =>
                    _update((s) => s.copyWith(autoSync: value)),
              ),
              SwitchListTile(
                key: const Key('settings-confirm-save'),
                title: const Text('Save Confirmation'),
                subtitle: const Text('Ask before uploading changes on Save'),
                value: settings.confirmBeforeSave,
                onChanged: (value) =>
                    _update((s) => s.copyWith(confirmBeforeSave: value)),
              ),
              SwitchListTile(
                key: const Key('settings-smart-save'),
                title: const Text('Smart Save'),
                subtitle: const Text(
                  'After 3 confirmed saves of a file, offer to stop '
                  'asking for that file',
                ),
                value: settings.smartSaveEnabled,
                onChanged: (value) =>
                    _update((s) => s.copyWith(smartSaveEnabled: value)),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('settings-temp-dir'),
                controller: _tempDirController,
                decoration: const InputDecoration(
                  labelText: 'Temp Directory',
                  hintText: 'System temp (default)',
                  isDense: true,
                ),
                onSubmitted: (value) =>
                    _update((s) => s.copyWith(tempDirectory: value.trim())),
              ),
              const SizedBox(height: 16),
              Text(
                'Files that skip the save confirmation',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (skipped.isEmpty)
                const Text('None yet.')
              else
                for (final entry in skipped)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.key.substring(entry.key.indexOf('|') + 1),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(uiPreferencesProvider.notifier)
                          .setSmartSaveRecord(
                            entry.key,
                            entry.value.copyWith(dontAskAgain: false),
                          ),
                      child: const Text('Ask again'),
                    ),
                  ),
            ],
          ),
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
}

/// The "Open With…" chooser (§2.3): detected macOS editors, the
/// configured default preselected, an option to set the choice as
/// the default, and a free-form name/path for anything else.
Future<void> showOpenWithDialog(
  BuildContext context,
  WidgetRef ref,
  RemoteEntry entry,
) async {
  final tab = ref.read(sessionManagerProvider).activeTab;
  if (tab == null) return;
  final settings = ref.read(uiPreferencesProvider).fileEditor;
  final detected = detectExternalApps();
  var selected = settings.externalApp;
  if (selected.isEmpty && detected.isNotEmpty) {
    selected = detected.first.bundlePath;
  }
  var custom = '';
  var makeDefault = false;

  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Open "${entry.name}" with'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detected.isEmpty)
                  Text(
                    Platform.isWindows
                        ? 'No known editor was found in the usual '
                              'install locations. Type an editor '
                              'executable path below.'
                        : 'No known editor was found in /Applications. '
                              'Type an application name or .app path below.',
                  ),
                for (final app in detected)
                  ListTile(
                    leading: Icon(
                      (custom.isEmpty && selected == app.bundlePath)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                    ),
                    title: Text(app.name),
                    subtitle: Text(app.bundlePath),
                    onTap: () => setState(() {
                      selected = app.bundlePath;
                      custom = '';
                    }),
                  ),
                TextField(
                  key: const Key('open-with-custom'),
                  decoration: const InputDecoration(
                    labelText: 'Other application (name or path)',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => custom = value),
                ),
                CheckboxListTile(
                  value: makeDefault,
                  onChanged: (value) =>
                      setState(() => makeDefault = value ?? false),
                  title: const Text('Set as default external application'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: (custom.trim().isEmpty && selected.isEmpty)
                ? null
                : () => Navigator.of(context)
                      .pop(custom.trim().isNotEmpty ? custom.trim() : selected),
            child: const Text('Open'),
          ),
        ],
      ),
    ),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;
  if (makeDefault) {
    ref
        .read(uiPreferencesProvider.notifier)
        .setFileEditorSettings(settings.copyWith(externalApp: chosen));
  }
  await openInExternalEditor(context, ref, entry, chosen);
}

/// A static sample of the terminal highlighting palette
/// (mirrors `terminalHighlightRules`, ADR-024).
final class _HighlightPreview extends StatelessWidget {
  const _HighlightPreview();

  @override
  Widget build(BuildContext context) {
    TextSpan word(String text, Color color, {bool underline = false}) =>
        TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            decoration: underline ? TextDecoration.underline : null,
          ),
        );
    const base = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Color(0xFFD6DEEB),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            word('error ', const Color(0xFFEF5350)),
            word('warning ', const Color(0xFFFFB74D)),
            word('enabled ', const Color(0xFF81C784)),
            word('information ', const Color(0xFF64B5F6)),
            word('103.82.192.240 ', const Color(0xFFF06292)),
            word('65.2% ', const Color(0xFFFFD54F)),
            word(
              'https://ubuntu.com/pro',
              const Color(0xFF4FC3F7),
              underline: true,
            ),
          ],
        ),
      ),
    );
  }
}
