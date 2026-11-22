import '../build_info.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../core/debug/input_debug_log.dart';

import '../features/connection/data/ssh_connection_service.dart';
import '../features/connection/domain/connection_state.dart';
import '../features/connection/presentation/terminal_sessions.dart';
import '../features/connection/presentation/connection_dialogs.dart';
import '../features/file_editor/presentation/editor_actions.dart'
    show closeDocumentWithGuard, showSmartSavePrompt;
import '../features/file_editor/presentation/editor_controller.dart';
import '../features/file_editor/presentation/editor_pane.dart';
import '../features/file_editor/presentation/file_editor_settings.dart'
    show showFileEditorSettings;
import '../features/remote_explorer/domain/remote_entry.dart';
import '../features/remote_explorer/presentation/remote_explorer.dart';
import '../features/server_monitor/domain/server_metrics.dart';
import '../features/server_monitor/presentation/server_metrics_controller.dart';
import '../features/sessions/domain/session_appearance.dart';
import '../features/sessions/domain/ssh_session.dart';
import 'ui_preferences.dart';
import '../features/sessions/presentation/sessions_controller.dart';
import '../features/sessions/presentation/sessions_sidebar.dart';
import 'theme/app_theme.dart';

/// App shell: responsive desktop layout with the three regions
/// HeroTerm is built around — sidebar, central work area, and a
/// metrics footer.
///
/// * With no terminal tabs open, the sidebar is the session
///   library and the workspace offers the selected session.
/// * Once tabs exist (multi-session tabs spec), the sidebar is the
///   Remote Explorer of the ACTIVE tab, the workspace shows the
///   tab strip plus the active tab's terminal, and the + button /
///   ⌘T opens a temporary session picker panel.
/// * The footer reports the active tab's *remote* server metrics
///   (Milestone 6) and shows "unavailable" while it is not
///   connected — never fake values (ADR-005).
final class _ConnectIntent extends Intent {
  const _ConnectIntent();
}

final class _DisconnectIntent extends Intent {
  const _DisconnectIntent();
}

final class _ReconnectIntent extends Intent {
  const _ReconnectIntent();
}

final class _ToggleInputLogIntent extends Intent {
  const _ToggleInputLogIntent();
}

final class _NewTabIntent extends Intent {
  const _NewTabIntent();
}

final class _CloseTabIntent extends Intent {
  const _CloseTabIntent();
}

final class _NextTabIntent extends Intent {
  const _NextTabIntent();
}

final class _PreviousTabIntent extends Intent {
  const _PreviousTabIntent();
}

final class _ActivateTabIntent extends Intent {
  const _ActivateTabIntent(this.index);
  final int index;
}

/// App-level keyboard shortcuts:
/// ⌘/Ctrl+Shift+C connect the selected session, ⌘/Ctrl+Shift+D
/// disconnect the active tab, ⌘/Ctrl+Shift+R reconnect it,
/// ⌘/Ctrl+T open the new-tab picker, ⌘/Ctrl+Shift+W close the
/// active tab, Ctrl+Tab / Ctrl+Shift+Tab cycle tabs, and
/// ⌘/Ctrl+1…9 jump to a tab. They fire when the focused widget
/// (e.g. the terminal) does not consume the combination itself.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _pickerOpen = false;

  SessionManagerNotifier get _manager =>
      ref.read(sessionManagerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(sessionManagerProvider);
    final hasTabs = tabs.tabs.isNotEmpty;

    ref.listen(sessionManagerProvider.select((s) => s.notice), (
      previous,
      next,
    ) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
        _manager.clearNotice();
      }
    });

    // While tabs exist, the sidebar is the active tab's Remote
    // Explorer; otherwise it is the session library. The whole
    // sidebar is the Finder drop target for uploads (Milestone 5) —
    // DropUploadRegion itself handles the disconnected case.
    final uiPrefs = ref.watch(uiPreferencesProvider);
    final sidebar = DropUploadRegion(
      child: hasTabs ? const RemoteExplorer() : const SessionsSidebar(),
    );
    final picker = _pickerOpen
        ? _SessionPicker(onClose: () => setState(() => _pickerOpen = false))
        : null;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
            _ConnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
            _ConnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, meta: true, shift: true):
            _DisconnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true):
            _DisconnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, meta: true, shift: true):
            _ReconnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyR, control: true, shift: true):
            _ReconnectIntent(),
        SingleActivator(LogicalKeyboardKey.keyL, meta: true, shift: true):
            _ToggleInputLogIntent(),
        SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true):
            _ToggleInputLogIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, meta: true): _NewTabIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _NewTabIntent(),
        SingleActivator(LogicalKeyboardKey.keyW, meta: true, shift: true):
            _CloseTabIntent(),
        SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true):
            _CloseTabIntent(),
        SingleActivator(LogicalKeyboardKey.tab, control: true):
            _NextTabIntent(),
        SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
            _PreviousTabIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            _ActivateTabIntent(0),
        SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            _ActivateTabIntent(1),
        SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            _ActivateTabIntent(2),
        SingleActivator(LogicalKeyboardKey.digit4, meta: true):
            _ActivateTabIntent(3),
        SingleActivator(LogicalKeyboardKey.digit5, meta: true):
            _ActivateTabIntent(4),
        SingleActivator(LogicalKeyboardKey.digit6, meta: true):
            _ActivateTabIntent(5),
        SingleActivator(LogicalKeyboardKey.digit7, meta: true):
            _ActivateTabIntent(6),
        SingleActivator(LogicalKeyboardKey.digit8, meta: true):
            _ActivateTabIntent(7),
        SingleActivator(LogicalKeyboardKey.digit9, meta: true):
            _ActivateTabIntent(8),
        SingleActivator(LogicalKeyboardKey.digit1, control: true):
            _ActivateTabIntent(0),
        SingleActivator(LogicalKeyboardKey.digit2, control: true):
            _ActivateTabIntent(1),
        SingleActivator(LogicalKeyboardKey.digit3, control: true):
            _ActivateTabIntent(2),
        SingleActivator(LogicalKeyboardKey.digit4, control: true):
            _ActivateTabIntent(3),
        SingleActivator(LogicalKeyboardKey.digit5, control: true):
            _ActivateTabIntent(4),
        SingleActivator(LogicalKeyboardKey.digit6, control: true):
            _ActivateTabIntent(5),
        SingleActivator(LogicalKeyboardKey.digit7, control: true):
            _ActivateTabIntent(6),
        SingleActivator(LogicalKeyboardKey.digit8, control: true):
            _ActivateTabIntent(7),
        SingleActivator(LogicalKeyboardKey.digit9, control: true):
            _ActivateTabIntent(8),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ConnectIntent: CallbackAction<_ConnectIntent>(
            onInvoke: (_) {
              final selected = ref.read(sessionsProvider).selectedSession;
              if (selected != null) _manager.openSession(selected);
              return null;
            },
          ),
          _DisconnectIntent: CallbackAction<_DisconnectIntent>(
            onInvoke: (_) {
              _manager.disconnectActive();
              return null;
            },
          ),
          _ReconnectIntent: CallbackAction<_ReconnectIntent>(
            onInvoke: (_) {
              _manager.reconnectActive();
              return null;
            },
          ),
          _ToggleInputLogIntent: CallbackAction<_ToggleInputLogIntent>(
            onInvoke: (_) {
              final turningOn = !InputDebugLog.enabled;
              // Fire-and-forget: enabling resolves the log path.
              InputDebugLog.setEnabled(turningOn);
              final messenger = ScaffoldMessenger.of(context);
              messenger.clearSnackBars();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    turningOn
                        ? 'Input log ON — reproduce the typing problem, '
                              'then press ⌘⇧L again and send the file '
                              'heroterm-input-log.txt (in the app support '
                              'folder). Do not type passwords while it is on.'
                        : 'Input log OFF.',
                  ),
                  duration: const Duration(seconds: 6),
                ),
              );
              return null;
            },
          ),
          _NewTabIntent: CallbackAction<_NewTabIntent>(
            onInvoke: (_) {
              setState(() => _pickerOpen = true);
              return null;
            },
          ),
          _CloseTabIntent: CallbackAction<_CloseTabIntent>(
            onInvoke: (_) {
              _manager.closeActive();
              return null;
            },
          ),
          _NextTabIntent: CallbackAction<_NextTabIntent>(
            onInvoke: (_) {
              _manager.activateRelativeTab(1);
              return null;
            },
          ),
          _PreviousTabIntent: CallbackAction<_PreviousTabIntent>(
            onInvoke: (_) {
              _manager.activateRelativeTab(-1);
              return null;
            },
          ),
          _ActivateTabIntent: CallbackAction<_ActivateTabIntent>(
            onInvoke: (intent) {
              final current = ref.read(sessionManagerProvider);
              if (intent.index < current.tabs.length) {
                _manager.activateTab(current.tabs[intent.index].id);
                ref.read(editorProvider.notifier).showTerminal();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                const _ConnectionHeader(),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 760) {
                        return Column(
                          children: [
                            SizedBox(height: 240, child: sidebar),
                            const Divider(height: 1),
                            Expanded(
                              child: Stack(
                                children: [
                                  _Workspace(
                                    onNewTab: () =>
                                        setState(() => _pickerOpen = true),
                                  ),
                                  if (picker != null)
                                    Positioned(
                                      left: 8,
                                      top: 8,
                                      bottom: 8,
                                      width: 300,
                                      child: picker,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      // Resizable sidebar (table-view spec
                      // section 3): the width persists across
                      // launches and is clamped so the terminal
                      // always keeps a usable share of the window.
                      var sidebarWidth = uiPrefs.clampedSidebarWidth;
                      final cap = constraints.maxWidth - 380;
                      if (cap > UiPreferences.minSidebarWidth &&
                          sidebarWidth > cap) {
                        sidebarWidth = cap;
                      }
                      return Row(
                        children: [
                          SizedBox(width: sidebarWidth, child: sidebar),
                          _SidebarResizer(currentWidth: sidebarWidth),
                          if (picker != null) ...[
                            SizedBox(width: 300, child: picker),
                            const VerticalDivider(width: 1),
                          ],
                          Expanded(
                            child: _Workspace(
                              onNewTab: () =>
                                  setState(() => _pickerOpen = true),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                const _MetricsFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drag handle between the sidebar and the workspace. Dragging
/// resizes the sidebar within its persisted limits; the width is
/// saved when the drag ends (and debounced while dragging).
class _SidebarResizer extends ConsumerWidget {
  const _SidebarResizer({required this.currentWidth});

  final double currentWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(uiPreferencesProvider.notifier);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('sidebar-resizer'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            notifier.setSidebarWidth(currentWidth + details.delta.dx),
        onHorizontalDragEnd: (_) => notifier.flush(),
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(width: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}

class _ConnectionHeader extends ConsumerWidget {
  const _ConnectionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionProvider);
    final (color, label) = switch (connection.status) {
      ConnectionStatus.connected => (
        Colors.green,
        'Connected: ${connection.profile?.name ?? ''}',
      ),
      ConnectionStatus.connecting => (Colors.amber, 'Connecting…'),
      ConnectionStatus.disconnecting => (Colors.amber, 'Disconnecting…'),
      ConnectionStatus.failed => (Colors.red, 'Connection failed'),
      _ => (Colors.grey, 'Disconnected'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.terminal, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('HeroTerm', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 16),
          Chip(
            avatar: Icon(Icons.circle, size: 10, color: color),
            label: Text(label),
          ),
          const SizedBox(width: 12),
          Text(
            'build $buildId',
            key: const Key('build-stamp'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('settings-button'),
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Settings',
            onPressed: () => showFileEditorSettings(context),
          ),
        ],
      ),
    );
  }
}

/// The terminal workspace: the tab strip and the active tab's
/// terminal, or — with no tabs — the empty state offering the
/// selected session.
class _Workspace extends ConsumerStatefulWidget {
  const _Workspace({this.onNewTab});

  final VoidCallback? onNewTab;

  @override
  ConsumerState<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<_Workspace> {
  bool _hostKeyDialogOpen = false;
  bool _passwordDialogOpen = false;

  @override
  void initState() {
    super.initState();
    // Smart Save (§2.5): the editor notifier asks us to show the
    // one-time "Don't ask again" prompt; dialogs need a context,
    // which lives here in the workspace.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(editorProvider.notifier).smartSavePromptListener = (docId) {
        if (mounted) {
          unawaited(showSmartSavePrompt(context, ref, docId));
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionManagerProvider, (previous, next) {
      if (next.hostKeyPrompt != null && !_hostKeyDialogOpen) {
        _showHostKeyDialog(next.hostKeyPrompt!.challenge);
      }
      if (next.passwordPrompt != null && !_passwordDialogOpen) {
        _showPasswordDialog(next.passwordPrompt!);
      }
    });

    final tabs = ref.watch(sessionManagerProvider);
    final editor = ref.watch(editorProvider);

    if (tabs.tabs.isEmpty && editor.documents.isEmpty) {
      return _emptyState(context);
    }

    final showEditor = editor.activeDocumentId != null;
    final activeIndex = tabs.tabs.indexWhere((t) => t.id == tabs.activeTabId);
    final active =
        tabs.activeTab ?? (tabs.tabs.isEmpty ? null : tabs.tabs.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabBar(onNewTab: widget.onNewTab),
        if (showEditor)
          const Expanded(child: EditorSurface())
        else if (active != null) ...[
          _TerminalBar(tab: active),
          Expanded(
            child: Container(
              color: Colors.black,
              // Every tab keeps its own TerminalView mounted so
              // switching never recreates a terminal or loses
              // scrollback (spec 3.2/3.4).
              child: IndexedStack(
                index: activeIndex < 0 ? 0 : activeIndex,
                children: [
                  for (final tab in tabs.tabs)
                    TerminalView(
                      tab.terminal,
                      key: ValueKey('terminal-${tab.id}'),
                      autofocus: tab.id == active.id && tab.isConnected,
                    ),
                ],
              ),
            ),
          ),
        ] else
          const Expanded(
            child: Center(
              child: Text('The terminal is closed — pick a file tab above.'),
            ),
          ),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final selected = ref.watch(sessionsProvider).selectedSession;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              selected == null ? 'Not connected to a server' : selected.name,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              selected == null
                  ? 'Select a session, or create one with + in the sidebar.'
                  : '${selected.username}@${selected.host}:${selected.port}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('connect-button'),
              onPressed: selected == null
                  ? null
                  : () => ref
                        .read(sessionManagerProvider.notifier)
                        .openSession(selected),
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHostKeyDialog(HostKeyChallenge challenge) async {
    _hostKeyDialogOpen = true;
    final trust = await showHostKeyTrustDialog(context, challenge);
    _hostKeyDialogOpen = false;
    if (!mounted) return;
    ref.read(sessionManagerProvider.notifier).resolveHostKeyPrompt(trust);
  }

  Future<void> _showPasswordDialog(PasswordPromptState prompt) async {
    _passwordDialogOpen = true;
    final password = await showPasswordPromptDialog(
      context,
      username: prompt.username,
      hostLabel: prompt.hostLabel,
    );
    _passwordDialogOpen = false;
    if (!mounted) return;
    ref.read(sessionManagerProvider.notifier).resolvePasswordPrompt(password);
  }
}

/// The tab strip (spec 2.1): one chip per open terminal session
/// with a status dot and a close button, horizontally scrollable
/// when overflowing, the active tab kept visible, and a + button
/// opening the session picker.
class _TabBar extends ConsumerStatefulWidget {
  const _TabBar({this.onNewTab});

  final VoidCallback? onNewTab;

  @override
  ConsumerState<_TabBar> createState() => _TabBarState();
}

class _TabBarState extends ConsumerState<_TabBar> {
  final _scrollController = ScrollController();
  final _chipKeys = <String, GlobalKey>{};
  String? _lastActiveId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(sessionManagerProvider);
    if (tabs.activeTabId != _lastActiveId) {
      _lastActiveId = tabs.activeTabId;
      final key = _chipKeys[tabs.activeTabId];
      if (key != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = key.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.5,
              duration: const Duration(milliseconds: 150),
            );
          }
        });
      }
    }
    final editor = ref.watch(editorProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in tabs.tabs)
                    _tabChip(
                      context,
                      tab,
                      tab.id == tabs.activeTabId &&
                          editor.activeDocumentId == null,
                    ),
                  for (final doc in editor.documents)
                    _docChip(context, doc, doc.id == editor.activeDocumentId),
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('new-tab-button'),
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'New tab (⌘T)',
            onPressed: widget.onNewTab,
          ),
        ],
      ),
    );
  }

  Widget _tabChip(BuildContext context, TerminalTab tab, bool active) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = switch (tab.status) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting ||
      ConnectionStatus.reconnecting ||
      ConnectionStatus.disconnecting => Colors.amber,
      ConnectionStatus.failed => Colors.red,
      _ => Colors.grey,
    };
    final key = _chipKeys.putIfAbsent(tab.id, GlobalKey.new);
    return Tooltip(
      message:
          '${tab.profile.name} — ${tab.profile.username}@'
          '${tab.profile.host}:${tab.profile.port}',
      child: InkWell(
        key: key,
        onTap: () {
          ref.read(sessionManagerProvider.notifier).activateTab(tab.id);
          ref.read(editorProvider.notifier).showTerminal();
        },
        child: Container(
          decoration: BoxDecoration(
            color: active ? scheme.surface : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? scheme.primary : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 9, color: dotColor),
              const SizedBox(width: 7),
              if (tab.profile.icon != null || tab.profile.colorValue != null)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Icon(
                    appearanceIcon(
                      tab.profile.icon,
                      fallback: Icons.dns_outlined,
                    ),
                    size: 14,
                    color: tab.profile.colorValue == null
                        ? null
                        : Color(tab.profile.colorValue!),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  tab.title,
                  key: Key('tab-title-${tab.id}'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              IconButton(
                key: Key('tab-close-${tab.id}'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Close tab',
                onPressed: () =>
                    ref.read(sessionManagerProvider.notifier).closeTab(tab.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A file-editor tab chip (Edit File spec §2.2): file name, a
  /// dirty dot, and a close button that honours the
  /// unsaved-changes guard (§2.4).
  Widget _docChip(BuildContext context, EditorDocument doc, bool active) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '${doc.remotePath} — ${doc.profileName}',
      child: InkWell(
        onTap: () => ref.read(editorProvider.notifier).activate(doc.id),
        child: Container(
          decoration: BoxDecoration(
            color: active ? scheme.surface : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? scheme.primary : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                doc.kind == EditorDocKind.external
                    ? Icons.open_in_new
                    : Icons.description_outlined,
                size: 14,
                color: scheme.outline,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  doc.fileName,
                  key: Key('editor-tab-${doc.id}'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (doc.isDirty)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.circle, size: 8, color: Colors.orange),
                ),
              IconButton(
                key: Key('editor-tab-close-${doc.id}'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.close, size: 15),
                tooltip: 'Close file',
                onPressed: () =>
                    unawaited(closeDocumentWithGuard(context, ref, doc.id)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The new-session picker (spec 2.2): a temporary panel listing the
/// saved connections grouped by folder, with search. Tapping a
/// connection opens it in a tab — or activates its existing tab
/// when it is already open; the trailing button deliberately opens
/// another session of the same profile. The panel stays open so
/// several connections can be opened in sequence.
class _SessionPicker extends ConsumerStatefulWidget {
  const _SessionPicker({required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<_SessionPicker> createState() => _SessionPickerState();
}

class _SessionPickerState extends ConsumerState<_SessionPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(SshSession session) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return session.name.toLowerCase().contains(q) ||
        session.host.toLowerCase().contains(q) ||
        session.username.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final sessionsState = ref.watch(sessionsProvider);
    final tabs = ref.watch(sessionManagerProvider);
    final manager = ref.read(sessionManagerProvider.notifier);
    final openCounts = <String, int>{};
    for (final tab in tabs.tabs) {
      openCounts[tab.profile.id] = (openCounts[tab.profile.id] ?? 0) + 1;
    }

    final groups = <(String, List<SshSession>)>[
      for (final folder in sessionsState.sortedFolders)
        (
          folder.name,
          sessionsState.sessions
              .where((s) => s.groupId == folder.id && _matches(s))
              .toList(),
        ),
      (
        'Ungrouped',
        sessionsState.sessions
            .where((s) => s.groupId == null && _matches(s))
            .toList(),
      ),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'New tab',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('picker-close'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close picker',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              key: const Key('picker-search'),
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search sessions…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (tabs.notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                tabs.notice!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final (groupName, sessions) in groups)
                  if (sessions.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                      child: Text(
                        groupName,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    for (final session in sessions)
                      ListTile(
                        key: Key('picker-session-${session.id}'),
                        dense: true,
                        leading: Icon(
                          appearanceIcon(
                            session.icon,
                            fallback: Icons.dns_outlined,
                          ),
                          size: 20,
                          color: session.colorValue == null
                              ? null
                              : Color(session.colorValue!),
                        ),
                        title: Text(
                          session.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${session.username}@${session.host}:${session.port}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: (openCounts[session.id] ?? 0) > 0
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Chip(
                                    label: Text('Open'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    key: Key(
                                      'picker-open-another-${session.id}',
                                    ),
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      size: 18,
                                    ),
                                    tooltip: 'Open another session',
                                    onPressed: () =>
                                        manager.openAdditionalSession(session),
                                  ),
                                ],
                              )
                            : null,
                        onTap: () {
                          if ((openCounts[session.id] ?? 0) > 0) {
                            // Already open: switch to its tab instead
                            // of silently duplicating (spec 2.2).
                            final existing = tabs.tabs.firstWhere(
                              (t) => t.profile.id == session.id,
                            );
                            manager.activateTab(existing.id);
                            widget.onClose();
                          } else {
                            manager.openSession(session);
                          }
                        },
                      ),
                  ],
                if (groups.every((g) => g.$2.isEmpty))
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No sessions match.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalBar extends ConsumerWidget {
  const _TerminalBar({required this.tab});

  final TerminalTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = tab.profile;
    final manager = ref.read(sessionManagerProvider.notifier);
    final message = tab.error?.userMessage ?? tab.notice;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.circle,
              size: 10,
              color: tab.isConnected ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${profile.name} — ${profile.username}@'
                '${profile.host}:${profile.port}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (message != null) ...[
              Flexible(
                child: Text(
                  message,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tab.error != null
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Dismiss',
                onPressed: () => manager.dismissActiveError(),
              ),
            ],
            if (tab.isConnected || tab.isBusy)
              Tooltip(
                message: 'Disconnect (⌘⇧D)',
                child: OutlinedButton.icon(
                  key: const Key('disconnect-button'),
                  onPressed: () => manager.disconnectTab(tab.id),
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('Disconnect'),
                ),
              ),
            if (!tab.isConnected && !tab.isBusy)
              Tooltip(
                message: 'Reconnect (⌘⇧R)',
                child: FilledButton.icon(
                  key: const Key('reconnect-button'),
                  onPressed: () => manager.reconnectTab(tab.id),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reconnect'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Footer with the *remote* server's CPU / memory / disk metrics
/// (Milestone 6). Values come from `serverMetricsProvider`; while
/// disconnected — or when the server cannot report them — the footer
/// shows dashes and an unavailable note, never invented numbers.
class _MetricsFooter extends ConsumerWidget {
  const _MetricsFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionProvider);
    final metrics = ref.watch(serverMetricsProvider);

    if (!connection.isConnected ||
        metrics.status == MetricsStatus.unavailable ||
        metrics.status == MetricsStatus.collecting) {
      final collecting =
          connection.isConnected && metrics.status == MetricsStatus.collecting;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.speed, size: 16),
            const SizedBox(width: 8),
            const Text('CPU —', style: AppTheme.mono),
            const SizedBox(width: 16),
            const Text('Memory —', style: AppTheme.mono),
            const SizedBox(width: 16),
            const Text('Disk —', style: AppTheme.mono),
            const Spacer(),
            if (collecting) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              collecting
                  ? 'Collecting server metrics…'
                  : 'Server metrics unavailable',
              style: AppTheme.mono,
            ),
          ],
        ),
      );
    }

    final stale = metrics.status == MetricsStatus.stale;
    final cpu = metrics.cpuPercent == null
        ? 'CPU —'
        : 'CPU ${metrics.cpuPercent!.toStringAsFixed(0)}%';
    final memory =
        metrics.memoryUsedBytes == null || metrics.memoryTotalBytes == null
        ? 'Memory —'
        : 'Memory ${formatRemoteSize(metrics.memoryUsedBytes!)} / '
              '${formatRemoteSize(metrics.memoryTotalBytes!)} '
              '(${metrics.memoryUsedPercent!.toStringAsFixed(0)}%)';
    final disk = metrics.diskUsedPercent == null
        ? 'Disk —'
        : 'Disk / ${metrics.diskUsedPercent!.toStringAsFixed(0)}%';
    final sampled = metrics.sampledAt;
    final hh = sampled.hour.toString().padLeft(2, '0');
    final mm = sampled.minute.toString().padLeft(2, '0');
    final ss = sampled.second.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.speed, size: 16, color: stale ? Colors.amber : null),
          const SizedBox(width: 8),
          Text(cpu, key: const Key('metrics-cpu'), style: AppTheme.mono),
          const SizedBox(width: 16),
          Text(memory, key: const Key('metrics-memory'), style: AppTheme.mono),
          const SizedBox(width: 16),
          Text(disk, key: const Key('metrics-disk'), style: AppTheme.mono),
          const Spacer(),
          Text(
            stale ? 'Stale — last update $hh:$mm:$ss' : 'Updated $hh:$mm:$ss',
            key: const Key('metrics-status'),
            style: AppTheme.mono.copyWith(color: stale ? Colors.amber : null),
          ),
        ],
      ),
    );
  }
}
