import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/app/ui_preferences.dart';
import 'package:heroterm/features/file_editor/data/external_editor.dart';
import 'package:heroterm/features/file_editor/presentation/editor_controller.dart';
import 'package:heroterm/features/remote_explorer/data/remote_file_service.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_entry.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';

import 'explorer_controller_test.dart' show FakeFileService;

final _profile = SshSession(
  id: 'profile-1',
  name: 'Staging',
  host: 'staging.example.com',
  username: 'root',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

RemoteEntry _entry(String path, {int? size}) => RemoteEntry(
  name: path.split('/').last,
  path: path,
  kind: RemoteEntryKind.file,
  size: size,
);

final class _FakeRuntime implements ExternalEditorRuntime {
  final launches = <(String, String)>[];
  final watchers = <String, StreamController<FileSystemEvent>>{};

  @override
  Future<void> launch(String app, String filePath) async {
    launches.add((app, filePath));
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String directoryPath) {
    return watchers
        .putIfAbsent(directoryPath, () => StreamController.broadcast())
        .stream;
  }
}

void main() {
  late Directory tmp;
  late FakeFileService service;
  late _FakeRuntime runtime;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('heroterm-editor-test-');
    runtime = _FakeRuntime();
    service = FakeFileService(
      const {},
      files: {
        '/etc/app.conf': utf8.encode('key=value\n'),
        '/srv/note.txt': utf8.encode('hello\n'),
      },
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> makeContainer({
    FileEditorSettings settings = const FileEditorSettings(),
    RemoteFileService? overrideService,
  }) async {
    final container = ProviderContainer(
      overrides: [
        editorFileServiceResolverProvider.overrideWithValue(
          (_) async => overrideService ?? service,
        ),
        uiPreferencesStoreProvider.overrideWithValue(
          UiPreferencesStore(directoryProvider: () async => tmp),
        ),
        externalEditorRuntimeProvider.overrideWithValue(runtime),
        localFileWatchFactoryProvider.overrideWithValue(
          (file, onStable) => LocalFileWatch(
            file,
            onStableChange: onStable,
            debounce: const Duration(milliseconds: 10),
            stabilityWindow: const Duration(milliseconds: 10),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(uiPreferencesProvider);
    // Let the (empty) store load settle, then apply test settings.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    container
        .read(uiPreferencesProvider.notifier)
        .setFileEditorSettings(settings);
    return container;
  }

  group('built-in editor', () {
    test('openFile loads content, detects language, starts clean', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      final error = await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      expect(error, isNull);
      final state = container.read(editorProvider);
      expect(state.documents, hasLength(1));
      final doc = state.documents.single;
      expect(doc.textController!.text, 'key=value\n');
      expect(doc.isDirty, isFalse);
      expect(doc.isLoading, isFalse);
      expect(state.activeDocumentId, doc.id);
    });

    test('openFile refuses oversize files before downloading', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      final error = await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/srv/big.log', size: 5 * 1024 * 1024),
      );
      expect(error, isNotNull);
      expect(error!.userMessage, contains('up to'));
      expect(container.read(editorProvider).documents, isEmpty);
      expect(service.calls.where((c) => c.startsWith('readBytes')), isEmpty);
    });

    test('openFile refuses binary and non-UTF-8 content', () async {
      service.files['/bin/tool'] = [0x7f, 0x45, 0x00, 0x01];
      service.files['/etc/latin.txt'] = [0x63, 0x61, 0x66, 0xe9];
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      final binaryError = await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/bin/tool', size: 4),
      );
      expect(binaryError!.userMessage, contains('binary'));
      final encodingError = await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/latin.txt', size: 4),
      );
      expect(encodingError!.userMessage, contains('UTF-8'));
      expect(container.read(editorProvider).documents, isEmpty);
    });

    test('opening the same file twice activates the same document', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      expect(container.read(editorProvider).documents, hasLength(1));
    });

    test('editing marks dirty; save uploads and marks clean', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      doc.textController!.text = 'key=changed\n';
      expect(container.read(editorProvider).documents.single.isDirty, isTrue);
      final (outcome, error) = await notifier.save(doc.id);
      expect(outcome, SaveOutcome.saved);
      expect(error, isNull);
      expect(utf8.decode(service.uploaded['/etc/app.conf']!), 'key=changed\n');
      expect(container.read(editorProvider).documents.single.isDirty, isFalse);
    });

    test('a remote change since load blocks save as a conflict', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      // Someone else edits the file on the server.
      service.files['/etc/app.conf'] = utf8.encode('key=other\n');
      service.mtimeTick++;
      doc.textController!.text = 'key=mine\n';
      final (outcome, _) = await notifier.save(doc.id);
      expect(outcome, SaveOutcome.conflict);
      expect(service.writeCounts['/etc/app.conf'] ?? 0, 0);
      // Forcing the save overwrites deliberately.
      final (forced, _) = await notifier.save(doc.id, force: true);
      expect(forced, SaveOutcome.saved);
      expect(utf8.decode(service.uploaded['/etc/app.conf']!), 'key=mine\n');
    });

    test('a failed save keeps the content and the dirty flag', () async {
      service.failWrites = true;
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      doc.textController!.text = 'key=changed\n';
      final (outcome, error) = await notifier.save(doc.id);
      expect(outcome, SaveOutcome.failed);
      expect(error, isNotNull);
      final after = container.read(editorProvider).documents.single;
      expect(after.isDirty, isTrue);
      expect(after.textController!.text, 'key=changed\n');
      expect(after.errorMessage, contains('Permission denied'));
    });

    test('reload discards local text for the remote content', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      doc.textController!.text = 'local draft\n';
      service.files['/etc/app.conf'] = utf8.encode('key=remote\n');
      final error = await notifier.reload(doc.id);
      expect(error, isNull);
      final after = container.read(editorProvider).documents.single;
      expect(after.textController!.text, 'key=remote\n');
      expect(after.isDirty, isFalse);
    });
  });

  group('smart save', () {
    test('after 3 confirmed saves the prompt fires once; '
        'dont-ask-again exempts the file', () async {
      final container = await makeContainer(
        settings: const FileEditorSettings(
          confirmBeforeSave: true,
          smartSaveEnabled: true,
          tempDirectory: '',
        ),
      );
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      expect(notifier.saveNeedsConfirmation(doc), isTrue);

      String? promptedDocId;
      notifier.smartSavePromptListener = (id) => promptedDocId = id;
      for (var i = 0; i < 3; i++) {
        doc.textController!.text = 'key=v$i\n';
        final (outcome, _) = await notifier.save(doc.id);
        expect(outcome, SaveOutcome.saved);
      }
      expect(promptedDocId, doc.id);

      notifier.answerSmartSavePrompt(doc.id, dontAskAgain: true);
      final record = container
          .read(uiPreferencesProvider)
          .fileEditor
          .recordFor('profile-1', '/etc/app.conf');
      expect(record.dontAskAgain, isTrue);
      expect(record.promptAnswered, isTrue);
      expect(
        notifier.saveNeedsConfirmation(
          container.read(editorProvider).documents.single,
        ),
        isFalse,
      );
    });

    test('no counting while the save confirmation is disabled', () async {
      final container = await makeContainer(
        settings: const FileEditorSettings(
          confirmBeforeSave: false,
          saveConfirmConfigured: true,
        ),
      );
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      doc.textController!.text = 'key=x\n';
      await notifier.save(doc.id);
      final record = container
          .read(uiPreferencesProvider)
          .fileEditor
          .recordFor('profile-1', '/etc/app.conf');
      expect(record.successfulSaves, 0);
    });
  });

  group('save confirmation default', () {
    test('a fresh install asks before saving and counts saves', () async {
      final container = await makeContainer();
      final notifier = container.read(editorProvider.notifier);
      await notifier.openFile(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/etc/app.conf', size: 10),
      );
      final doc = container.read(editorProvider).documents.single;
      expect(notifier.saveNeedsConfirmation(doc), isTrue);
      doc.textController!.text = 'key=default\n';
      await notifier.save(doc.id);
      final record = container
          .read(uiPreferencesProvider)
          .fileEditor
          .recordFor('profile-1', '/etc/app.conf');
      expect(record.successfulSaves, 1);
    });
  });

  group('external editor', () {
    Future<ProviderContainer> openExternal({
      FileEditorSettings settings = const FileEditorSettings(),
    }) async {
      final container = await makeContainer(
        settings: settings.copyWith(tempDirectory: tmp.path),
      );
      final notifier = container.read(editorProvider.notifier);
      final error = await notifier.openWithExternal(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/srv/note.txt', size: 6),
        app: 'FakeApp',
      );
      expect(error, isNull);
      return container;
    }

    test('downloads to a temp workspace and launches the app', () async {
      final container = await openExternal();
      final doc = container.read(editorProvider).documents.single;
      expect(doc.kind, EditorDocKind.external);
      expect(doc.localPath, isNotNull);
      final local = File(doc.localPath!);
      expect(await local.exists(), isTrue);
      expect(await local.readAsString(), 'hello\n');
      expect(runtime.launches, [('FakeApp', doc.localPath)]);
      expect(doc.hasUnsyncedChanges, isFalse);
    });

    test('a stable local change auto-syncs to the server', () async {
      final container = await openExternal();
      final notifier = container.read(editorProvider.notifier);
      final doc = container.read(editorProvider).documents.single;
      final local = File(doc.localPath!);
      await local.writeAsString('hello world\n');
      final dirPath = local.parent.path;
      runtime.watchers[dirPath]!.add(
        FileSystemModifyEvent(local.path, false, true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(utf8.decode(service.uploaded['/srv/note.txt']!), 'hello world\n');
      final after = container.read(editorProvider).documents.single;
      expect(after.hasUnsyncedChanges, isFalse);
      expect(after.syncState, ExternalSyncState.watching);
      expect(notifier, isNotNull);
    });

    test(
      'with Auto Sync off the change is flagged until manual sync',
      () async {
        final container = await openExternal(
          settings: const FileEditorSettings(autoSync: false),
        );
        final notifier = container.read(editorProvider.notifier);
        final doc = container.read(editorProvider).documents.single;
        final local = File(doc.localPath!);
        await local.writeAsString('draft\n');
        runtime.watchers[local.parent.path]!.add(
          FileSystemModifyEvent(local.path, false, true),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        var after = container.read(editorProvider).documents.single;
        expect(after.hasUnsyncedChanges, isTrue);
        expect(after.syncState, ExternalSyncState.changed);
        expect(service.uploaded['/srv/note.txt'], isNull);

        final (outcome, _) = await notifier.syncExternal(doc.id);
        expect(outcome, SaveOutcome.saved);
        expect(utf8.decode(service.uploaded['/srv/note.txt']!), 'draft\n');
        after = container.read(editorProvider).documents.single;
        expect(after.hasUnsyncedChanges, isFalse);
      },
    );

    test('closing without deleteTempFile keeps the temp file', () async {
      final container = await openExternal();
      final notifier = container.read(editorProvider.notifier);
      final doc = container.read(editorProvider).documents.single;
      final local = File(doc.localPath!);
      await notifier.closeDocument(doc.id);
      expect(await local.exists(), isTrue);
      await notifier.closeDocument(doc.id, deleteTempFile: true);
      // Already closed above; reopen and close with deletion.
      await notifier.openWithExternal(
        tabId: 'tab-1',
        profile: _profile,
        entry: _entry('/srv/note.txt', size: 6),
        app: 'FakeApp',
      );
      final doc2 = container.read(editorProvider).documents.single;
      final local2 = File(doc2.localPath!);
      await notifier.closeDocument(doc2.id, deleteTempFile: true);
      expect(await local2.exists(), isFalse);
    });
  });
}
