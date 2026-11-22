import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../data/id_name_resolver.dart';
import '../data/remote_file_service.dart';
import '../domain/remote_entry.dart';
import '../domain/remote_path.dart';

final class ExplorerState {
  const ExplorerState({
    this.currentPath,
    this.entries = const [],
    this.isLoading = false,
    this.error,
    this.notice,
    this.showHidden = false,
    this.followCwd = true,
    this.transferName,
    this.transferLabel,
    this.transferDone = 0,
    this.transferTotal,
    this.recentPaths = const [],
    this.sortColumn = ExplorerSortColumn.name,
    this.sortAscending = true,
    this.ownerNames = const {},
    this.groupNames = const {},
    this.selectedPath,
  });

  /// Null while no explorer is attached to a connection.
  final String? currentPath;
  final List<RemoteEntry> entries;
  final bool isLoading;
  final AppError? error;

  /// Transient success/info line (e.g. a finished download).
  final String? notice;
  final bool showHidden;
  final bool followCwd;

  /// Name of the file currently transferring, or null.
  final String? transferName;

  /// Optional richer label, e.g. "Uploading a.txt (2 of 5)".
  final String? transferLabel;
  final int transferDone;
  final int? transferTotal;

  bool get isTransferring => transferName != null;

  /// Recently visited directories, most recent first (max 12).
  final List<String> recentPaths;

  double? get transferProgress {
    final total = transferTotal;
    if (transferName == null || total == null || total == 0) return null;
    return transferDone / total;
  }

  /// Table sort state (table-view spec): one primary column.
  final ExplorerSortColumn sortColumn;
  final bool sortAscending;

  /// Best-effort UID→username and GID→group-name maps resolved once
  /// per connection from the server's account databases. Empty when
  /// the server could not provide them — labels then fall back to
  /// the numeric IDs, never to a guess.
  final Map<int, String> ownerNames;
  final Map<int, String> groupNames;

  /// Path of the selected table row, if any.
  final String? selectedPath;

  /// Display label for an entry's owner: resolved name, else the
  /// numeric UID, else an em dash when the server reported none.
  String ownerLabelOf(RemoteEntry entry) {
    final uid = entry.uid;
    if (uid == null) return '—';
    return ownerNames[uid] ?? '$uid';
  }

  /// Display label for an entry's group (same fallback as owner).
  String groupLabelOf(RemoteEntry entry) {
    final gid = entry.gid;
    if (gid == null) return '—';
    return groupNames[gid] ?? '$gid';
  }

  List<RemoteEntry> get visible {
    final filtered = entries.where((e) => showHidden || !e.isHidden).toList();
    return sortEntries(
      filtered,
      column: sortColumn,
      ascending: sortAscending,
      ownerLabel: ownerLabelOf,
      groupLabel: groupLabelOf,
    );
  }

  ExplorerState copyWith({
    String? currentPath,
    List<RemoteEntry>? entries,
    bool? isLoading,
    AppError? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    bool? showHidden,
    bool? followCwd,
    String? transferName,
    String? transferLabel,
    bool clearTransfer = false,
    int? transferDone,
    int? transferTotal,
    List<String>? recentPaths,
    ExplorerSortColumn? sortColumn,
    bool? sortAscending,
    Map<int, String>? ownerNames,
    Map<int, String>? groupNames,
    String? selectedPath,
    bool clearSelectedPath = false,
  }) {
    return ExplorerState(
      currentPath: currentPath ?? this.currentPath,
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
      showHidden: showHidden ?? this.showHidden,
      followCwd: followCwd ?? this.followCwd,
      transferName: clearTransfer ? null : (transferName ?? this.transferName),
      transferLabel: clearTransfer
          ? null
          : (transferLabel ?? this.transferLabel),
      transferDone: clearTransfer ? 0 : (transferDone ?? this.transferDone),
      transferTotal: clearTransfer
          ? null
          : (transferTotal ?? this.transferTotal),
      recentPaths: recentPaths ?? this.recentPaths,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      ownerNames: ownerNames ?? this.ownerNames,
      groupNames: groupNames ?? this.groupNames,
      selectedPath: clearSelectedPath
          ? null
          : (selectedPath ?? this.selectedPath),
    );
  }
}

/// How to resolve an upload filename collision.
enum CollisionChoice { overwrite, rename, skip }

/// The user's answer for one collision; [applyToAll] reuses the
/// choice for the rest of the batch.
typedef CollisionAnswer = ({CollisionChoice choice, bool applyToAll});

/// Asks the user how to handle one colliding upload target.
/// Returning null cancels the whole batch.
typedef CollisionResolver = Future<CollisionAnswer?> Function(
  String fileName,
  String remotePath,
);

final explorerProvider = NotifierProvider<ExplorerNotifier, ExplorerState>(
  ExplorerNotifier.new,
);

final class ExplorerNotifier extends Notifier<ExplorerState> {
  RemoteFileService? _service;
  int _requestId = 0;

  @override
  ExplorerState build() => const ExplorerState();

  bool get isAttached => _service != null;

  /// Attaches the explorer to a live connection and loads the first
  /// directory: the shell's reported cwd when already known, else
  /// the profile's startup directory, else the SFTP home directory.
  Future<void> attach(
    RemoteFileService service, {
    String? reportedCwd,
    String? startupDirectory,
    String? preferredPath,
    Future<IdNameMaps?> Function()? fetchIdNames,
  }) async {
    _service = service;
    final start =
        reportedCwd ??
        preferredPath ??
        (startupDirectory != null && startupDirectory.trim().isNotEmpty
            ? RemotePath.normalize(startupDirectory.trim())
            : await service.homeDirectory());
    await _load(start);
    // Owner/group name resolution is decoration on top of the
    // numeric IDs: fetch once per connection, apply when it lands,
    // and never let it fail the attach.
    if (fetchIdNames != null) {
      unawaited(
        fetchIdNames()
            .then((maps) {
              if (maps == null || !identical(_service, service)) return;
              state = state.copyWith(
                ownerNames: maps.users,
                groupNames: maps.groups,
              );
            })
            .catchError((_) {}),
      );
    }
  }

  void detach() {
    cancelDownload();
    _service = null;
    _requestId++;
    state = const ExplorerState();
  }

  Future<void> navigateTo(String path) => _load(RemotePath.normalize(path));

  Future<void> refresh() async {
    final path = state.currentPath;
    if (path == null || _service == null) return;
    await _load(path);
  }

  /// Called when the terminal reports a new working directory.
  /// Navigation failures keep the previous directory (acceptance:
  /// errors never silently change the current path).
  Future<void> onRemoteCwd(String path) async {
    if (_service == null || !state.followCwd) return;
    if (RemotePath.normalize(path) == state.currentPath) return;
    await _load(RemotePath.normalize(path), fromCwdReport: true);
  }

  void setShowHidden(bool value) => state = state.copyWith(showHidden: value);
  void setFollowCwd(bool value) => state = state.copyWith(followCwd: value);

  /// Table header click: a new column sorts ascending; clicking the
  /// active column toggles direction (table-view spec). Sorting is
  /// client-side over the already-fetched metadata — no SSH traffic.
  void setSort(ExplorerSortColumn column) {
    if (column == state.sortColumn) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(sortColumn: column, sortAscending: true);
    }
  }

  /// Selects (or clears) the highlighted table row.
  void selectEntry(String? path) {
    state = path == null
        ? state.copyWith(clearSelectedPath: true)
        : state.copyWith(selectedPath: path);
  }

  void dismissNotice() => state = state.copyWith(clearNotice: true);

  AppError _asAppError(Object e, String fallback) => e is AppError
      ? e
      : AppError(
          category: AppErrorCategory.unknown,
          userMessage: fallback,
          diagnostic: e.runtimeType.toString(),
        );

  // -- Milestone 4: file actions -------------------------------------

  /// Renames [entry] to [newName] in the same directory. Returns an
  /// error message for the dialog (collision/invalid), or null when
  /// the rename succeeded and the listing was refreshed.
  Future<String?> renameEntry(RemoteEntry entry, String newName) async {
    final service = _service;
    if (service == null) return 'Not connected.';
    final invalid = RemotePath.validateNewName(newName);
    if (invalid != null) return invalid;
    if (newName == entry.name) return null;
    final target = RemotePath.join(RemotePath.parentOf(entry.path), newName);
    try {
      if (await service.exists(target)) {
        return 'A file or folder named "$newName" already exists here.';
      }
      await service.rename(entry.path, target);
    } catch (e) {
      final error = _asAppError(e, 'Could not rename ${entry.name}.');
      state = state.copyWith(error: error);
      return error.userMessage;
    }
    await refresh();
    return null;
  }

  /// Deletes [entry] (directories recursively — the UI confirms
  /// first). Returns an error message or null on success.
  Future<String?> deleteEntry(RemoteEntry entry) async {
    final service = _service;
    if (service == null) return 'Not connected.';
    try {
      if (entry.kind == RemoteEntryKind.directory) {
        await service.deleteRecursively(entry.path);
      } else {
        await service.deleteFile(entry.path);
      }
    } catch (e) {
      final error = _asAppError(e, 'Could not delete ${entry.name}.');
      state = state.copyWith(error: error);
      return error.userMessage;
    }
    await refresh();
    return null;
  }

  bool _downloadCancelled = false;
  StreamSubscription<List<int>>? _downloadSub;
  Future<void> Function()? _downloadClose;

  void cancelDownload() {
    _downloadCancelled = true;
    unawaited(_downloadSub?.cancel());
    final close = _downloadClose;
    if (close != null) unawaited(close());
  }

  /// Downloads [entry] (a file) to the local [localPath] chosen by
  /// the user, reporting progress in the state. A cancelled or
  /// failed download removes the partial local file; failures land
  /// in the state's error so the UI stays recoverable.
  Future<void> downloadEntry(RemoteEntry entry, String localPath) async {
    final service = _service;
    if (service == null || state.isTransferring) return;
    _downloadCancelled = false;
    state = state.copyWith(
      transferName: entry.name,
      transferDone: 0,
      transferTotal: entry.size,
      clearError: true,
      clearNotice: true,
    );
    IOSink? sink;
    try {
      final handle = await service.openDownload(entry.path);
      _downloadClose = handle.close;
      state = state.copyWith(transferTotal: handle.totalBytes ?? entry.size);
      final file = File(localPath);
      sink = file.openWrite();
      var done = 0;
      var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
      final finished = Completer<void>();
      _downloadSub = handle.stream.listen(
        (chunk) {
          if (_downloadCancelled) return;
          sink?.add(chunk);
          done += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastPaint).inMilliseconds >= 100) {
            lastPaint = now;
            state = state.copyWith(transferDone: done);
          }
        },
        onError: finished.completeError,
        onDone: finished.complete,
        cancelOnError: true,
      );
      await finished.future;
      if (_downloadCancelled) throw const _DownloadCancelled();
      await sink.flush();
      await sink.close();
      sink = null;
      state = state.copyWith(
        clearTransfer: true,
        notice: 'Downloaded ${entry.name} to $localPath',
      );
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await File(localPath).delete();
      } catch (_) {}
      if (e is _DownloadCancelled || _downloadCancelled) {
        state = state.copyWith(
          clearTransfer: true,
          notice: 'Download cancelled; partial file removed.',
        );
      } else {
        state = state.copyWith(
          clearTransfer: true,
          error: _asAppError(e, 'Could not download ${entry.name}.'),
        );
      }
    } finally {
      _downloadSub = null;
      _downloadClose = null;
    }
  }

  // -- Milestone 5: drag-and-drop upload ----------------------------

  bool _uploadCancelled = false;
  UploadHandle? _activeUpload;

  void cancelUpload() {
    _uploadCancelled = true;
    final active = _activeUpload;
    if (active != null) unawaited(active.abort());
  }

  /// Uploads local files (and folders, recursively) dropped by the
  /// user into the current remote directory. [askCollision] decides
  /// per colliding file: overwrite, rename, or skip; returning null
  /// cancels the whole batch. Progress is reported through the
  /// transfer state; a cancelled/failed file never counts as
  /// uploaded, and the partial remote file is removed on cancel.
  Future<void> uploadLocalPaths(
    List<String> localPaths, {
    required CollisionResolver askCollision,
  }) async {
    final service = _service;
    final current = state.currentPath;
    if (service == null || current == null) {
      state = state.copyWith(
        error: const AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'Connect to a server before dropping files.',
        ),
      );
      return;
    }
    if (state.isTransferring) {
      state = state.copyWith(notice: 'A transfer is already in progress.');
      return;
    }

    // Expand dropped items into (local path, remote relative path)
    // file items plus the remote subdirectories to create.
    final items = <({String local, String rel})>[];
    final dirs = <String>{};
    final unreadable = <String>[];
    for (final dropped in localPaths) {
      final type = FileSystemEntity.typeSync(dropped);
      if (type == FileSystemEntityType.notFound) {
        unreadable.add(dropped);
      } else if (type == FileSystemEntityType.file) {
        items.add((local: dropped, rel: _baseName(dropped)));
      } else if (type == FileSystemEntityType.directory) {
        final rootName = _baseName(dropped);
        dirs.add(rootName);
        for (final entity in Directory(dropped).listSync(recursive: true)) {
          final rel = entity.path
              .substring(dropped.length)
              .replaceAll(Platform.pathSeparator, '/')
              .replaceFirst(RegExp('^/'), '');
          final remoteRel = '$rootName/$rel';
          if (entity is Directory) {
            dirs.add(remoteRel);
          } else if (entity is File) {
            items.add((local: entity.path, rel: remoteRel));
          }
        }
      }
    }
    if (items.isEmpty) {
      state = state.copyWith(
        error: unreadable.isNotEmpty
            ? AppError(
                category: AppErrorCategory.permissionDenied,
                userMessage:
                    'Could not read the dropped file(s): '
                    '${unreadable.join(', ')}. The app may not have '
                    'permission to access them.',
              )
            : null,
        notice: unreadable.isEmpty ? 'Nothing to upload.' : null,
      );
      return;
    }
    items.sort((a, b) => a.rel.compareTo(b.rel));

    _uploadCancelled = false;
    CollisionChoice? batchChoice;
    var uploaded = 0;
    var skipped = 0;
    final failed = <String>[];

    // Create remote subdirectories first (shallowest first).
    final sortedDirs = dirs.toList()
      ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));
    for (final dir in sortedDirs) {
      final target = RemotePath.join(current, dir);
      try {
        if (!await service.exists(target)) {
          await service.createDirectory(target);
        }
      } catch (e) {
        failed.add('$dir (${_asAppError(e, 'mkdir failed').userMessage})');
      }
    }

    for (var i = 0; i < items.length; i++) {
      if (_uploadCancelled) break;
      final item = items[i];
      var target = RemotePath.join(current, item.rel);
      final name = item.rel.split('/').last;

      if (await service.exists(target)) {
        var choice = batchChoice;
        if (choice == null) {
          final answer = await askCollision(name, target);
          if (answer == null) {
            _uploadCancelled = true;
            break;
          }
          choice = answer.choice;
          if (answer.applyToAll) batchChoice = choice;
        }
        switch (choice) {
          case CollisionChoice.skip:
            skipped++;
            continue;
          case CollisionChoice.rename:
            target = await _firstFreeName(service, target);
          case CollisionChoice.overwrite:
            break;
        }
      }

      final size = await File(item.local).length();
      state = state.copyWith(
        transferName: name,
        transferLabel: 'Uploading $name (${i + 1} of ${items.length})',
        transferDone: 0,
        transferTotal: size,
        clearError: true,
      );
      UploadHandle? handle;
      try {
        handle = await service.openUpload(target);
        _activeUpload = handle;
        var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
        await handle.write(File(item.local).openRead(), (sent) {
          final now = DateTime.now();
          if (now.difference(lastPaint).inMilliseconds >= 100) {
            lastPaint = now;
            state = state.copyWith(transferDone: sent);
          }
        });
        await handle.close();
        if (_uploadCancelled) throw const _DownloadCancelled();
        uploaded++;
        state = state.copyWith(transferDone: size);
        await refresh();
      } catch (e) {
        try {
          await handle?.abort();
        } catch (_) {}
        if (_uploadCancelled || e is _DownloadCancelled) {
          // Never leave a partial upload looking like a real file.
          try {
            await service.deleteFile(target);
          } catch (_) {}
          break;
        }
        failed.add('$name (${_asAppError(e, 'upload failed').userMessage})');
      } finally {
        _activeUpload = null;
      }
    }

    if (_uploadCancelled) {
      state = state.copyWith(
        clearTransfer: true,
        notice: 'Upload cancelled. $uploaded file(s) had completed.',
      );
    } else if (failed.isNotEmpty) {
      state = state.copyWith(
        clearTransfer: true,
        error: AppError(
          category: AppErrorCategory.unknown,
          userMessage:
              'Uploaded $uploaded of ${items.length} file(s); '
              '${skipped > 0 ? 'skipped $skipped; ' : ''}'
              'failed: ${failed.join('; ')}',
        ),
      );
    } else {
      state = state.copyWith(
        clearTransfer: true,
        notice:
            'Uploaded $uploaded file(s) to $current'
            '${skipped > 0 ? ' ($skipped skipped)' : ''}.',
      );
    }
  }

  Future<String> _firstFreeName(
    RemoteFileService service,
    String target,
  ) async {
    final parent = RemotePath.parentOf(target);
    final name = target.split('/').last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var n = 1; n < 1000; n++) {
      final candidate = RemotePath.join(parent, '$base ($n)$ext');
      if (!await service.exists(candidate)) return candidate;
    }
    return RemotePath.join(parent, '$base (copy)$ext');
  }

  String _baseName(String path) =>
      path.replaceAll(RegExp(r'/+$'), '').split('/').last;

  Future<void> _load(String path, {bool fromCwdReport = false}) async {
    final service = _service;
    if (service == null) return;
    final requestId = ++_requestId;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final canonical = await service.canonicalize(path);
      final entries = await service.list(canonical);
      if (requestId != _requestId) return;
      // Most-recent-first history for the path bar's dropdown;
      // consecutive duplicates collapse and the list is capped.
      final history = <String>[
        canonical,
        for (final p in state.recentPaths)
          if (p != canonical) p,
      ];
      if (history.length > 12) history.removeRange(12, history.length);
      state = state.copyWith(
        currentPath: canonical,
        entries: entries,
        isLoading: false,
        recentPaths: history,
        clearSelectedPath: true,
      );
    } catch (e) {
      if (requestId != _requestId) return;
      final error = e is AppError
          ? e
          : AppError(
              category: AppErrorCategory.unknown,
              userMessage: 'Could not read $path.',
              diagnostic: e.runtimeType.toString(),
            );
      // Keep the old path and listing visible under the error: a
      // failed cd target or a permission-denied folder must not blank
      // the explorer or pretend the path changed.
      state = state.copyWith(isLoading: false, error: error);
    }
  }
}

final class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
