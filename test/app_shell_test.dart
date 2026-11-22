import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/app/app.dart';
import 'package:heroterm/core/security/credential_store.dart';
import 'package:heroterm/features/connection/data/ssh_connection_service.dart';
import 'package:heroterm/features/connection/presentation/connection_providers.dart';
import 'package:heroterm/features/connection/presentation/terminal_sessions.dart';
import 'package:heroterm/features/remote_explorer/data/remote_file_service.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_entry.dart';
import 'package:heroterm/features/sessions/data/session_repository.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';
import 'package:heroterm/features/sessions/presentation/session_providers.dart';
import 'package:heroterm/features/sessions/presentation/sessions_controller.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        sessionRepositoryProvider.overrideWithValue(
          InMemorySessionRepository(),
        ),
      ],
      child: const HeroTermApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final class _FakeShell implements RemoteShell {
  final _done = Completer<void>();
  bool closed = false;

  @override
  Stream<Uint8List> get stdout => const Stream.empty();
  @override
  Stream<Uint8List> get stderr => const Stream.empty();
  @override
  void writeInput(Uint8List bytes) {}
  @override
  void resize(int width, int height) {}
  @override
  Future<void> get done => _done.future;
  @override
  int? get exitCode => closed ? 0 : null;
  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }
}

final class _FakeFileService implements RemoteFileService {
  @override
  Future<List<RemoteEntry>> list(String path) async => [
    RemoteEntry(
      name: 'docs',
      path: '/home/deploy/docs',
      kind: RemoteEntryKind.directory,
      modifiedAt: DateTime.utc(2026, 10, 20, 12),
      permissions: 'rwxr-xr-x',
      uid: 1000,
      gid: 1000,
      modeValue: int.parse('40755', radix: 8),
    ),
    RemoteEntry(
      name: 'a.txt',
      path: '/home/deploy/a.txt',
      kind: RemoteEntryKind.file,
      size: 3000,
      modifiedAt: DateTime.utc(2026, 10, 20, 12),
      permissions: 'rw-r--r--',
      uid: 1000,
      gid: 1000,
      modeValue: int.parse('100644', radix: 8),
    ),
    RemoteEntry(
      name: 'b.txt',
      path: '/home/deploy/b.txt',
      kind: RemoteEntryKind.file,
      size: 1000,
      modifiedAt: DateTime.utc(2026, 10, 20, 12),
      permissions: 'rw-r--r--',
      uid: 1000,
      gid: 1000,
      modeValue: int.parse('100644', radix: 8),
    ),
  ];
  @override
  Future<String> canonicalize(String path) async => path;
  @override
  Future<String> homeDirectory() async => '/home/deploy';
  @override
  Future<bool> exists(String path) async => false;
  @override
  Future<void> rename(String from, String to) async {}
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<void> deleteRecursively(String path) async {}
  @override
  Future<DownloadHandle> openDownload(String path) =>
      throw UnimplementedError();
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<UploadHandle> openUpload(String path) => throw UnimplementedError();
  @override
  Future<RemoteFileStat> stat(String path) => throw UnimplementedError();
  @override
  Future<Uint8List> readBytes(String path, {required int maxBytes}) =>
      throw UnimplementedError();
  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      throw UnimplementedError();
}

final class _FakeConnection implements RemoteConnection {
  _FakeConnection(this.shell);
  @override
  final _FakeShell shell;
  @override
  Future<RemoteFileService> fileService() async => _FakeFileService();
  @override
  Future<String> runCommand(String command) async => '';
  @override
  Future<void> close() => shell.close();
}

final class _FakeService implements SshConnectionService {
  int connectCount = 0;
  @override
  Future<RemoteConnection> connect(ConnectRequest request) async {
    connectCount++;
    return _FakeConnection(_FakeShell());
  }
}

Future<void> sendShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

void main() {
  testWidgets('disconnected shell shows sessions, empty state, and '
      'unavailable metrics (never fake values)', (tester) async {
    await pumpApp(tester);

    expect(find.text('HeroTerm'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('No sessions yet.'), findsOneWidget);
    expect(find.text('Not connected to a server'), findsOneWidget);
    expect(find.text('Server metrics unavailable'), findsOneWidget);
  });

  testWidgets('creating a session through the editor adds it to the '
      'sidebar and survives filtering', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('new-session-button')));
    await tester.pumpAndSettle();
    expect(find.text('New session'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('session-name')), 'Prod');
    await tester.enterText(
      find.byKey(const Key('session-host')),
      'prod.example.com',
    );
    await tester.enterText(find.byKey(const Key('session-username')), 'root');
    await tester.enterText(
      find.byKey(const Key('session-password')),
      'canary-password',
    );
    await tester.tap(find.byKey(const Key('session-save')));
    await tester.pumpAndSettle();

    expect(find.text('Prod'), findsWidgets);
    // The endpoint detail is no longer an always-visible subtitle;
    // it lives in the tile's hover tooltip (ADR-013).
    expect(
      find.text('root@prod.example.com:22 · Never connected'),
      findsNothing,
    );
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.text('Prod').first,
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, 'root@prod.example.com:22 · Never connected');

    // Search filters the list.
    await tester.enterText(find.byKey(const Key('session-search')), 'zzz');
    await tester.pump();
    expect(find.text('No sessions match your search.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('session-search')), '');
    await tester.pump();
    expect(find.text('Prod'), findsWidgets);
  });

  testWidgets('shortcuts connect/disconnect and the Reconnect button '
      'reconnects (Milestone 7)', (tester) async {
    final service = _FakeService();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          sessionRepositoryProvider.overrideWithValue(
            InMemorySessionRepository(),
          ),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const HeroTermApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HeroTermApp)),
    );
    final now = DateTime.utc(2026, 10, 25);
    await container
        .read(sessionsProvider.notifier)
        .addSession(
          SshSession(
            id: 's1',
            name: 'Prod',
            host: 'prod.example.com',
            username: 'root',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pump();

    // Select the session, then connect with ⌘⇧C.
    await tester.tap(find.text('Prod').first);
    await tester.pump();
    await sendShortcut(tester, LogicalKeyboardKey.keyC);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Connected:'), findsOneWidget);
    expect(service.connectCount, 1);
    expect(find.byKey(const Key('disconnect-button')), findsOneWidget);

    // Disconnect with ⌘⇧D: the Reconnect button appears.
    await sendShortcut(tester, LogicalKeyboardKey.keyD);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('reconnect-button')), findsOneWidget);

    // Reconnect button connects the same session again.
    await tester.tap(find.byKey(const Key('reconnect-button')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Connected:'), findsOneWidget);
    expect(service.connectCount, 2);

    // Leave the app disconnected so no polling timers remain.
    await tester.tap(find.byKey(const Key('disconnect-button')));
    await tester.pump();
    await tester.pump();
  });

  testWidgets('explorer table view shows metadata columns and sorts '
      'by header taps (table-view spec)', (tester) async {
    final service = _FakeService();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          sessionRepositoryProvider.overrideWithValue(
            InMemorySessionRepository(),
          ),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const HeroTermApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HeroTermApp)),
    );
    final now = DateTime.utc(2026, 10, 25);
    await container
        .read(sessionsProvider.notifier)
        .addSession(
          SshSession(
            id: 's1',
            name: 'Prod',
            host: 'prod.example.com',
            username: 'root',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pump();
    await tester.tap(find.text('Prod').first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Table headers and metadata cells are visible.
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('drwxr-xr-x'), findsOneWidget);
    expect(find.text('-rw-r--r--'), findsWidgets);
    expect(find.text('2.9 KB'), findsOneWidget);
    expect(find.text('1000 B'), findsOneWidget);
    expect(find.textContaining('2026-10-20'), findsWidgets);
    // The fake server resolves no account names: numeric fallback.
    expect(find.text('1000'), findsWidgets);

    // Default sort: name ascending (a.txt above b.txt).
    expect(
      tester.getTopLeft(find.text('a.txt')).dy,
      lessThan(tester.getTopLeft(find.text('b.txt')).dy),
    );

    // Tap the Size header: ascending size puts b.txt above a.txt;
    // the folder stays first regardless.
    await tester.tap(find.byKey(const Key('column-header-size')));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('b.txt')).dy,
      lessThan(tester.getTopLeft(find.text('a.txt')).dy),
    );
    expect(
      tester.getTopLeft(find.text('docs')).dy,
      lessThan(tester.getTopLeft(find.text('b.txt')).dy),
    );

    // Leave the app disconnected so no polling timers remain.
    await tester.tap(find.byKey(const Key('disconnect-button')));
    await tester.pump();
    await tester.pump();
  });

  testWidgets('tabs: connect, open a second session via the picker, '
      'switch and close tabs (multi-session spec)', (tester) async {
    final service = _FakeService();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          sessionRepositoryProvider.overrideWithValue(
            InMemorySessionRepository(),
          ),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const HeroTermApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HeroTermApp)),
    );
    final now = DateTime.utc(2026, 10, 25);
    final sessions = container.read(sessionsProvider.notifier);
    await sessions.addSession(
      SshSession(
        id: 's1',
        name: 'Prod',
        host: 'prod.example.com',
        username: 'root',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await sessions.addSession(
      SshSession(
        id: 's2',
        name: 'Dev',
        host: 'dev.example.com',
        username: 'deploy',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pump();

    // Connect Prod from the empty state: one tab appears.
    await tester.tap(find.text('Prod').first);
    await tester.pump();
    await tester.tap(find.byKey(const Key('connect-button')));
    await tester.pump();
    await tester.pump();
    var tabs = container.read(sessionManagerProvider);
    expect(tabs.tabs, hasLength(1));
    expect(tabs.activeTab?.profile.name, 'Prod');
    expect(find.byKey(const Key('new-tab-button')), findsOneWidget);

    // + opens the picker; choosing Dev opens a second tab while the
    // picker stays open.
    await tester.tap(find.byKey(const Key('new-tab-button')));
    await tester.pump();
    expect(find.byKey(const Key('picker-search')), findsOneWidget);
    expect(find.byKey(const Key('picker-session-s2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('picker-session-s2')));
    await tester.pump();
    await tester.pump();
    tabs = container.read(sessionManagerProvider);
    expect(tabs.tabs, hasLength(2));
    expect(tabs.activeTab?.profile.name, 'Dev');
    expect(service.connectCount, 2);
    expect(find.byKey(const Key('picker-search')), findsOneWidget);
    await tester.tap(find.byKey(const Key('picker-close')));
    await tester.pump();

    // Tapping the Prod chip switches the active tab without
    // reconnecting.
    await tester.tap(find.text('Prod').first);
    await tester.pump();
    tabs = container.read(sessionManagerProvider);
    expect(tabs.activeTab?.profile.name, 'Prod');
    expect(service.connectCount, 2);

    // Closing the active (Prod) tab activates its neighbour and
    // leaves Dev's connection untouched.
    final prodTab = tabs.tabs.firstWhere((t) => t.profile.name == 'Prod');
    await tester.tap(find.byKey(Key('tab-close-${prodTab.id}')));
    await tester.pump();
    await tester.pump();
    tabs = container.read(sessionManagerProvider);
    expect(tabs.tabs, hasLength(1));
    expect(tabs.activeTab?.profile.name, 'Dev');

    // Closing the last tab returns to the empty state (which also
    // stops metrics polling timers).
    final devTab = tabs.tabs.single;
    await tester.tap(find.byKey(Key('tab-close-${devTab.id}')));
    await tester.pump();
    await tester.pump();
    tabs = container.read(sessionManagerProvider);
    expect(tabs.tabs, isEmpty);
    expect(find.byKey(const Key('connect-button')), findsOneWidget);
  });

  testWidgets('profiles: labels on items, label filter, and '
      'the form test-connection + discard guard (profile spec)', (
    tester,
  ) async {
    final service = _FakeService();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          sessionRepositoryProvider.overrideWithValue(
            InMemorySessionRepository(),
          ),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
        child: const HeroTermApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HeroTermApp)),
    );
    final now = DateTime.utc(2026, 10, 25);
    final sessions = container.read(sessionsProvider.notifier);
    final production = await sessions.addLabel('Production');
    final development = await sessions.addLabel('Development');
    await sessions.addSession(
      SshSession(
        id: 'sp',
        name: 'ProdSrv',
        host: 'prod.example.com',
        username: 'root',
        labelIds: [production.id],
        icon: 'database',
        colorValue: 0xFFD32F2F,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await sessions.addSession(
      SshSession(
        id: 'sd',
        name: 'DevSrv',
        host: 'dev.example.com',
        username: 'deploy',
        labelIds: [development.id],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pump();

    // Labels render on the items; the endpoint subtitle is gone
    // (it lives in the hover tooltip now).
    expect(find.text('Production'), findsWidgets);
    expect(find.text('ProdSrv'), findsOneWidget);
    expect(find.text('DevSrv'), findsOneWidget);
    expect(find.textContaining('root@prod.example.com'), findsNothing);

    // Label filter: Development hides the production server.
    await tester.tap(find.byKey(Key('label-filter-${development.id}')));
    await tester.pump();
    expect(find.text('ProdSrv'), findsNothing);
    expect(find.text('DevSrv'), findsOneWidget);
    await tester.tap(find.byKey(Key('label-filter-${development.id}')));
    await tester.pump();
    expect(find.text('ProdSrv'), findsOneWidget);

    // The form: label assignment exists (no environment field any
    // more); Test Connection runs the fake service and reports
    // success without closing the form.
    await tester.tap(find.byKey(const Key('new-session-button')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('session-new-label')), findsOneWidget);
    expect(find.byKey(Key('session-label-${production.id}')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('session-name')), 'TestSrv');
    await tester.enterText(
      find.byKey(const Key('session-host')),
      'test.example.com',
    );
    await tester.enterText(find.byKey(const Key('session-username')), 'deploy');
    await tester.tap(find.byKey(const Key('session-test')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('session-test-result')), findsOneWidget);
    expect(find.textContaining('succeeded'), findsOneWidget);
    expect(find.byKey(const Key('session-save')), findsOneWidget);

    // Cancelling a dirty form asks before discarding.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('session-save')), findsNothing);
  });
}
