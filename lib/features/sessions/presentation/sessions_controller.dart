import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/credential_store.dart';
import '../data/profile_transfer.dart';
import '../data/session_repository.dart';
import '../domain/session_folder.dart';
import '../domain/session_label.dart';
import '../domain/ssh_session.dart';
import 'session_providers.dart';

const _uuid = Uuid();

final class SessionsState {
  const SessionsState({
    this.sessions = const [],
    this.folders = const [],
    this.labels = const [],
    this.query = '',
    this.selectedLabelIds = const {},
    this.isLoaded = false,
    this.selectedSessionId,
    this.errorMessage,
  });

  final List<SshSession> sessions;
  final List<SessionFolder> folders;
  final List<SessionLabel> labels;
  final String query;

  /// Label filter (ADR-013): a session is shown when it carries
  /// ALL selected labels. Combines with [query].
  final Set<String> selectedLabelIds;
  final bool isLoaded;
  final String? selectedSessionId;
  final String? errorMessage;

  SessionLabel? labelById(String id) {
    for (final l in labels) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<SessionLabel> labelsOf(SshSession session) => [
    for (final id in session.labelIds)
      if (labelById(id) != null) labelById(id)!,
  ];

  List<SshSession> get filteredSessions {
    final folderNames = {for (final f in folders) f.id: f.name};
    final labelNames = {for (final l in labels) l.id: l.name};
    return sessions
        .where(
          (s) =>
              selectedLabelIds.every(s.labelIds.contains) &&
              s.matchesQuery(
                query,
                groupName: s.groupId == null ? null : folderNames[s.groupId!],
                labelNames: [
                  for (final id in s.labelIds)
                    if (labelNames[id] != null) labelNames[id]!,
                ],
              ),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<SessionFolder> get sortedFolders => folders.toList()
    ..sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0
          ? byOrder
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  List<SshSession> sessionsIn(String? folderId) =>
      filteredSessions.where((s) => s.groupId == folderId).toList();

  SshSession? get selectedSession {
    for (final s in sessions) {
      if (s.id == selectedSessionId) return s;
    }
    return null;
  }

  bool folderMatchesQuery(SessionFolder folder) {
    if (query.trim().isEmpty && selectedLabelIds.isEmpty) return true;
    if (query.trim().isNotEmpty &&
        folder.name.toLowerCase().contains(query.trim().toLowerCase())) {
      return true;
    }
    return sessionsIn(folder.id).isNotEmpty;
  }

  SessionsState copyWith({
    List<SshSession>? sessions,
    List<SessionFolder>? folders,
    List<SessionLabel>? labels,
    String? query,
    Set<String>? selectedLabelIds,
    bool? isLoaded,
    String? selectedSessionId,
    bool clearSelection = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SessionsState(
      sessions: sessions ?? this.sessions,
      folders: folders ?? this.folders,
      labels: labels ?? this.labels,
      query: query ?? this.query,
      selectedLabelIds: selectedLabelIds ?? this.selectedLabelIds,
      isLoaded: isLoaded ?? this.isLoaded,
      selectedSessionId: clearSelection
          ? null
          : (selectedSessionId ?? this.selectedSessionId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final sessionsProvider = NotifierProvider<SessionsNotifier, SessionsState>(
  SessionsNotifier.new,
);

final class SessionsNotifier extends Notifier<SessionsState> {
  late SessionRepository _repository;
  late CredentialStore _credentials;

  @override
  SessionsState build() {
    _repository = ref.watch(sessionRepositoryProvider);
    _credentials = ref.watch(credentialStoreProvider);
    Future.microtask(_load);
    return const SessionsState();
  }

  Future<void> _load() async {
    try {
      final library = await _repository.load();
      var sessions = library.sessions;
      var labels = library.labels;
      // ADR-013 migration: turn legacy environment/tags values
      // (extracted by the repository) into real labels, assign
      // them, and persist the migrated library once.
      if (library.legacyLabelNames.isNotEmpty) {
        final now = DateTime.now();
        SessionLabel findOrCreate(String name) {
          final normalized = normalizeLabelName(name);
          for (final l in labels) {
            if (l.name.toLowerCase() == normalized.toLowerCase()) return l;
          }
          final created = SessionLabel(
            id: _uuid.v4(),
            name: normalized,
            colorValue: labelColorForName(normalized),
            createdAt: now,
            updatedAt: now,
          );
          labels = [...labels, created];
          return created;
        }

        sessions = [
          for (final s in sessions)
            library.legacyLabelNames[s.id] == null
                ? s
                : s.copyWith(
                    labelIds: {
                      ...s.labelIds,
                      for (final name in library.legacyLabelNames[s.id]!)
                        findOrCreate(name).id,
                    }.toList(),
                  ),
        ];
      }
      state = state.copyWith(
        sessions: sessions,
        folders: library.folders,
        labels: labels,
        isLoaded: true,
      );
      if (library.legacyLabelNames.isNotEmpty) await _persist();
    } catch (e) {
      state = state.copyWith(
        isLoaded: true,
        errorMessage: 'Could not load saved sessions.',
      );
    }
  }

  Future<void> _persist() async {
    try {
      await _repository.save((
        sessions: state.sessions,
        folders: state.folders,
        labels: state.labels,
        legacyLabelNames: const {},
      ));
    } catch (e) {
      state = state.copyWith(errorMessage: 'Could not save changes.');
    }
  }

  void setQuery(String query) => state = state.copyWith(query: query);

  void toggleLabelFilter(String labelId) {
    final next = {...state.selectedLabelIds};
    if (!next.remove(labelId)) next.add(labelId);
    state = state.copyWith(selectedLabelIds: next);
  }

  /// Clears the search text and the label filter (the no-results
  /// empty state's recovery action).
  void clearFilters() =>
      state = state.copyWith(query: '', selectedLabelIds: const {});

  // --- Labels (ADR-013) ---

  /// Creates a label, or returns the existing one with the same
  /// name (case-insensitive) so duplicates never fork.
  Future<SessionLabel> addLabel(String name, {int? colorValue}) async {
    final normalized = normalizeLabelName(name);
    for (final l in state.labels) {
      if (l.name.toLowerCase() == normalized.toLowerCase()) return l;
    }
    final now = DateTime.now();
    final label = SessionLabel(
      id: _uuid.v4(),
      name: normalized,
      colorValue: colorValue ?? labelColorForName(normalized),
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(labels: [...state.labels, label]);
    await _persist();
    return label;
  }

  Future<void> renameLabel(String labelId, String name) async {
    final normalized = normalizeLabelName(name);
    if (normalized.isEmpty) return;
    state = state.copyWith(
      labels: [
        for (final l in state.labels)
          l.id == labelId
              ? l.copyWith(name: normalized, updatedAt: DateTime.now())
              : l,
      ],
    );
    await _persist();
  }

  Future<void> setLabelColor(String labelId, int colorValue) async {
    state = state.copyWith(
      labels: [
        for (final l in state.labels)
          l.id == labelId
              ? l.copyWith(colorValue: colorValue, updatedAt: DateTime.now())
              : l,
      ],
    );
    await _persist();
  }

  /// Deletes a label and detaches it from every session.
  Future<void> deleteLabel(String labelId) async {
    state = state.copyWith(
      labels: state.labels.where((l) => l.id != labelId).toList(),
      sessions: [
        for (final s in state.sessions)
          s.labelIds.contains(labelId)
              ? s.copyWith(
                  labelIds: s.labelIds.where((id) => id != labelId).toList(),
                )
              : s,
      ],
      selectedLabelIds: {...state.selectedLabelIds}..remove(labelId),
    );
    await _persist();
  }

  /// Resolves label names to IDs, creating missing labels with
  /// their canonical/palette colours. Used by imports.
  Future<List<String>> resolveLabelIds(Iterable<String> names) async {
    final ids = <String>[];
    for (final name in names) {
      final label = await addLabel(name);
      if (!ids.contains(label.id)) ids.add(label.id);
    }
    return ids;
  }

  void select(String? sessionId) => state = state.copyWith(
    selectedSessionId: sessionId,
    clearSelection: sessionId == null,
  );

  /// Creates a session. When [secret] is non-empty it is stored in the
  /// credential store (Keychain) under a fresh reference; the secret
  /// itself never enters the session model or the JSON library.
  Future<SshSession> addSession(SshSession draft, {String? secret}) async {
    var session = draft;
    if (secret != null && secret.isNotEmpty) {
      final ref = _uuid.v4();
      await _credentials.write(ref, secret);
      session = draft.copyWith(credentialRef: ref);
    }
    state = state.copyWith(sessions: [...state.sessions, session]);
    await _persist();
    return session;
  }

  /// Updates a session. [secret] semantics: null = keep the existing
  /// secret, empty = remove it, non-empty = replace it.
  ///
  /// Copy-on-write for shared references (profile spec 6.4): when
  /// the session's credential reference is shared with another
  /// profile (the state a duplicate starts in), replacing or
  /// removing the secret never touches the shared entry — a
  /// replacement is written under a FRESH reference owned by this
  /// profile alone, and a removal only detaches this profile.
  Future<void> updateSession(SshSession updated, {String? secret}) async {
    var session = updated;
    if (secret != null) {
      final oldRef = session.credentialRef;
      final shared =
          oldRef != null &&
          state.sessions.any(
            (s) => s.id != session.id && s.credentialRef == oldRef,
          );
      if (secret.isEmpty) {
        if (oldRef != null && !shared) await _credentials.delete(oldRef);
        session = session.copyWith(clearCredentialRef: true);
      } else {
        final ref = (oldRef == null || shared) ? _uuid.v4() : oldRef;
        await _credentials.write(ref, secret);
        session = session.copyWith(credentialRef: ref);
      }
    }
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions) s.id == session.id ? session : s,
      ],
    );
    await _persist();
  }

  /// Duplicates a session (profile spec 6.4): new ID, the name
  /// `<original> Copy` with a numeric suffix when taken, all
  /// non-secret configuration copied. The secret is NOT copied:
  /// the duplicate SHARES the original's credential reference, so
  /// it connects immediately; the sharing is safe because edits
  /// copy-on-write (see [updateSession]) and deletes only remove
  /// a credential when no profile references it anymore. The UI
  /// opens the editor on the copy so the user can review it.
  Future<SshSession?> duplicateSession(String sessionId) async {
    final original = state.selectedSessionById(sessionId);
    if (original == null) return null;
    final now = DateTime.now();
    final taken = state.sessions.map((s) => s.name).toSet();
    var name = '${original.name} Copy';
    var n = 2;
    while (taken.contains(name)) {
      name = '${original.name} Copy ${n++}';
    }
    final copy = SshSession(
      id: _uuid.v4(),
      name: name,
      host: original.host,
      port: original.port,
      username: original.username,
      authMethod: original.authMethod,
      credentialRef: original.credentialRef,
      privateKeyPath: original.privateKeyPath,
      groupId: original.groupId,
      description: original.description,
      labelIds: original.labelIds,
      icon: original.icon,
      colorValue: original.colorValue,
      connectionTimeout: original.connectionTimeout,
      startupDirectory: original.startupDirectory,
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(sessions: [...state.sessions, copy]);
    await _persist();
    return copy;
  }

  Future<void> deleteSession(String sessionId) async {
    final target = state.selectedSessionById(sessionId);
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != sessionId).toList(),
      clearSelection: state.selectedSessionId == sessionId,
    );
    await _persist();
    final ref = target?.credentialRef;
    if (ref != null && !state.sessions.any((s) => s.credentialRef == ref)) {
      await _credentials.delete(ref);
    }
  }

  /// Records a successful connection (Milestone 2): updates the
  /// last-connected timestamp shown in the session list, and the
  /// last-attempt outcome (profile spec section 5).
  Future<void> markConnected(String sessionId) async {
    final now = DateTime.now();
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          s.id == sessionId
              ? s.copyWith(
                  lastConnectedAt: now,
                  lastConnectionStatus: LastConnectionStatus.success,
                  updatedAt: now,
                )
              : s,
      ],
    );
    await _persist();
  }

  /// Records a failed connection attempt (outcome only — never any
  /// error detail or credential material).
  Future<void> markConnectionFailed(String sessionId) async {
    if (!state.sessions.any((s) => s.id == sessionId)) return;
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          s.id == sessionId
              ? s.copyWith(
                  lastConnectionStatus: LastConnectionStatus.failed,
                  updatedAt: DateTime.now(),
                )
              : s,
      ],
    );
    await _persist();
  }

  Future<void> moveSession(String sessionId, String? folderId) async {
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          s.id == sessionId
              ? (folderId == null
                    ? s.copyWith(clearGroupId: true, updatedAt: DateTime.now())
                    : s.copyWith(groupId: folderId, updatedAt: DateTime.now()))
              : s,
      ],
    );
    await _persist();
  }

  Future<SessionFolder> addFolder(
    String name, {
    String? parentId,
    FolderType type = FolderType.custom,
    String? icon,
    int? colorValue,
  }) async {
    final siblings = state.folders.where((f) => f.parentId == parentId).length;
    final now = DateTime.now();
    final folder = SessionFolder(
      id: _uuid.v4(),
      name: name,
      parentId: parentId,
      type: type,
      icon: icon,
      colorValue: colorValue,
      sortOrder: siblings,
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(folders: [...state.folders, folder]);
    await _persist();
    return folder;
  }

  Future<void> renameFolder(
    String folderId,
    String name, {
    FolderType? type,
    String? icon,
    bool clearIcon = false,
    int? colorValue,
    bool clearColor = false,
  }) async {
    state = state.copyWith(
      folders: [
        for (final f in state.folders)
          f.id == folderId
              ? f.copyWith(
                  name: name,
                  type: type,
                  icon: icon,
                  clearIcon: clearIcon,
                  colorValue: colorValue,
                  clearColor: clearColor,
                  updatedAt: DateTime.now(),
                )
              : f,
      ],
    );
    await _persist();
  }

  /// Applies a validated import (profile spec 6.5). Groups resolve
  /// by name + type: an existing folder is reused, a missing one is
  /// created. Conflicts follow [strategy] — never a silent
  /// overwrite. Update keeps the existing profile's ID, creation
  /// time and stored credential (imports carry no secrets).
  /// Imported profiles are never auto-connected.
  Future<({int added, int updated, int skipped})> importProfiles(
    List<ImportedProfile> imported,
    ImportConflictStrategy strategy,
  ) async {
    var sessions = [...state.sessions];
    var folders = [...state.folders];
    var labels = [...state.labels];
    var added = 0, updated = 0, skipped = 0;
    final now = DateTime.now();

    String resolveLabelId(String name) {
      final normalized = normalizeLabelName(name);
      for (final l in labels) {
        if (l.name.toLowerCase() == normalized.toLowerCase()) return l.id;
      }
      final created = SessionLabel(
        id: _uuid.v4(),
        name: normalized,
        colorValue: labelColorForName(normalized),
        createdAt: now,
        updatedAt: now,
      );
      labels = [...labels, created];
      return created.id;
    }

    String? resolveGroup(ImportedProfile profile) {
      final name = profile.groupName;
      if (name == null) return null;
      for (final f in folders) {
        if (f.name.toLowerCase() == name.toLowerCase() &&
            f.type == profile.groupType) {
          return f.id;
        }
      }
      final folder = SessionFolder(
        id: _uuid.v4(),
        name: name,
        type: profile.groupType,
        sortOrder: folders.where((f) => f.parentId == null).length,
        createdAt: now,
        updatedAt: now,
      );
      folders = [...folders, folder];
      return folder.id;
    }

    String uniqueName(String base, Iterable<String> taken) {
      var candidate = base;
      var n = 2;
      final takenLower = taken.map((t) => t.toLowerCase()).toSet();
      while (takenLower.contains(candidate.toLowerCase())) {
        candidate = '$base Copy ${n++}';
      }
      return candidate;
    }

    SshSession materialize(
      SshSession d, {
      required String id,
      required String? groupId,
      required List<String> labelIds,
      String? name,
    }) {
      return SshSession(
        id: id,
        name: name ?? d.name,
        host: d.host,
        port: d.port,
        username: d.username,
        authMethod: d.authMethod,
        privateKeyPath: d.privateKeyPath,
        groupId: groupId,
        description: d.description,
        labelIds: labelIds,
        icon: d.icon,
        colorValue: d.colorValue,
        connectionTimeout: d.connectionTimeout,
        startupDirectory: d.startupDirectory,
        createdAt: now,
        updatedAt: now,
      );
    }

    for (final profile in imported) {
      String keyOf(SshSession s) =>
          '${s.name.toLowerCase()}|${s.host.toLowerCase()}|'
          '${s.username}|${s.port}';
      final conflictIndex = sessions.indexWhere(
        (s) => keyOf(s) == profile.conflictKey,
      );
      final groupId = resolveGroup(profile);
      final resolvedLabelIds = [
        for (final name in profile.labelNames) resolveLabelId(name),
      ];
      if (conflictIndex < 0) {
        sessions = [
          ...sessions,
          materialize(
            profile.draft,
            id: _uuid.v4(),
            groupId: groupId,
            labelIds: resolvedLabelIds,
          ),
        ];
        added++;
        continue;
      }
      switch (strategy) {
        case ImportConflictStrategy.skip:
          skipped++;
        case ImportConflictStrategy.copy:
          sessions = [
            ...sessions,
            materialize(
              profile.draft,
              id: _uuid.v4(),
              groupId: groupId,
              labelIds: resolvedLabelIds,
              name: uniqueName(profile.draft.name, sessions.map((s) => s.name)),
            ),
          ];
          added++;
        case ImportConflictStrategy.update:
          final existing = sessions[conflictIndex];
          final d = profile.draft;
          // The imported fields win; identity, audit history and —
          // critically — the stored credential reference survive,
          // because an import file never carries secrets.
          sessions[conflictIndex] = SshSession(
            id: existing.id,
            name: d.name,
            host: d.host,
            port: d.port,
            username: d.username,
            authMethod: d.authMethod,
            credentialRef: existing.credentialRef,
            privateKeyPath: d.privateKeyPath,
            groupId: groupId,
            description: d.description,
            labelIds: resolvedLabelIds,
            icon: d.icon,
            colorValue: d.colorValue,
            connectionTimeout: d.connectionTimeout,
            startupDirectory: d.startupDirectory,
            createdAt: existing.createdAt,
            updatedAt: now,
            lastConnectedAt: existing.lastConnectedAt,
            lastConnectionStatus: existing.lastConnectionStatus,
          );
          updated++;
      }
    }
    state = state.copyWith(
      sessions: sessions,
      folders: folders,
      labels: labels,
    );
    await _persist();
    return (added: added, updated: updated, skipped: skipped);
  }

  /// Documented delete behavior (Milestone 1 acceptance): deleting a
  /// folder never deletes its sessions. Sessions move to Ungrouped and
  /// subfolders move to the deleted folder's parent. The UI confirms
  /// with the user before calling this.
  Future<void> deleteFolder(String folderId) async {
    final target = _firstOrNull(state.folders.where((f) => f.id == folderId));
    if (target == null) return;
    final now = DateTime.now();
    state = state.copyWith(
      sessions: [
        for (final s in state.sessions)
          s.groupId == folderId
              ? s.copyWith(clearGroupId: true, updatedAt: now)
              : s,
      ],
      folders: [
        for (final f in state.folders)
          if (f.id != folderId)
            f.parentId == folderId
                ? (target.parentId == null
                      ? f.copyWith(clearParentId: true, updatedAt: now)
                      : f.copyWith(parentId: target.parentId, updatedAt: now))
                : f,
      ],
    );
    await _persist();
  }

  /// Reorders a folder among its siblings by swapping sort order.
  Future<void> moveFolder(String folderId, {required bool up}) async {
    final siblings = state.sortedFolders
        .where(
          (f) =>
              f.parentId ==
              _firstOrNull(state.folders.where((x) => x.id == folderId))
                  ?.parentId,
        )
        .toList();
    final index = siblings.indexWhere((f) => f.id == folderId);
    final swapIndex = up ? index - 1 : index + 1;
    if (index < 0 || swapIndex < 0 || swapIndex >= siblings.length) return;
    final a = siblings[index];
    final b = siblings[swapIndex];
    final now = DateTime.now();
    state = state.copyWith(
      folders: [
        for (final f in state.folders)
          if (f.id == a.id)
            f.copyWith(sortOrder: b.sortOrder, updatedAt: now)
          else if (f.id == b.id)
            f.copyWith(sortOrder: a.sortOrder, updatedAt: now)
          else
            f,
      ],
    );
    await _persist();
  }
}

T? _firstOrNull<T>(Iterable<T> items) => items.isEmpty ? null : items.first;

extension on SessionsState {
  SshSession? selectedSessionById(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }
}
