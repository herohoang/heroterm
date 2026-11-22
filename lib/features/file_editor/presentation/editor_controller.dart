import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/ui_preferences.dart';
import '../../../core/errors/app_error.dart';
import '../../connection/presentation/terminal_sessions.dart';
import '../../remote_explorer/data/remote_file_service.dart';
import '../../remote_explorer/domain/remote_entry.dart';
import '../../remote_explorer/domain/remote_path.dart';
import '../../remote_explorer/presentation/explorer_controller.dart';
import '../../sessions/domain/ssh_session.dart';
import '../data/external_editor.dart';
import '../domain/text_file_rules.dart';
import 'highlighting.dart';

/// How a document's content is edited (Edit File spec §2).
enum EditorDocKind { builtin, external }

enum SaveOutcome { saved, conflict, failed }

/// External-edit sync lifecycle (§2.3): watching for changes, a
/// stable change waiting to sync (Auto Sync off), a sync in
/// flight, or a failed sync whose local copy is preserved.
enum ExternalSyncState { watching, changed, syncing, error }

/// One open file in the workspace. Built-in documents own a
/// [TextEditingController]; external documents own a temp file
/// watched for changes. Documents keep their content when their
/// terminal tab disconnects — only saving needs the connection,
/// and a failed save never loses content (§2.4/§4).
final class EditorDocument {
  const EditorDocument({
    required this.id,
    required this.kind,
    required this.tabId,
    required this.sessionId,
    required this.profileName,
    required this.remotePath,
    required this.fileName,
    required this.language,
    this.textController,
    this.undoController,
    this.savedText = '',
    this.savedBytes = const [],
    this.hasBom = false,
    this.remoteStat,
    this.isLoading = false,
    this.isSaving = false,
    this.isDirty = false,
    this.errorMessage,
    this.localPath,
    this.syncState = ExternalSyncState.watching,
    this.hasUnsyncedChanges = false,
    this.lastSyncedAt,
  });

  final String id;
  final EditorDocKind kind;

  /// The terminal tab whose connection serves this file.
  final String tabId;

  /// The saved profile's ID (Smart Save records key on this).
  final String sessionId;
  final String profileName;
  final String remotePath;
  final String fileName;
  final EditorLanguage language;

  // Built-in editing state.
  final TextEditingController? textController;
  final UndoHistoryController? undoController;

  /// Baseline content as last loaded/saved. Dirty = current text
  /// differs (built-in) or the temp file has unsynced changes.
  final String savedText;
  final List<int> savedBytes;
  final bool hasBom;

  /// Remote size/mtime captured at load and after each save —
  /// the conflict-detection baseline (§4).
  final RemoteFileStat? remoteStat;

  final bool isLoading;
  final bool isSaving;
  final bool isDirty;
  final String? errorMessage;

  // External editing state.
  final String? localPath;
  final ExternalSyncState syncState;
  final bool hasUnsyncedChanges;
  final DateTime? lastSyncedAt;

  EditorDocument copyWith({
    String? savedText,
    List<int>? savedBytes,
    bool? hasBom,
    RemoteFileStat? remoteStat,
    bool? isLoading,
    bool? isSaving,
    bool? isDirty,
    String? errorMessage,
    bool clearError = false,
    ExternalSyncState? syncState,
    bool? hasUnsyncedChanges,
    DateTime? lastSyncedAt,
  }) {
    return EditorDocument(
      id: id,
      kind: kind,
      tabId: tabId,
      sessionId: sessionId,
      profileName: profileName,
      remotePath: remotePath,
      fileName: fileName,
      language: language,
      textController: textController,
      undoController: undoController,
      savedText: savedText ?? this.savedText,
      savedBytes: savedBytes ?? this.savedBytes,
      hasBom: hasBom ?? this.hasBom,
      remoteStat: remoteStat ?? this.remoteStat,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isDirty: isDirty ?? this.isDirty,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      localPath: localPath,
      syncState: syncState ?? this.syncState,
      hasUnsyncedChanges: hasUnsyncedChanges ?? this.hasUnsyncedChanges,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

final class EditorState {
  const EditorState({this.documents = const [], this.activeDocumentId});

  final List<EditorDocument> documents;

  /// The document shown in the workspace; null = the terminal
  /// surface is showing.
  final String? activeDocumentId;

  EditorDocument? get activeDocument {
    for (final doc in documents) {
      if (doc.id == activeDocumentId) return doc;
    }
    return null;
  }

  EditorDocument? docById(String id) {
    for (final doc in documents) {
      if (doc.id == id) return doc;
    }
    return null;
  }

  EditorState copyWith({
    List<EditorDocument>? documents,
    String? activeDocumentId,
    bool clearActiveDocument = false,
  }) {
    return EditorState(
      documents: documents ?? this.documents,
      activeDocumentId: clearActiveDocument
          ? null
          : (activeDocumentId ?? this.activeDocumentId),
    );
  }
}

/// Resolves the file service for a terminal tab. Overridable in
/// tests; in the app it goes through the session manager.
final editorFileServiceResolverProvider =
    Provider<Future<RemoteFileService?> Function(String tabId)>(
      (ref) =>
          (tabId) =>
              ref.read(sessionManagerProvider.notifier).fileServiceFor(tabId),
    );

final externalEditorRuntimeProvider = Provider<ExternalEditorRuntime>(
  (ref) => const ProcessExternalEditorRuntime(),
);

/// Creates the debounced watcher for one external document;
/// overridable in tests with near-zero durations.
final localFileWatchFactoryProvider =
    Provider<LocalFileWatch Function(File file, void Function() onStable)>(
      (ref) =>
          (file, onStable) => LocalFileWatch(file, onStableChange: onStable),
    );

final editorProvider = NotifierProvider<EditorNotifier, EditorState>(
  EditorNotifier.new,
);

final class EditorNotifier extends Notifier<EditorState> {
  final _uuid = const Uuid();
  final _watches = <String, LocalFileWatch>{};

  /// Dispose callbacks for each document's controllers, keyed by
  /// document ID and tracked in a field because `state` is no
  /// longer readable by the time ref.onDispose runs. Closing a
  /// document disposes through here exactly once.
  final _docDisposers = <String, List<void Function()>>{};

  @override
  EditorState build() {
    ref.onDispose(() {
      for (final disposers in _docDisposers.values) {
        for (final dispose in disposers) {
          dispose();
        }
      }
      for (final watch in _watches.values) {
        watch.dispose();
      }
    });
    return const EditorState();
  }

  void _disposeDocControllers(String docId) {
    final disposers = _docDisposers.remove(docId);
    if (disposers == null) return;
    for (final dispose in disposers) {
      dispose();
    }
  }

  FileEditorSettings get _settings =>
      ref.read(uiPreferencesProvider).fileEditor;

  // ---------------------------------------------------------------
  // Opening documents
  // ---------------------------------------------------------------

  /// Opens [entry] in the built-in editor (or activates the
  /// existing document for the same tab + path). Returns an
  /// [AppError] to show the user, or null on success.
  Future<AppError?> openFile({
    required String tabId,
    required SshSession profile,
    required RemoteEntry entry,
  }) async {
    final existing = _findDoc(EditorDocKind.builtin, tabId, entry.path);
    if (existing != null) {
      activate(existing.id);
      return null;
    }
    if (entry.size != null && entry.size! > maxEditableBytes) {
      return AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage:
            '"${entry.name}" is ${(entry.size! / (1024 * 1024)).toStringAsFixed(1)} MB — '
            'the built-in editor opens files up to '
            '${(maxEditableBytes / (1024 * 1024)).toStringAsFixed(0)} MB. '
            'Download it instead.',
      );
    }
    final service = await ref.read(editorFileServiceResolverProvider)(tabId);
    if (service == null) {
      return const AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'The connection for this file is no longer open.',
      );
    }
    final docId = _uuid.v4();
    final controller = HighlightingController(
      language: languageForPath(entry.path),
    );
    final undo = UndoHistoryController();
    _docDisposers[docId] = [controller.dispose, undo.dispose];
    var doc = EditorDocument(
      id: docId,
      kind: EditorDocKind.builtin,
      tabId: tabId,
      sessionId: profile.id,
      profileName: profile.name,
      remotePath: entry.path,
      fileName: entry.name,
      language: languageForPath(entry.path),
      textController: controller,
      undoController: undo,
      isLoading: true,
    );
    _addDoc(doc);
    controller.addListener(() => _onTextChanged(docId));
    try {
      final bytes = await service.readBytes(
        entry.path,
        maxBytes: maxEditableBytes,
      );
      if (looksBinary(bytes)) {
        _removeDoc(docId);
        return AppError(
          category: AppErrorCategory.unsupportedCapability,
          userMessage:
              '"${entry.name}" looks like a binary file and cannot '
              'be edited as text.',
        );
      }
      final decoded = decodeTextFile(bytes);
      final stat = await service.stat(entry.path);
      _replaceDoc(
        doc.copyWith(
          savedText: decoded.text,
          savedBytes: bytes,
          hasBom: decoded.hasBom,
          remoteStat: stat,
          isLoading: false,
        ),
      );
      controller.text = decoded.text;
      return null;
    } on AppError catch (e) {
      _removeDoc(docId);
      return e;
    } on FormatException {
      _removeDoc(docId);
      return AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage:
            '"${entry.name}" is not valid UTF-8. HeroTerm only '
            'edits UTF-8 text files, so the file was not opened '
            '(nothing was changed).',
      );
    } catch (e) {
      _removeDoc(docId);
      return AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'Could not open "${entry.name}".',
        diagnostic: e.runtimeType.toString(),
      );
    }
  }

  // ---------------------------------------------------------------
  // Saving (built-in + shared upload pipeline)
  // ---------------------------------------------------------------

  /// Saves a built-in document. Without [force], a remote change
  /// since load/save yields [SaveOutcome.conflict] and NOTHING is
  /// written (§4). A failed save keeps the content and the dirty
  /// flag (§2.4).
  Future<(SaveOutcome, AppError?)> save(
    String docId, {
    bool force = false,
  }) async {
    final doc = state.docById(docId);
    if (doc == null || doc.kind != EditorDocKind.builtin) {
      return (SaveOutcome.failed, null);
    }
    final text = doc.textController!.text;
    final bytes = encodeTextFile(text, hasBom: doc.hasBom);
    final outcome = await _upload(doc, bytes, force: force);
    if (outcome.$1 == SaveOutcome.saved) {
      _replaceDoc(
        state
            .docById(docId)!
            .copyWith(savedText: text, savedBytes: bytes, isDirty: false),
      );
      _afterSuccessfulSave(state.docById(docId)!);
    }
    return outcome;
  }

  /// The shared upload path: conflict check → write → re-stat →
  /// refresh the explorer when it shows the file's directory.
  Future<(SaveOutcome, AppError?)> _upload(
    EditorDocument doc,
    List<int> bytes, {
    required bool force,
  }) async {
    _replaceDoc(doc.copyWith(isSaving: true, clearError: true));
    try {
      final service = await ref.read(editorFileServiceResolverProvider)(
        doc.tabId,
      );
      if (service == null) {
        throw const AppError(
          category: AppErrorCategory.unknown,
          userMessage:
              'The connection is closed. Your changes are kept in '
              'the editor — reconnect and save again.',
        );
      }
      if (!force && doc.remoteStat != null) {
        final current = await service.stat(doc.remotePath);
        if (!current.sameAs(doc.remoteStat!)) {
          _replaceDoc(state.docById(doc.id)!.copyWith(isSaving: false));
          return (SaveOutcome.conflict, null);
        }
      }
      await service.writeBytes(doc.remotePath, bytes);
      final stat = await service.stat(doc.remotePath);
      _replaceDoc(
        state
            .docById(doc.id)!
            .copyWith(
              remoteStat: stat,
              savedBytes: bytes,
              isSaving: false,
              clearError: true,
            ),
      );
      final explorer = ref.read(explorerProvider);
      if (explorer.currentPath == RemotePath.parentOf(doc.remotePath)) {
        unawaited(ref.read(explorerProvider.notifier).refresh());
      }
      return (SaveOutcome.saved, null);
    } on AppError catch (e) {
      _replaceDoc(
        state
            .docById(doc.id)!
            .copyWith(isSaving: false, errorMessage: e.userMessage),
      );
      return (SaveOutcome.failed, e);
    } catch (e) {
      final error = AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'Save failed. Your changes are kept in the editor.',
        diagnostic: e.runtimeType.toString(),
      );
      _replaceDoc(
        state
            .docById(doc.id)!
            .copyWith(isSaving: false, errorMessage: error.userMessage),
      );
      return (SaveOutcome.failed, error);
    }
  }

  /// Reloads a built-in document from the server, discarding the
  /// local text. Callers confirm with the user first when dirty.
  Future<AppError?> reload(String docId) async {
    final doc = state.docById(docId);
    if (doc == null || doc.kind != EditorDocKind.builtin) return null;
    try {
      final service = await ref.read(editorFileServiceResolverProvider)(
        doc.tabId,
      );
      if (service == null) {
        throw const AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'The connection for this file is no longer open.',
        );
      }
      final bytes = await service.readBytes(
        doc.remotePath,
        maxBytes: maxEditableBytes,
      );
      if (looksBinary(bytes)) {
        throw const AppError(
          category: AppErrorCategory.unsupportedCapability,
          userMessage: 'The remote file is no longer a text file.',
        );
      }
      final decoded = decodeTextFile(bytes);
      final stat = await service.stat(doc.remotePath);
      doc.textController!.text = decoded.text;
      _replaceDoc(
        doc.copyWith(
          savedText: decoded.text,
          savedBytes: bytes,
          remoteStat: stat,
          isDirty: false,
          clearError: true,
        ),
      );
      return null;
    } on AppError catch (e) {
      return e;
    } on FormatException {
      return const AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage: 'The remote file is no longer valid UTF-8.',
      );
    }
  }

  // ---------------------------------------------------------------
  // Smart Save bookkeeping (§2.5)
  // ---------------------------------------------------------------

  /// Counts a successful save; when the file reaches 3 and the
  /// prompt was never answered, flags it so the UI can offer
  /// "Don't ask again for this file" exactly once. Only the
  /// before-save confirmation is skippable — never the
  /// unsaved-changes warning on close.
  void _afterSuccessfulSave(EditorDocument doc) {
    if (!_settings.smartSaveEnabled) return;
    if (!_settings.effectiveConfirmBeforeSave) return;
    // Only built-in saves go through the confirmation dialog —
    // external auto-syncs are never "confirmed saves".
    if (doc.kind != EditorDocKind.builtin) return;
    final key = FileEditorSettings.recordKey(doc.sessionId, doc.remotePath);
    final record = _settings.recordFor(doc.sessionId, doc.remotePath);
    final updated = record.copyWith(
      successfulSaves: record.successfulSaves + 1,
    );
    ref.read(uiPreferencesProvider.notifier).setSmartSaveRecord(key, updated);
    if (updated.successfulSaves >= 3 && !updated.promptAnswered) {
      _smartSavePromptDocId = doc.id;
      _notifySmartSavePrompt?.call(doc.id);
    }
  }

  String? _smartSavePromptDocId;
  void Function(String docId)? _notifySmartSavePrompt;

  /// The UI registers here to be told when the Smart Save prompt
  /// should appear for a document.
  set smartSavePromptListener(void Function(String docId)? listener) {
    _notifySmartSavePrompt = listener;
  }

  String? get pendingSmartSavePromptDocId => _smartSavePromptDocId;

  void answerSmartSavePrompt(String docId, {required bool dontAskAgain}) {
    final doc = state.docById(docId);
    if (doc == null) return;
    _smartSavePromptDocId = null;
    final key = FileEditorSettings.recordKey(doc.sessionId, doc.remotePath);
    final record = _settings.recordFor(doc.sessionId, doc.remotePath);
    ref
        .read(uiPreferencesProvider.notifier)
        .setSmartSaveRecord(
          key,
          record.copyWith(dontAskAgain: dontAskAgain, promptAnswered: true),
        );
  }

  /// Whether saving [doc] should ask for confirmation first:
  /// the setting is on, Smart Save did not exempt this file.
  bool saveNeedsConfirmation(EditorDocument doc) {
    if (!_settings.effectiveConfirmBeforeSave) return false;
    final record = _settings.recordFor(doc.sessionId, doc.remotePath);
    return !record.dontAskAgain;
  }

  // ---------------------------------------------------------------
  // Activation / closing
  // ---------------------------------------------------------------

  void activate(String docId) {
    state = state.copyWith(activeDocumentId: docId);
  }

  /// Shows the terminal surface again (documents stay open).
  void showTerminal() {
    state = state.copyWith(clearActiveDocument: true);
  }

  /// Removes a document. For external documents the temp file is
  /// deleted only when [deleteTempFile] — callers pass true only
  /// when everything is synced or the user confirmed discarding.
  Future<void> closeDocument(
    String docId, {
    bool deleteTempFile = false,
  }) async {
    final doc = state.docById(docId);
    if (doc == null) return;
    _watches.remove(docId)?.dispose();
    _disposeDocControllers(docId);
    final docs = state.documents.where((d) => d.id != docId).toList();
    var active = state.activeDocumentId;
    if (active == docId) {
      active = docs.isEmpty ? null : docs.last.id;
    }
    state = EditorState(documents: docs, activeDocumentId: active);
    if (deleteTempFile && doc.localPath != null) {
      try {
        final file = File(doc.localPath!);
        if (await file.exists()) await file.delete();
        final dir = file.parent;
        if (await dir.exists() && (await dir.list().isEmpty)) {
          await dir.delete();
        }
      } catch (_) {
        // Cleanup is best-effort; a leftover temp file is noted
        // in the docs, never a crash.
      }
    }
  }

  // ---------------------------------------------------------------
  // External editor (§2.3)
  // ---------------------------------------------------------------

  /// Downloads [entry] into a private temp workspace, opens it in
  /// [app] (a bundle path or `open -a` name), and watches the temp
  /// file: stable changes sync back per the Auto Sync setting.
  /// Returns an [AppError] to show, or null on success.
  Future<AppError?> openWithExternal({
    required String tabId,
    required SshSession profile,
    required RemoteEntry entry,
    required String app,
  }) async {
    final existing = _findDoc(EditorDocKind.external, tabId, entry.path);
    if (existing != null) {
      activate(existing.id);
      // Re-launch the app so the user lands back in the editor.
      final runtime = ref.read(externalEditorRuntimeProvider);
      await runtime.launch(app, existing.localPath!);
      return null;
    }
    final service = await ref.read(editorFileServiceResolverProvider)(tabId);
    if (service == null) {
      return const AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'The connection for this file is no longer open.',
      );
    }
    final docId = _uuid.v4();
    try {
      // Temp workspace: <tempRoot>/HeroTerm/<docId>/<fileName>,
      // directory restricted to the user (it can hold .env files).
      final configured = _settings.tempDirectory;
      final base = configured.isNotEmpty
          ? Directory(configured)
          : Directory.systemTemp;
      final workDir = Directory('${base.path}/HeroTerm/$docId');
      await workDir.create(recursive: true);
      try {
        await Process.run('chmod', ['700', workDir.path]);
      } catch (_) {
        // Best effort (POSIX hosts); never block the open on it.
      }
      final localFile = File('${workDir.path}/${entry.name}');
      final handle = await service.openDownload(entry.path);
      try {
        final sink = localFile.openWrite();
        await sink.addStream(handle.stream);
        await sink.close();
      } finally {
        await handle.close();
      }
      final stat = await service.stat(entry.path);
      final bytes = await localFile.readAsBytes();
      final doc = EditorDocument(
        id: docId,
        kind: EditorDocKind.external,
        tabId: tabId,
        sessionId: profile.id,
        profileName: profile.name,
        remotePath: entry.path,
        fileName: entry.name,
        language: languageForPath(entry.path),
        savedBytes: bytes,
        remoteStat: stat,
        localPath: localFile.path,
        lastSyncedAt: DateTime.now(),
      );
      _addDoc(doc);
      final watch = ref.read(localFileWatchFactoryProvider)(
        localFile,
        () => unawaited(_onExternalStable(docId)),
      );
      _watches[docId] = watch;
      watch.start(
        ref.read(externalEditorRuntimeProvider).watchDirectory(workDir.path),
      );
      final runtime = ref.read(externalEditorRuntimeProvider);
      await runtime.launch(app, localFile.path);
      return null;
    } on AppError catch (e) {
      return e;
    } catch (e) {
      return AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'Could not open "${entry.name}" externally.',
        diagnostic: e.runtimeType.toString(),
      );
    }
  }

  /// A stable local change was detected: compare bytes, then sync
  /// now (Auto Sync on) or just flag the document (off).
  Future<void> _onExternalStable(String docId) async {
    final doc = state.docById(docId);
    if (doc == null || doc.localPath == null) return;
    try {
      final bytes = await File(doc.localPath!).readAsBytes();
      if (_bytesEqual(bytes, doc.savedBytes)) {
        if (doc.hasUnsyncedChanges) {
          _replaceDoc(
            doc.copyWith(
              syncState: ExternalSyncState.watching,
              hasUnsyncedChanges: false,
              isDirty: false,
            ),
          );
        }
        return;
      }
      _replaceDoc(doc.copyWith(hasUnsyncedChanges: true, isDirty: true));
      if (_settings.autoSync) {
        await syncExternal(docId);
      } else {
        _replaceDoc(
          state.docById(docId)!.copyWith(syncState: ExternalSyncState.changed),
        );
      }
    } catch (_) {
      // A read racing the editor's own save: the next stable
      // event will re-check.
    }
  }

  /// Uploads the temp file's current content through the shared
  /// conflict-checked pipeline. Failures keep the local file and
  /// flag the document (§2.3/§4).
  Future<(SaveOutcome, AppError?)> syncExternal(
    String docId, {
    bool force = false,
  }) async {
    final doc = state.docById(docId);
    if (doc == null || doc.kind != EditorDocKind.external) {
      return (SaveOutcome.failed, null);
    }
    List<int> bytes;
    try {
      bytes = await File(doc.localPath!).readAsBytes();
    } catch (e) {
      return (
        SaveOutcome.failed,
        AppError(
          category: AppErrorCategory.unknown,
          userMessage: 'The temporary file could not be read.',
          diagnostic: e.runtimeType.toString(),
        ),
      );
    }
    _replaceDoc(doc.copyWith(syncState: ExternalSyncState.syncing));
    final outcome = await _upload(doc, bytes, force: force);
    final current = state.docById(docId);
    if (current == null) return outcome;
    if (outcome.$1 == SaveOutcome.saved) {
      _replaceDoc(
        current.copyWith(
          syncState: ExternalSyncState.watching,
          hasUnsyncedChanges: false,
          isDirty: false,
          lastSyncedAt: DateTime.now(),
        ),
      );
      _afterSuccessfulSave(current);
    } else if (outcome.$1 == SaveOutcome.failed) {
      _replaceDoc(current.copyWith(syncState: ExternalSyncState.error));
    } else {
      _replaceDoc(current.copyWith(syncState: ExternalSyncState.changed));
    }
    return outcome;
  }

  /// Re-opens the external app on the document's temp file.
  Future<AppError?> relaunchExternal(String docId) async {
    final doc = state.docById(docId);
    if (doc == null || doc.localPath == null) return null;
    final app = _settings.externalApp;
    if (app.isEmpty) {
      return const AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'No external application is configured.',
      );
    }
    try {
      await ref.read(externalEditorRuntimeProvider).launch(app, doc.localPath!);
      return null;
    } on AppError catch (e) {
      return e;
    }
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  EditorDocument? _findDoc(EditorDocKind kind, String tabId, String path) {
    for (final doc in state.documents) {
      if (doc.kind == kind && doc.tabId == tabId && doc.remotePath == path) {
        return doc;
      }
    }
    return null;
  }

  void _addDoc(EditorDocument doc) {
    state = EditorState(
      documents: [...state.documents, doc],
      activeDocumentId: doc.id,
    );
  }

  void _removeDoc(String docId) {
    _disposeDocControllers(docId);
    final docs = state.documents.where((d) => d.id != docId).toList();
    state = EditorState(
      documents: docs,
      activeDocumentId: state.activeDocumentId == docId
          ? (docs.isEmpty ? null : docs.last.id)
          : state.activeDocumentId,
    );
  }

  void _replaceDoc(EditorDocument doc) {
    state = EditorState(
      documents: [for (final d in state.documents) d.id == doc.id ? doc : d],
      activeDocumentId: state.activeDocumentId,
    );
  }

  void _onTextChanged(String docId) {
    final doc = state.docById(docId);
    if (doc == null || doc.textController == null) return;
    final dirty = doc.textController!.text != doc.savedText;
    if (dirty != doc.isDirty) {
      _replaceDoc(doc.copyWith(isDirty: dirty));
    }
  }
}
