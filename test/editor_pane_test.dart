import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/app/ui_preferences.dart';
import 'package:heroterm/features/file_editor/presentation/editor_controller.dart';
import 'package:heroterm/features/file_editor/presentation/editor_pane.dart';
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

void main() {
  late Directory tmp;
  late FakeFileService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('heroterm-pane-test-');
    service = FakeFileService(
      const {},
      files: {'/etc/app.conf': utf8.encode('key=value\nother=1\n')},
    );
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<ProviderContainer> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorFileServiceResolverProvider.overrideWithValue(
            (_) async => service,
          ),
          uiPreferencesStoreProvider.overrideWithValue(
            UiPreferencesStore(directoryProvider: () async => tmp),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: EditorSurface())),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorSurface)),
    );
    final error = await container
        .read(editorProvider.notifier)
        .openFile(
          tabId: 'tab-1',
          profile: _profile,
          entry: const RemoteEntry(
            name: 'app.conf',
            path: '/etc/app.conf',
            kind: RemoteEntryKind.file,
            size: 18,
          ),
        );
    expect(error, isNull);
    await tester.pump();
    return container;
  }

  testWidgets('pane shows content, gutter and clean status', (tester) async {
    await pumpEditor(tester);
    expect(find.text('app.conf'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'key=value\nother=1\n');
    // Gutter shows line numbers 1..3.
    expect(find.text('1\n2\n3'), findsOneWidget);
  });

  testWidgets('typing marks dirty; Save uploads and marks clean', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).first, 'key=changed\n');
    await tester.pump();
    expect(find.text('Unsaved changes'), findsWidgets);
    final docId = ProviderScope.containerOf(
      tester.element(find.byType(EditorSurface)),
    ).read(editorProvider).documents.single.id;
    await tester.tap(find.byKey(Key('editor-save-$docId')));
    await tester.pumpAndSettle();
    // The save confirmation is ON by default (spec baseline):
    // the upload happens only after confirming.
    expect(find.text('Save file?'), findsOneWidget);
    expect(service.uploaded['/etc/app.conf'], isNull);
    await tester.tap(find.byKey(const Key('confirm-save-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(utf8.decode(service.uploaded['/etc/app.conf']!), 'key=changed\n');
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('find & replace-all rewrites matches', (tester) async {
    final container = await pumpEditor(tester);
    final docId = container.read(editorProvider).documents.single.id;
    await tester.tap(find.byKey(Key('editor-find-$docId')));
    await tester.pump();
    await tester.enterText(find.byKey(Key('editor-find-field-$docId')), 'key');
    await tester.pump();
    await tester.enterText(
      find.byKey(Key('editor-replace-field-$docId')),
      'id',
    );
    await tester.tap(find.text('Replace All'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(Key('editor-text-$docId')),
    );
    expect(field.controller!.text, 'id=value\nother=1\n');
  });

  testWidgets('closing a dirty file asks; Don\'t Save closes it', (
    tester,
  ) async {
    final container = await pumpEditor(tester);
    final docId = container.read(editorProvider).documents.single.id;
    await tester.enterText(find.byType(TextField).first, 'dirty\n');
    await tester.pump();
    await tester.tap(find.byKey(Key('editor-close-$docId')));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved Changes'), findsOneWidget);
    await tester.tap(find.text("Don't Save"));
    await tester.pumpAndSettle();
    expect(container.read(editorProvider).documents, isEmpty);
  });

  testWidgets('closing a dirty file with Save uploads then closes', (
    tester,
  ) async {
    final container = await pumpEditor(tester);
    final docId = container.read(editorProvider).documents.single.id;
    await tester.enterText(find.byType(TextField).first, 'kept\n');
    await tester.pump();
    await tester.tap(find.byKey(Key('editor-close-$docId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unsaved-save-button')));
    await tester.pumpAndSettle();
    expect(utf8.decode(service.uploaded['/etc/app.conf']!), 'kept\n');
    expect(container.read(editorProvider).documents, isEmpty);
  });
}
