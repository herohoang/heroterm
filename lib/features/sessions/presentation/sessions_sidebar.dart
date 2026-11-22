import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/session_appearance.dart';
import '../domain/session_folder.dart';
import '../domain/session_label.dart';
import '../domain/ssh_session.dart';
import 'label_manager_dialog.dart';
import 'session_dialogs.dart';
import 'sessions_controller.dart';
import 'test_connection.dart';
import 'transfer_dialogs.dart';

/// Session library sidebar: search + environment filter, grouped
/// session list, and all create/edit/duplicate/delete/move,
/// test-connection and import/export actions for sessions and
/// folders. Displayed in the sidebar while no terminal tabs are
/// open; with tabs open the region swaps to the Remote Explorer
/// (FEATURE_SPEC section 2).
class SessionsSidebar extends ConsumerStatefulWidget {
  const SessionsSidebar({super.key});

  @override
  ConsumerState<SessionsSidebar> createState() => _SessionsSidebarState();
}

class _SessionsSidebarState extends ConsumerState<SessionsSidebar> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SessionTestRunner _testRunner(BuildContext context) {
    return (draft, enteredSecret) async {
      final result = await runConnectionTest(
        context,
        ref,
        draft,
        enteredSecret: enteredSecret,
      );
      return (success: result.success, message: result.message);
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionsProvider);
    final notifier = ref.read(sessionsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Text('Sessions', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                key: const Key('new-folder-button'),
                icon: const Icon(Icons.create_new_folder_outlined),
                tooltip: 'New folder',
                onPressed: () async {
                  final result = await showFolderEditorDialog(
                    context,
                    title: 'New folder',
                  );
                  if (result != null) {
                    await notifier.addFolder(
                      result.name,
                      type: result.type,
                      icon: result.icon,
                      colorValue: result.colorValue,
                    );
                  }
                },
              ),
              IconButton(
                key: const Key('new-session-button'),
                icon: const Icon(Icons.add),
                tooltip: 'New session',
                onPressed: () => _createSession(context),
              ),
              PopupMenuButton<String>(
                key: const Key('library-menu'),
                tooltip: 'Import / export',
                onSelected: (action) async {
                  switch (action) {
                    case 'export':
                      await exportProfiles(
                        context,
                        ref,
                        profiles: state.sessions,
                        suggestedName: 'heroterm-profiles.json',
                      );
                    case 'import':
                      await importProfiles(context, ref);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: Text('Export all profiles…'),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: Text('Import profiles…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            key: const Key('session-search'),
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search sessions',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: notifier.setQuery,
          ),
        ),
        if (state.labels.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final label in state.labels)
                  FilterChip(
                    key: Key('label-filter-${label.id}'),
                    avatar: CircleAvatar(
                      backgroundColor: label.color,
                      radius: 6,
                    ),
                    label: Text(label.name),
                    selected: state.selectedLabelIds.contains(label.id),
                    onSelected: (_) => notifier.toggleLabelFilter(label.id),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                  ),
                IconButton(
                  key: const Key('manage-labels-button'),
                  icon: const Icon(Icons.label_outline, size: 18),
                  tooltip: 'Manage labels',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showLabelManagerDialog(context),
                ),
              ],
            ),
          ),
        if (state.errorMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: !state.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : state.sessions.isEmpty && state.folders.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No sessions yet.'),
                      SizedBox(height: 4),
                      Text('Use + to save your first SSH session.'),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    for (final folder in state.sortedFolders)
                      if (folder.parentId == null &&
                          state.folderMatchesQuery(folder))
                        _FolderSection(folder: folder, depth: 0),
                    _SessionGroup(
                      title: 'Ungrouped',
                      sessions: state.sessionsIn(null),
                    ),
                    // Folders alone are a real library: keep the
                    // first-run hint as a list footer instead of
                    // letting the empty state swallow the tree
                    // (it keyed on sessions only, so a folder
                    // created before any session never rendered).
                    if (state.sessions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No sessions yet.'),
                            SizedBox(height: 4),
                            Text('Use + to save your first SSH session.'),
                          ],
                        ),
                      )
                    else if (state.filteredSessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('No sessions match your search.'),
                            TextButton(
                              key: const Key('clear-filters'),
                              onPressed: () {
                                _searchController.clear();
                                notifier.clearFilters();
                              },
                              child: const Text('Clear filters'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _createSession(BuildContext context) async {
    final state = ref.read(sessionsProvider);
    final result = await showSessionEditor(
      context,
      folders: state.sortedFolders,
      labels: state.labels,
      onTestConnection: _testRunner(context),
      onCreateLabel: (name, colorValue) => ref
          .read(sessionsProvider.notifier)
          .addLabel(name, colorValue: colorValue),
    );
    if (result == null) return;
    final created = await ref
        .read(sessionsProvider.notifier)
        .addSession(result.draft, secret: result.secret);
    ref.read(sessionsProvider.notifier).select(created.id);
  }
}

class _FolderSection extends ConsumerStatefulWidget {
  const _FolderSection({required this.folder, required this.depth});

  final SessionFolder folder;
  final int depth;

  @override
  ConsumerState<_FolderSection> createState() => _FolderSectionState();
}

class _FolderSectionState extends ConsumerState<_FolderSection> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionsProvider);
    final folder = widget.folder;
    final children = state.sortedFolders
        .where((f) => f.parentId == folder.id)
        .toList();
    // While a search/filter is active, matches must stay visible.
    final filtering =
        state.query.trim().isNotEmpty || state.selectedLabelIds.isNotEmpty;
    final collapsed = _collapsed && !filtering;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12.0 + widget.depth * 16, 8, 4, 4),
          child: Row(
            children: [
              IconButton(
                key: Key('folder-toggle-${folder.id}'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                ),
                tooltip: collapsed ? 'Expand group' : 'Collapse group',
                onPressed: () => setState(() => _collapsed = !_collapsed),
              ),
              Icon(
                appearanceIcon(folder.icon, fallback: Icons.folder_outlined),
                size: 18,
                color: folder.colorValue == null
                    ? null
                    : Color(folder.colorValue!),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  folder.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(switch (folder.type) {
                FolderType.project => 'Project',
                FolderType.client => 'Client',
                FolderType.custom => '',
              }, style: Theme.of(context).textTheme.labelSmall),
              PopupMenuButton<String>(
                key: Key('folder-menu-${folder.id}'),
                tooltip: 'Folder actions',
                onSelected: (action) => _onAction(context, state, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'add', child: Text('New session here')),
                  PopupMenuItem(
                    value: 'subfolder',
                    child: Text('New subfolder'),
                  ),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'up', child: Text('Move up')),
                  PopupMenuItem(value: 'down', child: Text('Move down')),
                  PopupMenuItem(value: 'delete', child: Text('Delete folder')),
                ],
              ),
            ],
          ),
        ),
        if (!collapsed) ...[
          for (final session in state.sessionsIn(folder.id))
            _SessionTile(session: session, depth: widget.depth + 1),
          for (final child in children)
            if (state.folderMatchesQuery(child))
              _FolderSection(folder: child, depth: widget.depth + 1),
        ],
      ],
    );
  }

  Future<void> _onAction(
    BuildContext context,
    SessionsState state,
    String action,
  ) async {
    final notifier = ref.read(sessionsProvider.notifier);
    final folder = widget.folder;
    switch (action) {
      case 'add':
        final result = await showSessionEditor(
          context,
          folders: state.sortedFolders,
          labels: state.labels,
          onCreateLabel: (name, colorValue) =>
              notifier.addLabel(name, colorValue: colorValue),
          onTestConnection: (draft, enteredSecret) async {
            final r = await runConnectionTest(
              context,
              ref,
              draft,
              enteredSecret: enteredSecret,
            );
            return (success: r.success, message: r.message);
          },
        );
        if (result == null) return;
        final moved = result.draft.groupId == folder.id
            ? result.draft
            : result.draft.copyWith(groupId: folder.id);
        await notifier.addSession(moved, secret: result.secret);
      case 'subfolder':
        final result = await showFolderEditorDialog(
          context,
          title: 'New folder',
        );
        if (result != null) {
          await notifier.addFolder(
            result.name,
            parentId: folder.id,
            type: result.type,
            icon: result.icon,
            colorValue: result.colorValue,
          );
        }
      case 'rename':
        final result = await showFolderEditorDialog(
          context,
          title: 'Rename folder',
          initial: folder.name,
          initialType: folder.type,
        );
        if (result != null) {
          await notifier.renameFolder(
            folder.id,
            result.name,
            type: result.type,
          );
        }
      case 'up':
        await notifier.moveFolder(folder.id, up: true);
      case 'down':
        await notifier.moveFolder(folder.id, up: false);
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete folder "${folder.name}"?',
          message:
              'Sessions in this folder are not deleted; they move to '
              'Ungrouped. Subfolders move up one level.',
          confirmLabel: 'Delete folder',
        );
        if (confirmed) await notifier.deleteFolder(folder.id);
    }
  }
}

class _SessionGroup extends ConsumerWidget {
  const _SessionGroup({required this.title, required this.sessions});

  final String title;
  final List<SshSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              const Icon(Icons.folder_off_outlined, size: 18),
              const SizedBox(width: 6),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
        for (final session in sessions)
          _SessionTile(session: session, depth: 1),
      ],
    );
  }
}

/// A session's label shown on its item (ADR-013): a small pill in
/// the label's colour with its name.
class SessionLabelChip extends StatelessWidget {
  const SessionLabelChip({super.key, required this.label});

  final SessionLabel label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: label.color.withValues(alpha: 0.18),
        border: Border.all(color: label.color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.name,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: label.color,
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session, required this.depth});

  final SshSession session;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    final selected = state.selectedSessionId == session.id;
    final last = session.lastConnectedAt;
    final failed = session.lastConnectionStatus == LastConnectionStatus.failed;
    final labels = state.labelsOf(session);
    // The endpoint detail moved out of the always-visible subtitle
    // (user request): it lives in the hover tooltip instead.
    final tooltip =
        '${session.username}@${session.host}:${session.port} · '
        '${last == null ? 'Never connected' : 'Last: ${_formatDate(last)}'}'
        '${failed ? ' · Last attempt failed' : ''}';
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: ListTile(
        dense: true,
        selected: selected,
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 8, right: 4),
        leading: Icon(
          appearanceIcon(session.icon, fallback: Icons.dns_outlined),
          size: 20,
          color: session.colorValue == null ? null : Color(session.colorValue!),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(session.name, overflow: TextOverflow.ellipsis),
            ),
            for (final label in labels.take(3)) ...[
              const SizedBox(width: 6),
              SessionLabelChip(label: label),
            ],
            if (labels.length > 3) ...[
              const SizedBox(width: 6),
              Text(
                '+${labels.length - 3}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          key: Key('session-menu-${session.id}'),
          tooltip: 'Session actions',
          onSelected: (action) => _onAction(context, ref, action),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            PopupMenuItem(value: 'test', child: Text('Test Connection')),
            PopupMenuItem(value: 'export', child: Text('Export profile…')),
            PopupMenuItem(value: 'move', child: Text('Move to folder…')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => ref.read(sessionsProvider.notifier).select(session.id),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final notifier = ref.read(sessionsProvider.notifier);
    final state = ref.read(sessionsProvider);
    switch (action) {
      case 'edit':
        final result = await showSessionEditor(
          context,
          initial: session,
          folders: state.sortedFolders,
          labels: state.labels,
          onCreateLabel: (name, colorValue) =>
              notifier.addLabel(name, colorValue: colorValue),
          onTestConnection: (draft, enteredSecret) async {
            final r = await runConnectionTest(
              context,
              ref,
              draft,
              enteredSecret: enteredSecret,
            );
            return (success: r.success, message: r.message);
          },
        );
        if (result != null) {
          await notifier.updateSession(result.draft, secret: result.secret);
        }
      case 'duplicate':
        final copy = await notifier.duplicateSession(session.id);
        // Spec 6.4: open the editor on the new profile so the user
        // reviews it right away (the copy is already saved;
        // cancelling the editor leaves it in the list).
        if (copy != null && context.mounted) {
          final result = await showSessionEditor(
            context,
            initial: copy,
            folders: ref.read(sessionsProvider).sortedFolders,
            labels: ref.read(sessionsProvider).labels,
            onCreateLabel: (name, colorValue) =>
                notifier.addLabel(name, colorValue: colorValue),
            onTestConnection: (draft, enteredSecret) async {
              final r = await runConnectionTest(
                context,
                ref,
                draft,
                enteredSecret: enteredSecret,
              );
              return (success: r.success, message: r.message);
            },
          );
          if (result != null) {
            await notifier.updateSession(result.draft, secret: result.secret);
          }
        }
      case 'test':
        final result = await runConnectionTest(context, ref, session);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(result.message)));
        }
      case 'export':
        await exportProfiles(
          context,
          ref,
          profiles: [session],
          suggestedName: 'heroterm-${session.name}.json',
        );
      case 'move':
        final choice = await showMoveSessionDialog(
          context,
          folders: state.sortedFolders,
        );
        if (choice.chosen) {
          await notifier.moveSession(session.id, choice.folderId);
        }
      case 'delete':
        final sharedNote =
            session.credentialRef != null &&
                state.sessions.any(
                  (s) =>
                      s.id != session.id &&
                      s.credentialRef == session.credentialRef,
                )
            ? ' Its stored credential is shared with another profile '
                  'and will be kept.'
            : '';
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete session "${session.name}"?',
          message:
              'This removes the saved profile and its stored credential. '
              'This cannot be undone.$sharedNote',
          confirmLabel: 'Delete session',
        );
        if (confirmed) await notifier.deleteSession(session.id);
    }
  }
}

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
