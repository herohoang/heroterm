import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../domain/session_appearance.dart';
import '../domain/session_folder.dart';
import '../domain/session_label.dart';
import '../domain/ssh_session.dart';

const _uuid = Uuid();

/// Outcome of the session editor. [secret] follows the controller's
/// convention: null = keep existing secret (edit only), empty = no
/// secret / remove secret, non-empty = store this secret in the
/// credential store. The secret is never placed on the session model.
final class SessionEditorResult {
  const SessionEditorResult({required this.draft, required this.secret});
  final SshSession draft;
  final String? secret;
}

/// Runs a connection test for an unsaved draft (the form's Test
/// Connection button). Implemented by the caller, which owns the
/// SSH service and credential store; returns a secret-free result.
typedef SessionTestRunner = Future<({bool success, String message})> Function(
  SshSession draft,
  String? enteredSecret,
);

/// Creates a label in the library (the form's "New label…"
/// action). Implemented by the caller, which owns the sessions
/// state; returns the created (or existing same-name) label.
typedef SessionLabelCreator = Future<SessionLabel> Function(
  String name,
  int colorValue,
);

Future<SessionEditorResult?> showSessionEditor(
  BuildContext context, {
  SshSession? initial,
  required List<SessionFolder> folders,
  List<SessionLabel> labels = const [],
  SessionTestRunner? onTestConnection,
  SessionLabelCreator? onCreateLabel,
}) {
  return showDialog<SessionEditorResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SessionEditorDialog(
      initial: initial,
      folders: folders,
      labels: labels,
      onTestConnection: onTestConnection,
      onCreateLabel: onCreateLabel,
    ),
  );
}

class _SessionEditorDialog extends StatefulWidget {
  const _SessionEditorDialog({
    required this.initial,
    required this.folders,
    required this.labels,
    required this.onTestConnection,
    required this.onCreateLabel,
  });

  final SshSession? initial;
  final List<SessionFolder> folders;
  final List<SessionLabel> labels;
  final SessionTestRunner? onTestConnection;
  final SessionLabelCreator? onCreateLabel;

  @override
  State<_SessionEditorDialog> createState() => _SessionEditorDialogState();
}

class _SessionEditorDialogState extends State<_SessionEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _secret = TextEditingController();
  late final TextEditingController _keyPath;
  late final TextEditingController _timeout;
  late final TextEditingController _startupDir;
  late final TextEditingController _description;
  late AuthMethod _authMethod;
  late String? _groupId;
  late List<SessionLabel> _allLabels;
  late Set<String> _labelIds;
  late String? _iconId;
  late int? _colorValue;
  bool _secretTouched = false;
  Map<String, String> _errors = const {};
  String? _keyWarning;
  bool _testing = false;
  ({bool success, String message})? _testResult;
  bool _forceClose = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '');
    _port = TextEditingController(text: '${s?.port ?? 22}');
    _username = TextEditingController(text: s?.username ?? '');
    _keyPath = TextEditingController(text: s?.privateKeyPath ?? '');
    _timeout = TextEditingController(
      text: '${s?.connectionTimeout.inSeconds ?? 15}',
    );
    _startupDir = TextEditingController(text: s?.startupDirectory ?? '');
    _description = TextEditingController(text: s?.description ?? '');
    _authMethod = s?.authMethod ?? AuthMethod.password;
    _groupId = s?.groupId;
    _allLabels = [...widget.labels];
    _labelIds = {...?s?.labelIds};
    _iconId = s?.icon;
    _colorValue = s?.colorValue;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _username,
      _secret,
      _keyPath,
      _timeout,
      _startupDir,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whether any field differs from the profile as opened (the
  /// unsaved-changes guard, spec 6.3). A typed secret always
  /// counts as a change; an untouched one does not.
  bool get _isDirty {
    final s = widget.initial;
    if (_secretTouched && _secret.text.isNotEmpty) return true;
    final initialLabels = {...?s?.labelIds};
    return _name.text != (s?.name ?? '') ||
        _host.text != (s?.host ?? '') ||
        _port.text != '${s?.port ?? 22}' ||
        _username.text != (s?.username ?? '') ||
        _keyPath.text != (s?.privateKeyPath ?? '') ||
        _timeout.text != '${s?.connectionTimeout.inSeconds ?? 15}' ||
        _startupDir.text != (s?.startupDirectory ?? '') ||
        _description.text != (s?.description ?? '') ||
        _authMethod != (s?.authMethod ?? AuthMethod.password) ||
        _groupId != s?.groupId ||
        _iconId != s?.icon ||
        _colorValue != s?.colorValue ||
        _labelIds.length != initialLabels.length ||
        !_labelIds.containsAll(initialLabels);
  }

  Future<void> _createLabel() async {
    final creator = widget.onCreateLabel;
    if (creator == null) return;
    final spec = await showCreateLabelDialog(context);
    if (spec == null || !mounted) return;
    final label = await creator(spec.name, spec.colorValue);
    if (!mounted) return;
    setState(() {
      if (!_allLabels.any((l) => l.id == label.id)) {
        _allLabels = [..._allLabels, label];
      }
      _labelIds = {..._labelIds, label.id};
    });
  }

  Future<void> _requestClose() async {
    if (_isDirty && !_forceClose) {
      final discard = await showConfirmDialog(
        context,
        title: 'Discard changes?',
        message: 'This profile form has unsaved changes.',
        confirmLabel: 'Discard',
      );
      if (!discard || !mounted) return;
    }
    setState(() => _forceClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) {
      setState(() {
        _errors = {..._errors}..remove(field);
      });
    }
  }

  Future<void> _browseKeyFile() async {
    // Picking the file through the open panel is also what grants
    // the sandboxed app permission to read it (ADR-007).
    final file = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: 'SSH private key')],
      initialDirectory: _keyPath.text.trim().isEmpty
          ? null
          : File(_keyPath.text.trim()).parent.path,
    );
    if (file != null) {
      setState(() {
        _keyPath.text = file.path;
        _errors = {..._errors}..remove('keyPath');
      });
    }
  }

  SshSession _buildDraft() {
    final now = DateTime.now();
    final initial = widget.initial;
    final port = int.tryParse(_port.text.trim());
    final timeoutSeconds = int.tryParse(_timeout.text.trim());
    return SshSession(
      id: initial?.id ?? _uuid.v4(),
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: port ?? -1,
      username: _username.text.trim(),
      authMethod: _authMethod,
      credentialRef: initial?.credentialRef,
      privateKeyPath: _authMethod == AuthMethod.privateKey
          ? _keyPath.text.trim()
          : null,
      groupId: _groupId,
      description: _description.text.trim(),
      labelIds: [
        for (final l in _allLabels)
          if (_labelIds.contains(l.id)) l.id,
      ],
      icon: _iconId,
      colorValue: _colorValue,
      connectionTimeout: Duration(seconds: timeoutSeconds ?? -1),
      startupDirectory: _startupDir.text.trim().isEmpty
          ? null
          : _startupDir.text.trim(),
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
      lastConnectedAt: initial?.lastConnectedAt,
      lastConnectionStatus: initial?.lastConnectionStatus,
    );
  }

  /// A missing key file is a WARNING, not a save blocker (spec
  /// section 8): the profile may be prepared for a key that lives
  /// elsewhere; Test Connection and real connects will fail with
  /// an actionable error until the file is readable.
  String? _computeKeyWarning() {
    if (_authMethod != AuthMethod.privateKey) return null;
    var path = _keyPath.text.trim();
    if (path.isEmpty) return null;
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '';
      path = '$home${path.substring(1)}';
    }
    if (File(path).existsSync()) return null;
    return 'Key file not found on this Mac (or not accessible). '
        'You can save anyway; connecting will fail until the file '
        'is available.';
  }

  Future<void> _save() async {
    final draft = _buildDraft();
    final errors = draft.validateFields();
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _keyWarning = _computeKeyWarning();
      });
      return;
    }
    final String? secret;
    if (!_isEdit) {
      secret = _secret.text;
    } else if (_secretTouched) {
      secret = _secret.text;
    } else {
      secret = null;
    }
    setState(() => _forceClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context)
            .pop(SessionEditorResult(draft: draft, secret: secret));
      }
    });
  }

  Future<void> _test() async {
    final runner = widget.onTestConnection;
    if (runner == null || _testing) return;
    final draft = _buildDraft();
    final errors = draft.validateFields();
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _keyWarning = _computeKeyWarning();
        _testResult = null;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
      _keyWarning = _computeKeyWarning();
    });
    final result = await runner(draft, _secret.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasExistingSecret = widget.initial?.credentialRef != null;
    return PopScope(
      canPop: _forceClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: AlertDialog(
        title: Text(_isEdit ? 'Edit session' : 'New session'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('session-name'),
                  controller: _name,
                  onChanged: (_) => _clearError('name'),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    errorText: _errors['name'],
                  ),
                ),
                TextField(
                  key: const Key('session-host'),
                  controller: _host,
                  onChanged: (_) => _clearError('host'),
                  decoration: InputDecoration(
                    labelText: 'Host',
                    errorText: _errors['host'],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('session-port'),
                        controller: _port,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _clearError('port'),
                        decoration: InputDecoration(
                          labelText: 'Port',
                          errorText: _errors['port'],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('session-timeout'),
                        controller: _timeout,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _clearError('timeout'),
                        decoration: InputDecoration(
                          labelText: 'Timeout (seconds)',
                          errorText: _errors['timeout'],
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  key: const Key('session-username'),
                  controller: _username,
                  onChanged: (_) => _clearError('username'),
                  decoration: InputDecoration(
                    labelText: 'Username',
                    errorText: _errors['username'],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AuthMethod>(
                  key: const Key('session-auth-method'),
                  initialValue: _authMethod,
                  decoration: const InputDecoration(
                    labelText: 'Authentication',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: AuthMethod.password,
                      child: Text('Password'),
                    ),
                    DropdownMenuItem(
                      value: AuthMethod.privateKey,
                      child: Text('Private key'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _authMethod = v ?? AuthMethod.password),
                ),
                if (_authMethod == AuthMethod.password)
                  TextField(
                    key: const Key('session-password'),
                    controller: _secret,
                    obscureText: true,
                    onChanged: (_) => _secretTouched = true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: _isEdit && hasExistingSecret
                          ? 'Stored in Keychain. Leave blank to keep it.'
                          : 'Stored in the macOS Keychain, never in files.',
                    ),
                  ),
                if (_authMethod == AuthMethod.privateKey) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('session-key-path'),
                          controller: _keyPath,
                          onChanged: (_) => _clearError('keyPath'),
                          decoration: InputDecoration(
                            labelText: 'Private key file path',
                            helperText:
                                'Referenced in place; the key file '
                                'is not copied.',
                            errorText: _errors['keyPath'],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('session-key-browse'),
                        onPressed: _browseKeyFile,
                        child: const Text('Browse…'),
                      ),
                    ],
                  ),
                  TextField(
                    key: const Key('session-passphrase'),
                    controller: _secret,
                    obscureText: true,
                    onChanged: (_) => _secretTouched = true,
                    decoration: InputDecoration(
                      labelText: 'Key passphrase (optional)',
                      helperText: _isEdit && hasExistingSecret
                          ? 'Stored in Keychain. Leave blank to keep it.'
                          : 'Stored in the macOS Keychain, never in files.',
                    ),
                  ),
                ],
                TextField(
                  key: const Key('session-startup-dir'),
                  controller: _startupDir,
                  onChanged: (_) => _clearError('startupDirectory'),
                  decoration: InputDecoration(
                    labelText: 'Startup directory (optional)',
                    errorText: _errors['startupDirectory'],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const Key('session-folder'),
                  initialValue: _groupId,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Ungrouped'),
                    ),
                    for (final f in widget.folders)
                      DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ],
                  onChanged: (v) => setState(() => _groupId = v),
                ),
                TextField(
                  key: const Key('session-description'),
                  controller: _description,
                  maxLength: 500,
                  maxLines: 2,
                  onChanged: (_) => _clearError('description'),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    errorText: _errors['description'],
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Labels',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final label in _allLabels)
                        FilterChip(
                          key: Key('session-label-${label.id}'),
                          avatar: CircleAvatar(
                            backgroundColor: label.color,
                            radius: 6,
                          ),
                          label: Text(label.name),
                          selected: _labelIds.contains(label.id),
                          onSelected: (selected) => setState(() {
                            _labelIds = {..._labelIds};
                            if (selected) {
                              _labelIds.add(label.id);
                            } else {
                              _labelIds.remove(label.id);
                            }
                          }),
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                        ),
                      if (widget.onCreateLabel != null)
                        ActionChip(
                          key: const Key('session-new-label'),
                          avatar: const Icon(Icons.add, size: 16),
                          label: const Text('New label'),
                          onPressed: _createLabel,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Icon & colour',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                _IconPicker(
                  selected: _iconId,
                  fallback: Icons.dns_outlined,
                  onChanged: (v) => setState(() => _iconId = v),
                ),
                const SizedBox(height: 6),
                _ColorPicker(
                  selected: _colorValue,
                  onChanged: (v) => setState(() => _colorValue = v),
                ),
                if (_keyWarning != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _keyWarning!,
                            key: const Key('session-key-warning'),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_testing || _testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_testing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _testResult!.success
                                ? Icons.check_circle
                                : Icons.error,
                            size: 16,
                            color: _testResult!.success
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _testing
                                ? 'Testing connection…'
                                : _testResult!.message,
                            key: const Key('session-test-result'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (widget.onTestConnection != null)
            OutlinedButton(
              key: const Key('session-test'),
              onPressed: _testing ? null : _test,
              child: const Text('Test Connection'),
            ),
          TextButton(onPressed: _requestClose, child: const Text('Cancel')),
          FilledButton(
            key: const Key('session-save'),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Icon picker row (ADR-013): a Default choice plus the curated
/// icon set. Shared by the session and folder editors.
class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.selected,
    required this.fallback,
    required this.onChanged,
  });

  final String? selected;
  final IconData fallback;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget choice(String? id, IconData icon, String tooltip) {
      final isSelected = selected == id;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          key: Key('icon-choice-${id ?? 'default'}'),
          onTap: () => onChanged(id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isSelected ? scheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: Icon(icon, size: 18),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          choice(null, fallback, 'Default icon'),
          for (final entry in appearanceIconChoices.entries)
            choice(entry.key, entry.value, entry.key),
        ],
      ),
    );
  }
}

/// Colour picker row (ADR-013): a None choice plus the palette.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget choice(int? value, Widget child, String tooltip) {
      final isSelected = selected == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          key: Key('color-choice-${value ?? 'none'}'),
          onTap: () => onChanged(value),
          customBorder: const CircleBorder(),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? scheme.primary : scheme.outlineVariant,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          choice(null, const Icon(Icons.block, size: 16), 'No colour'),
          for (final value in appearanceColorChoices)
            choice(
              value,
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(value),
                ),
              ),
              'Colour',
            ),
        ],
      ),
    );
  }
}

/// Create-label dialog (name + colour), used by the session
/// editor's "New label" action and the label manager.
Future<({String name, int colorValue})?> showCreateLabelDialog(
  BuildContext context,
) {
  return showDialog<({String name, int colorValue})>(
    context: context,
    builder: (context) => const _CreateLabelDialog(),
  );
}

class _CreateLabelDialog extends StatefulWidget {
  const _CreateLabelDialog();

  @override
  State<_CreateLabelDialog> createState() => _CreateLabelDialogState();
}

class _CreateLabelDialogState extends State<_CreateLabelDialog> {
  final _controller = TextEditingController();
  int _colorValue = labelPalette[5];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = normalizeLabelName(_controller.text);
    if (name.isEmpty) {
      setState(() => _error = 'Label name is required.');
      return;
    }
    if (name.length > 40) {
      setState(() => _error = 'Label name is too long.');
      return;
    }
    Navigator.of(context).pop((name: name, colorValue: _colorValue));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('label-name'),
            controller: _controller,
            autofocus: true,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Label name',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          _ColorPicker(
            selected: _colorValue,
            onChanged: (v) =>
                setState(() => _colorValue = v ?? labelPalette[5]),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('label-create'),
          onPressed: _save,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Folder editor result: name, group type, and appearance
/// (profile spec 5.1 + ADR-013).
typedef FolderEditorResult = ({
  String name,
  FolderType type,
  String? icon,
  int? colorValue,
});

Future<FolderEditorResult?> showFolderEditorDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  FolderType initialType = FolderType.custom,
  String? initialIcon,
  int? initialColorValue,
}) {
  return showDialog<FolderEditorResult>(
    context: context,
    builder: (context) => _FolderEditorDialog(
      title: title,
      initial: initial,
      type: initialType,
      icon: initialIcon,
      colorValue: initialColorValue,
    ),
  );
}

class _FolderEditorDialog extends StatefulWidget {
  const _FolderEditorDialog({
    required this.title,
    required this.initial,
    required this.type,
    required this.icon,
    required this.colorValue,
  });

  final String title;
  final String initial;
  final FolderType type;
  final String? icon;
  final int? colorValue;

  @override
  State<_FolderEditorDialog> createState() => _FolderEditorDialogState();
}

class _FolderEditorDialogState extends State<_FolderEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  late FolderType _type = widget.type;
  late String? _iconId = widget.icon;
  late int? _colorValue = widget.colorValue;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Folder name is required.');
      return;
    }
    if (name.length > 100) {
      setState(() => _error = 'Folder name is too long.');
      return;
    }
    if (name.contains('/')) {
      setState(() => _error = 'Folder name must not contain /.');
      return;
    }
    Navigator.of(context)
        .pop((name: name, type: _type, icon: _iconId, colorValue: _colorValue));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('folder-name'),
            controller: _controller,
            autofocus: true,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Folder name',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<FolderType>(
            key: const Key('folder-type'),
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Group type'),
            items: const [
              DropdownMenuItem(
                value: FolderType.project,
                child: Text('Project'),
              ),
              DropdownMenuItem(value: FolderType.client, child: Text('Client')),
              DropdownMenuItem(value: FolderType.custom, child: Text('Custom')),
            ],
            onChanged: (v) => setState(() => _type = v ?? FolderType.custom),
          ),
          const SizedBox(height: 12),
          _IconPicker(
            selected: _iconId,
            fallback: Icons.folder_outlined,
            onChanged: (v) => setState(() => _iconId = v),
          ),
          const SizedBox(height: 6),
          _ColorPicker(
            selected: _colorValue,
            onChanged: (v) => setState(() => _colorValue = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('folder-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-action'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Result of the move-session picker: [chosen] false means cancelled;
/// when chosen, [folderId] null means Ungrouped.
typedef MoveChoice = ({bool chosen, String? folderId});

Future<MoveChoice> showMoveSessionDialog(
  BuildContext context, {
  required List<SessionFolder> folders,
}) async {
  final result = await showDialog<MoveChoice>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Move session to'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(context).pop((chosen: true, folderId: null)),
          child: const Text('Ungrouped'),
        ),
        for (final f in folders)
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop((chosen: true, folderId: f.id)),
            child: Text(f.name),
          ),
      ],
    ),
  );
  return result ?? (chosen: false, folderId: null);
}
