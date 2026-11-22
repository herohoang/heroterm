import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/ui_preferences.dart';
import '../../file_editor/presentation/editor_actions.dart';
import '../../file_editor/presentation/file_editor_settings.dart'
    show showOpenWithDialog;
import '../../connection/presentation/terminal_sessions.dart';
import '../data/id_name_resolver.dart';
import '../domain/remote_entry.dart';
import '../domain/remote_path.dart';
import 'explorer_controller.dart';
import 'explorer_dialogs.dart';

/// Milestone 3 Remote Explorer: replaces the session library in the
/// sidebar while connected (FEATURE_SPEC section 2). Lists the remote
/// directory that tracks the terminal's working directory.
class RemoteExplorer extends ConsumerStatefulWidget {
  const RemoteExplorer({super.key});

  @override
  ConsumerState<RemoteExplorer> createState() => _RemoteExplorerState();
}

class _RemoteExplorerState extends ConsumerState<RemoteExplorer> {
  bool _attaching = false;

  /// The tab whose connection the explorer is currently bound to,
  /// and each tab's last browsed directory (restored on switch).
  String? _attachedTabId;
  final _savedPaths = <String, String>{};

  @override
  Widget build(BuildContext context) {
    // The explorer always follows the ACTIVE tab: it re-attaches
    // when the active tab changes or (dis)connects, remembers each
    // tab's directory, and tracks the active shell's cwd reports.
    ref.listen(sessionManagerProvider, (previous, next) {
      final prevActive = previous?.activeTab;
      final nextActive = next.activeTab;
      final desired = (nextActive != null && nextActive.isConnected)
          ? nextActive.id
          : null;
      if (desired != _attachedTabId) {
        if (_attachedTabId != null) {
          final oldPath = ref.read(explorerProvider).currentPath;
          if (oldPath != null) _savedPaths[_attachedTabId!] = oldPath;
          _attachedTabId = null;
          ref.read(explorerProvider.notifier).detach();
        }
        if (desired != null) _attachTab(nextActive!);
      }
      if (nextActive != null &&
          nextActive.id == prevActive?.id &&
          nextActive.remoteCwd != null &&
          nextActive.remoteCwd != prevActive?.remoteCwd &&
          nextActive.isConnected) {
        ref.read(explorerProvider.notifier).onRemoteCwd(nextActive.remoteCwd!);
      }
    });

    final explorer = ref.watch(explorerProvider);
    final tabs = ref.watch(sessionManagerProvider);
    final activeTab = tabs.activeTab;
    final notifier = ref.read(explorerProvider.notifier);
    final currentPath = explorer.currentPath;

    // If this widget mounts after the active tab is already live
    // (the listen edge above was missed — e.g. a very fast local
    // connection completing within one frame), attach directly.
    if (activeTab != null &&
        activeTab.isConnected &&
        _attachedTabId != activeTab.id &&
        !notifier.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _attachTab(activeTab);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Remote Explorer',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                key: const Key('explorer-follow-toggle'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(
                  explorer.followCwd ? Icons.link : Icons.link_off,
                  size: 18,
                ),
                tooltip: explorer.followCwd
                    ? 'Following terminal directory (tap to pause)'
                    : 'Not following terminal directory (tap to follow)',
                onPressed: () => notifier.setFollowCwd(!explorer.followCwd),
              ),
              IconButton(
                key: const Key('explorer-hidden-toggle'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(
                  explorer.showHidden ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                ),
                tooltip: explorer.showHidden
                    ? 'Hide hidden files'
                    : 'Show hidden files',
                onPressed: () => notifier.setShowHidden(!explorer.showHidden),
              ),
              IconButton(
                key: const Key('explorer-upload'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: const Icon(Icons.upload_file, size: 18),
                tooltip: 'Upload files…',
                onPressed: explorer.currentPath == null
                    ? null
                    : () async {
                        final picked = await openFiles(
                          confirmButtonText: 'Upload',
                        );
                        if (picked.isEmpty) return;
                        await notifier.uploadLocalPaths(
                          picked.map((f) => f.path).toList(),
                          askCollision: (fileName, remotePath) =>
                              showCollisionDialog(
                                context,
                                fileName: fileName,
                                remotePath: remotePath,
                              ),
                        );
                      },
              ),
              IconButton(
                key: const Key('explorer-refresh'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh',
                onPressed: explorer.isLoading ? null : notifier.refresh,
              ),
            ],
          ),
        ),
        if (currentPath != null) ...[
          const _LocationBar(),
          _Breadcrumbs(path: currentPath),
        ],
        if ((activeTab?.isConnected ?? false) &&
            !(activeTab?.cwdTrackingSupported ?? true))
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              'This shell does not report its working directory; '
              'the explorer will not follow the terminal. Navigate '
              'manually instead.',
            ),
          ),
        if (explorer.isLoading) const LinearProgressIndicator(),
        if (explorer.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    explorer.error!.userMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: notifier.refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: currentPath == null
              ? Center(
                  child: Text(
                    activeTab?.isConnected ?? false
                        ? 'Connecting…'
                        : 'This session is not connected.',
                  ),
                )
              : _ExplorerTable(currentPath: currentPath),
        ),
        const _TransferPanel(),
      ],
    );
  }

  Future<void> _attachTab(TerminalTab tab) async {
    if (_attaching) return;
    _attaching = true;
    try {
      final manager = ref.read(sessionManagerProvider.notifier);
      final service = await manager.fileServiceFor(tab.id);
      if (service == null || !mounted) return;
      // The user may have switched tabs while the service was being
      // created; only bind the explorer to the still-active tab.
      final current = ref.read(sessionManagerProvider);
      if (current.activeTabId != tab.id ||
          !(current.tabById(tab.id)?.isConnected ?? false)) {
        return;
      }
      _attachedTabId = tab.id;
      await ref
          .read(explorerProvider.notifier)
          .attach(
            service,
            reportedCwd: tab.remoteCwd,
            startupDirectory: tab.profile.startupDirectory,
            preferredPath: _savedPaths[tab.id],
            fetchIdNames: () => fetchIdNames(
              (command) => manager.runCommandFor(tab.id, command),
            ),
          );
    } finally {
      _attaching = false;
    }
  }
}

class _Breadcrumbs extends ConsumerWidget {
  const _Breadcrumbs({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ancestors = RemotePath.ancestorsOf(path);
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            for (var i = 0; i < ancestors.length; i++) ...[
              if (i > 0) const Icon(Icons.chevron_right, size: 14),
              TextButton(
                key: Key('crumb-${ancestors[i]}'),
                onPressed: () => ref
                    .read(explorerProvider.notifier)
                    .navigateTo(ancestors[i]),
                child: Text(
                  ancestors[i] == '/' ? '/' : ancestors[i].split('/').last,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _EntryAction { edit, openWith, rename, delete, download }

/// The entry context menu shared by table rows (Rename / Download /
/// Delete), identical actions to the Milestone 4 list tiles.
Future<void> _showEntryMenu(
  BuildContext context,
  WidgetRef ref,
  RemoteEntry entry,
  Offset position,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final action = await showMenu<_EntryAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      if (entry.kind == RemoteEntryKind.file) ...[
        const PopupMenuItem(value: _EntryAction.edit, child: Text('Edit')),
        const PopupMenuItem(
          value: _EntryAction.openWith,
          child: Text('Open With…'),
        ),
      ],
      const PopupMenuItem(value: _EntryAction.rename, child: Text('Rename…')),
      if (entry.kind == RemoteEntryKind.file)
        const PopupMenuItem(
          value: _EntryAction.download,
          child: Text('Download…'),
        ),
      const PopupMenuItem(value: _EntryAction.delete, child: Text('Delete…')),
    ],
  );
  if (action == null || !context.mounted) return;
  final notifier = ref.read(explorerProvider.notifier);
  switch (action) {
    case _EntryAction.edit:
      await openInBuiltinEditor(context, ref, entry);
    case _EntryAction.openWith:
      await showOpenWithDialog(context, ref, entry);
    case _EntryAction.rename:
      final newName = await showRenameDialog(context, entry: entry);
      if (newName != null) {
        await notifier.renameEntry(entry, newName);
      }
    case _EntryAction.delete:
      final confirmed = await showDeleteConfirmDialog(context, entry: entry);
      if (confirmed) {
        await notifier.deleteEntry(entry);
      }
    case _EntryAction.download:
      final location = await getSaveLocation(
        suggestedName: entry.name,
        confirmButtonText: 'Download',
      );
      if (location != null) {
        await notifier.downloadEntry(entry, location.path);
      }
  }
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// The directory listing as a multi-column table (table-view spec):
/// sortable headers, per-column drag resizing with double-click
/// auto-fit, folders first, horizontal scrolling when the sidebar
/// is narrower than the table.
class _ExplorerTable extends ConsumerStatefulWidget {
  const _ExplorerTable({required this.currentPath});

  final String currentPath;

  @override
  ConsumerState<_ExplorerTable> createState() => _ExplorerTableState();
}

class _ExplorerTableState extends ConsumerState<_ExplorerTable> {
  static const _columns = ExplorerSortColumn.values;
  final Map<ExplorerSortColumn, double> _dragStartWidths = {};

  double _totalWidth(UiPreferences prefs) =>
      _columns.fold(0.0, (sum, c) => sum + prefs.columnWidth(c));

  void _autoFit(ExplorerSortColumn column) {
    final explorer = ref.read(explorerProvider);
    final style = Theme.of(context).textTheme.bodySmall!;
    var widest = explorerColumnSpecs[column]!.label.length * 8.0 + 40;
    for (final entry in explorer.visible) {
      final text = _cellText(explorer, column, entry);
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      var width = painter.width + 24;
      if (column == ExplorerSortColumn.name) width += 26; // row icon
      if (width > widest) widest = width;
    }
    ref.read(uiPreferencesProvider.notifier).setColumnWidth(column, widest);
  }

  String _cellText(
    ExplorerState explorer,
    ExplorerSortColumn column,
    RemoteEntry entry,
  ) {
    return switch (column) {
      ExplorerSortColumn.name => entry.name,
      ExplorerSortColumn.size =>
        entry.kind == RemoteEntryKind.file && entry.size != null
            ? formatRemoteSize(entry.size!)
            : '—',
      ExplorerSortColumn.modified =>
        entry.modifiedAt != null ? _formatDateTime(entry.modifiedAt!) : '—',
      ExplorerSortColumn.owner => explorer.ownerLabelOf(entry),
      ExplorerSortColumn.group => explorer.groupLabelOf(entry),
      ExplorerSortColumn.permission => entry.permissionString ?? '—',
    };
  }

  @override
  Widget build(BuildContext context) {
    final explorer = ref.watch(explorerProvider);
    final prefs = ref.watch(uiPreferencesProvider);
    final totalWidth = _totalWidth(prefs);
    final entries = explorer.visible;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth < constraints.maxWidth
                ? constraints.maxWidth
                : totalWidth,
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, explorer, prefs),
                const Divider(height: 1),
                Expanded(
                  child: entries.isEmpty && !explorer.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('This directory is empty.'),
                        )
                      : ListView.builder(
                          itemCount:
                              entries.length +
                              (widget.currentPath != '/' ? 1 : 0),
                          itemBuilder: (context, index) {
                            var i = index;
                            if (widget.currentPath != '/') {
                              if (i == 0) {
                                return _buildParentRow(context, prefs);
                              }
                              i--;
                            }
                            return _buildRow(
                              context,
                              explorer,
                              prefs,
                              entries[i],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ExplorerState explorer,
    UiPreferences prefs,
  ) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      height: 34,
      child: Row(
        children: [
          for (final column in _columns)
            SizedBox(
              width: prefs.columnWidth(column),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InkWell(
                      key: Key('column-header-${column.name}'),
                      onTap: () =>
                          ref.read(explorerProvider.notifier).setSort(column),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment:
                              explorerColumnSpecs[column]!.rightAligned
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                explorerColumnSpecs[column]!.label,
                                style: theme.textTheme.labelMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (explorer.sortColumn == column) ...[
                              const SizedBox(width: 2),
                              Icon(
                                explorer.sortAscending
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 13,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        key: Key('column-resize-${column.name}'),
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) {
                          _dragStartWidths[column] = prefs.columnWidth(column);
                        },
                        onHorizontalDragUpdate: (details) {
                          final running =
                              _dragStartWidths[column] ??
                              prefs.columnWidth(column);
                          final next = running + details.delta.dx;
                          _dragStartWidths[column] =
                              explorerColumnSpecs[column]!.clampWidth(next);
                          ref
                              .read(uiPreferencesProvider.notifier)
                              .setColumnWidth(column, next);
                        },
                        onHorizontalDragEnd: (_) =>
                            ref.read(uiPreferencesProvider.notifier).flush(),
                        onDoubleTap: () => _autoFit(column),
                        child: const SizedBox(width: 9, height: 34),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParentRow(BuildContext context, UiPreferences prefs) {
    final notifier = ref.read(explorerProvider.notifier);
    return InkWell(
      onTap: () => notifier.navigateTo(RemotePath.parentOf(widget.currentPath)),
      child: SizedBox(
        height: 30,
        child: Row(
          children: [
            SizedBox(
              width: prefs.columnWidth(ExplorerSortColumn.name),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(Icons.folder_outlined, size: 17),
                    SizedBox(width: 6),
                    Text('..'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ExplorerState explorer,
    UiPreferences prefs,
    RemoteEntry entry,
  ) {
    final theme = Theme.of(context);
    final notifier = ref.read(explorerProvider.notifier);
    final selected = explorer.selectedPath == entry.path;
    return InkWell(
      key: Key('entry-row-${entry.name}'),
      onTap: () {
        notifier.selectEntry(entry.path);
        if (entry.isNavigable) notifier.navigateTo(entry.path);
      },
      onDoubleTap: entry.kind == RemoteEntryKind.file
          ? () => openWithDefaultEditor(context, ref, entry)
          : null,
      onSecondaryTapDown: (details) {
        notifier.selectEntry(entry.path);
        _showEntryMenu(context, ref, entry, details.globalPosition);
      },
      child: Container(
        height: 30,
        color: selected ? theme.colorScheme.secondaryContainer : null,
        child: Row(
          children: [
            for (final column in _columns)
              SizedBox(
                width: prefs.columnWidth(column),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: column == ExplorerSortColumn.name
                      ? Row(
                          children: [
                            Icon(
                              entry.isNavigable
                                  ? Icons.folder
                                  : entry.kind == RemoteEntryKind.symlink
                                  ? Icons.link
                                  : Icons.insert_drive_file_outlined,
                              size: 17,
                              color: entry.isNavigable
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Tooltip(
                                message: entry.kind == RemoteEntryKind.symlink
                                    ? '${entry.path} → ${entry.linkTarget ?? ''}'
                                    : entry.path,
                                child: Text(
                                  entry.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _cellText(explorer, column, entry),
                          overflow: TextOverflow.ellipsis,
                          textAlign: explorerColumnSpecs[column]!.rightAligned
                              ? TextAlign.right
                              : TextAlign.left,
                          style: column == ExplorerSortColumn.permission
                              ? AppTheme.mono.copyWith(fontSize: 11.5)
                              : theme.textTheme.bodySmall,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wraps the sidebar (session library or Remote Explorer) as the
/// drag-and-drop target for Milestone 5. Drops while connected go
/// to the explorer's upload queue for the visible current
/// directory; drops while disconnected are rejected with a clear
/// message.
class DropUploadRegion extends ConsumerStatefulWidget {
  const DropUploadRegion({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DropUploadRegion> createState() => _DropUploadRegionState();
}

class _DropUploadRegionState extends ConsumerState<DropUploadRegion> {
  bool _dragging = false;

  Future<void> _onDrop(List<DropItem> items) async {
    final connection = ref.read(connectionProvider);
    final explorer = ref.read(explorerProvider);
    if (!connection.isConnected || explorer.currentPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect to a server first — dropped files upload to '
            'the folder shown in the Remote Explorer.',
          ),
        ),
      );
      return;
    }
    // macOS sandbox: files dragged in from Finder are outside the
    // app container. The drop plugin hands us a security-scoped
    // bookmark per item; access must be started explicitly or every
    // read fails with a permission error (the drop then looks like
    // it "did nothing"). Hold the scopes for the whole upload.
    final started = <Uint8List>[];
    for (final item in items) {
      final bookmark = item.extraAppleBookmark;
      if (bookmark != null && bookmark.isNotEmpty) {
        final ok = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
        if (ok) started.add(bookmark);
      }
    }
    try {
      await ref
          .read(explorerProvider.notifier)
          .uploadLocalPaths(
            items.map((f) => f.path).toList(),
            askCollision: (fileName, remotePath) => showCollisionDialog(
              context,
              fileName: fileName,
              remotePath: remotePath,
            ),
          );
    } finally {
      for (final bookmark in started) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final explorer = ref.watch(explorerProvider);
    final connection = ref.watch(connectionProvider);
    final canUpload = connection.isConnected && explorer.currentPath != null;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _onDrop(details.files);
      },
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer
                        .withValues(alpha: 0.85),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    canUpload
                        ? 'Drop to upload into\n${explorer.currentPath}'
                        : 'Connect to a server to upload files',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Path bar above the breadcrumbs (MobaXterm-style location bar):
/// shows the current directory in an editable text field — select
/// and copy it, or type a path and press Enter to navigate. The
/// dropdown button opens the recent-paths history.
class _LocationBar extends ConsumerStatefulWidget {
  const _LocationBar();

  @override
  ConsumerState<_LocationBar> createState() => _LocationBarState();
}

class _LocationBarState extends ConsumerState<_LocationBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _editing = _focusNode.hasFocus);
      if (!_focusNode.hasFocus) _sync(null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sync(String? currentPath) {
    final path = currentPath ?? ref.read(explorerProvider).currentPath;
    if (path != null && _controller.text != path) {
      _controller.text = path;
    }
  }

  void _go() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(explorerProvider.notifier).navigateTo(text);
    _focusNode.unfocus();
  }

  Future<void> _showHistory() async {
    final explorer = ref.read(explorerProvider);
    final history = explorer.recentPaths;
    if (history.isEmpty) return;
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height)),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
      Offset.zero & overlay.size,
    );
    final chosen = await showMenu<String>(
      context: context,
      position: position,
      items: [
        for (final path in history)
          PopupMenuItem(
            value: path,
            child: Row(
              children: [
                Icon(
                  path == explorer.currentPath
                      ? Icons.folder_open
                      : Icons.history,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(path, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    );
    if (chosen != null) {
      ref.read(explorerProvider.notifier).navigateTo(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(explorerProvider.select((s) => s.currentPath), (previous, next) {
      if (!_editing) _sync(next);
    });
    final explorer = ref.watch(explorerProvider);
    if (!_editing) _sync(explorer.currentPath);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('explorer-path-field'),
              controller: _controller,
              focusNode: _focusNode,
              style: Theme.of(context).textTheme.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.folder_open, size: 16),
                prefixIconConstraints: BoxConstraints(
                  minWidth: 30,
                  minHeight: 0,
                ),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) => _go(),
            ),
          ),
          IconButton(
            key: const Key('explorer-history'),
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            tooltip: 'Recent folders',
            onPressed: explorer.recentPaths.isEmpty ? null : _showHistory,
          ),
        ],
      ),
    );
  }
}

/// Bottom-of-sidebar transfer panel: active transfer progress and
/// the latest transfer/info notice live here (per user request),
/// not at the top of the explorer.
class _TransferPanel extends ConsumerWidget {
  const _TransferPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explorer = ref.watch(explorerProvider);
    final notifier = ref.read(explorerProvider.notifier);
    if (!explorer.isTransferring && explorer.notice == null) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (explorer.isTransferring) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    explorer.transferLabel ??
                        'Downloading ${explorer.transferName} — '
                            '${formatRemoteSize(explorer.transferDone)}'
                            '${explorer.transferTotal != null ? ' of ${formatRemoteSize(explorer.transferTotal!)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: const Key('transfer-cancel'),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  tooltip: 'Cancel transfer',
                  onPressed: () {
                    notifier.cancelDownload();
                    notifier.cancelUpload();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: explorer.transferProgress),
          ],
          if (explorer.notice != null) ...[
            if (explorer.isTransferring) const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    explorer.notice!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Dismiss',
                  onPressed: notifier.dismissNotice,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
