import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/core/errors/app_error.dart';
import 'package:heroterm/core/security/credential_store.dart';
import 'package:heroterm/features/connection/data/ssh_connection_service.dart';
import 'package:heroterm/features/remote_explorer/data/remote_file_service.dart';
import 'package:heroterm/features/connection/domain/connection_state.dart';
import 'package:heroterm/features/connection/presentation/connection_providers.dart';
import 'package:heroterm/features/connection/presentation/terminal_sessions.dart';
import 'package:heroterm/features/sessions/data/session_repository.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';
import 'package:heroterm/features/sessions/presentation/session_providers.dart';
import 'package:heroterm/features/sessions/presentation/sessions_controller.dart';

final class FakeShell implements RemoteShell {
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _done = Completer<void>();
  final List<int> input = [];
  bool closed = false;

  @override
  Stream<Uint8List> get stdout => _stdout.stream;

  @override
  Stream<Uint8List> get stderr => _stderr.stream;

  @override
  void writeInput(Uint8List bytes) => input.addAll(bytes);

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

  void emitOutput(String text) =>
      _stdout.add(Uint8List.fromList(text.codeUnits));

  void endFromRemote() {
    if (!_done.isCompleted) _done.complete();
  }
}

final class FakeConnection implements RemoteConnection {
  FakeConnection(this.shell);

  @override
  final FakeShell shell;

  @override
  Future<RemoteFileService> fileService() =>
      throw UnimplementedError('not used in manager tests');

  @override
  Future<String> runCommand(String command) async => '';

  @override
  Future<void> close() => shell.close();
}

final class FakeService implements SshConnectionService {
  final shellsByHost = <String, FakeShell>{};
  FakeShell? lastShell;
  String? receivedPassword;
  int connectCount = 0;

  @override
  Future<RemoteConnection> connect(ConnectRequest request) async {
    connectCount++;
    final profile = request.profile;
    if (profile.host == 'authfail.example.com') {
      throw const AppError(
        category: AppErrorCategory.authentication,
        userMessage: 'Authentication failed.',
      );
    }
    if (profile.host.startsWith('newkey')) {
      final trusted = await request.onHostKeyPrompt(
        HostKeyChallenge(
          hostLabel: '${profile.host}:22',
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:fake',
        ),
      );
      if (!trusted) {
        throw const AppError(
          category: AppErrorCategory.hostKeyUnknown,
          userMessage: 'Host key was not trusted.',
        );
      }
    }
    if (profile.host == 'promptpw.example.com' &&
        request.storedSecret == null) {
      receivedPassword = await request.onPasswordPrompt(
        profile.username,
        '${profile.host}:${profile.port}',
      );
      if (receivedPassword == null) {
        throw const AppError(
          category: AppErrorCategory.authentication,
          userMessage: 'Password entry cancelled.',
        );
      }
    }
    final shell = FakeShell();
    shellsByHost[profile.host] = shell;
    lastShell = shell;
    return FakeConnection(shell);
  }
}

SshSession profile(String host) {
  final now = DateTime.utc(2026, 10, 24, 12);
  return SshSession(
    id: 'id-$host',
    name: host,
    host: host,
    username: 'deploy',
    createdAt: now,
    updatedAt: now,
  );
}

Future<ProviderContainer> makeContainer(FakeService service) async {
  final container = ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(InMemorySessionRepository()),
      credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      sshConnectionServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionsProvider);
  container.read(sessionManagerProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container;
}

Future<void> pumpEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

String bufferText(TerminalTab tab) {
  final lines = tab.terminal.buffer.lines;
  return [for (var i = 0; i < lines.length; i++) lines[i].toString()]
      .join('\n');
}

void main() {
  group('SessionManagerNotifier (multi-session tabs)', () {
    test(
      'successful connect wires output and records lastConnectedAt',
      () async {
        final service = FakeService();
        final container = await makeContainer(service);
        final sessions = container.read(sessionsProvider.notifier);
        final manager = container.read(sessionManagerProvider.notifier);
        final target = profile('ok.example.com');
        await sessions.addSession(target);

        final tab = await manager.openSession(target);
        expect(tab, isNotNull);
        expect(tab!.status, ConnectionStatus.connected);
        // The derived single-connection view follows the active tab.
        expect(
          container.read(connectionProvider).status,
          ConnectionStatus.connected,
        );

        service.lastShell!.emitOutput('hello from server');
        await pumpEvents();
        expect(bufferText(tab), contains('hello from server'));

        final saved = container
            .read(sessionsProvider)
            .sessions
            .singleWhere((s) => s.id == target.id);
        expect(saved.lastConnectedAt, isNotNull);

        await manager.disconnectTab(tab.id);
        expect(service.lastShell!.closed, isTrue);
        expect(
          container.read(sessionManagerProvider).tabById(tab.id)?.status,
          ConnectionStatus.disconnected,
        );
      },
    );

    test('two tabs run concurrently and route output independently', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);

      final tabA = await manager.openSession(profile('a.example.com'));
      final tabB = await manager.openSession(profile('b.example.com'));
      expect(service.connectCount, 2);
      final state = container.read(sessionManagerProvider);
      expect(state.tabs, hasLength(2));
      expect(state.activeTabId, tabB!.id);

      service.shellsByHost['a.example.com']!.emitOutput('output-for-A');
      service.shellsByHost['b.example.com']!.emitOutput('output-for-B');
      await pumpEvents();
      final after = container.read(sessionManagerProvider);
      expect(bufferText(after.tabById(tabA!.id)!), contains('output-for-A'));
      expect(bufferText(after.tabById(tabB.id)!), contains('output-for-B'));
      expect(
        bufferText(after.tabById(tabA.id)!),
        isNot(contains('output-for-B')),
      );

      // Closing one tab releases only its own connection.
      await manager.closeTab(tabA.id);
      expect(service.shellsByHost['a.example.com']!.closed, isTrue);
      expect(service.shellsByHost['b.example.com']!.closed, isFalse);
      final remaining = container.read(sessionManagerProvider);
      expect(remaining.tabs, hasLength(1));
      expect(remaining.tabs.single.status, ConnectionStatus.connected);
      expect(remaining.activeTabId, tabB.id);
    });

    test('opening an already-open profile activates its tab instead of '
        'duplicating; openAdditionalSession forces a duplicate with a '
        'suffix title', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);
      final target = profile('dup.example.com');

      final first = await manager.openSession(target);
      await manager.openSession(profile('other.example.com'));
      final again = await manager.openSession(target);
      expect(again!.id, first!.id);
      expect(service.connectCount, 2);
      expect(container.read(sessionManagerProvider).tabs, hasLength(2));
      expect(container.read(sessionManagerProvider).activeTabId, first.id);

      final extra = await manager.openAdditionalSession(target);
      expect(extra, isNotNull);
      expect(extra!.id, isNot(first.id));
      final tabs = container.read(sessionManagerProvider).tabs;
      expect(tabs, hasLength(3));
      expect(
        tabs.where((t) => t.profile.id == target.id).map((t) => t.title),
        containsAll(['dup.example.com', 'dup.example.com (2)']),
      );
    });

    test('closing the active tab activates a neighbour, then empties '
        'cleanly', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);
      final t1 = await manager.openAdditionalSession(profile('h1.example.com'));
      final t2 = await manager.openAdditionalSession(profile('h2.example.com'));
      final t3 = await manager.openAdditionalSession(profile('h3.example.com'));

      manager.activateTab(t2!.id);
      await manager.closeTab(t2.id);
      var state = container.read(sessionManagerProvider);
      expect(state.activeTabId, t3!.id); // right neighbour

      await manager.closeTab(t3.id);
      state = container.read(sessionManagerProvider);
      expect(state.activeTabId, t1!.id); // falls back to the left

      await manager.closeTab(t1.id);
      state = container.read(sessionManagerProvider);
      expect(state.tabs, isEmpty);
      expect(state.activeTabId, isNull);

      // Idempotent: closing again is a no-op.
      await manager.closeTab(t1.id);
      expect(container.read(sessionManagerProvider).tabs, isEmpty);
    });

    test('a shell ending marks only its own tab disconnected', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);
      final tabA = await manager.openSession(profile('a.example.com'));
      final tabB = await manager.openSession(profile('b.example.com'));

      service.shellsByHost['a.example.com']!.endFromRemote();
      await pumpEvents();
      final state = container.read(sessionManagerProvider);
      expect(state.tabById(tabA!.id)?.status, ConnectionStatus.disconnected);
      expect(state.tabById(tabA.id)?.notice, isNotNull);
      expect(state.tabById(tabB!.id)?.status, ConnectionStatus.connected);
    });

    test('reconnect works per tab after manual disconnect and after '
        'remote shell end', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);
      final tab = await manager.openSession(profile('ok.example.com'));

      await manager.disconnectTab(tab!.id);
      await manager.reconnectTab(tab.id);
      expect(
        container.read(sessionManagerProvider).tabById(tab.id)?.status,
        ConnectionStatus.connected,
      );
      expect(service.connectCount, 2);

      service.shellsByHost['ok.example.com']!.endFromRemote();
      await pumpEvents();
      await manager.reconnectTab(tab.id);
      expect(
        container.read(sessionManagerProvider).tabById(tab.id)?.status,
        ConnectionStatus.connected,
      );
      expect(service.connectCount, 3);
    });

    test('auth failure fails only that tab, with a typed error', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);
      final good = await manager.openSession(profile('ok.example.com'));
      final bad = await manager.openSession(profile('authfail.example.com'));

      final state = container.read(sessionManagerProvider);
      expect(state.tabById(bad!.id)?.status, ConnectionStatus.failed);
      expect(
        state.tabById(bad.id)?.error?.category,
        AppErrorCategory.authentication,
      );
      expect(state.tabById(good!.id)?.status, ConnectionStatus.connected);
    });

    test('host key prompts are serialized across tabs and attributed '
        'to the prompting tab', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);

      final pendingA = manager.openSession(profile('newkey-a.example.com'));
      await pumpEvents();
      var state = container.read(sessionManagerProvider);
      final tabA = state.tabs.single;
      expect(state.hostKeyPrompt, isNotNull);
      expect(state.hostKeyPromptTabId, tabA.id);

      // A second tab needing a prompt must wait its turn.
      final pendingB = manager.openAdditionalSession(
        profile('newkey-b.example.com'),
      );
      await pumpEvents();
      state = container.read(sessionManagerProvider);
      expect(state.tabs, hasLength(2));
      expect(state.hostKeyPromptTabId, tabA.id);

      manager.resolveHostKeyPrompt(true);
      await pendingA;
      await pumpEvents();
      state = container.read(sessionManagerProvider);
      final tabB = state.tabs.firstWhere((t) => t.id != tabA.id);
      expect(state.tabById(tabA.id)?.status, ConnectionStatus.connected);
      expect(state.hostKeyPromptTabId, tabB.id);

      // Refusing B's key fails only B.
      manager.resolveHostKeyPrompt(false);
      await pendingB;
      state = container.read(sessionManagerProvider);
      expect(state.tabById(tabB.id)?.status, ConnectionStatus.failed);
      expect(state.tabById(tabA.id)?.status, ConnectionStatus.connected);
      expect(state.hostKeyPrompt, isNull);
    });

    test(
      'password prompt flow: entered password reaches the service',
      () async {
        final service = FakeService();
        final container = await makeContainer(service);
        final manager = container.read(sessionManagerProvider.notifier);

        final pending = manager.openSession(profile('promptpw.example.com'));
        await pumpEvents();
        expect(
          container.read(sessionManagerProvider).passwordPrompt,
          isNotNull,
        );

        manager.resolvePasswordPrompt('typed-secret');
        await pending;
        expect(service.receivedPassword, 'typed-secret');
        expect(
          container.read(sessionManagerProvider).activeTab?.status,
          ConnectionStatus.connected,
        );
      },
    );

    test('tab limit: the 13th session is refused with a notice', () async {
      final service = FakeService();
      final container = await makeContainer(service);
      final manager = container.read(sessionManagerProvider.notifier);
      for (var i = 0; i < SessionManagerNotifier.maxTabs; i++) {
        await manager.openAdditionalSession(profile('h$i.example.com'));
      }
      expect(
        container.read(sessionManagerProvider).tabs,
        hasLength(SessionManagerNotifier.maxTabs),
      );
      final extra = await manager.openAdditionalSession(
        profile('overflow.example.com'),
      );
      expect(extra, isNull);
      expect(container.read(sessionManagerProvider).notice, contains('limit'));
      expect(service.connectCount, SessionManagerNotifier.maxTabs);
    });
  });
  shellInitGateTests();
}

void shellInitGateTests() {
  group('shell-init quiescence gate (ADR-023)', () {
    ({ProviderContainer container, FakeShell shell}) connect(FakeAsync async) {
      final service = FakeService();
      final container = ProviderContainer(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(
            InMemorySessionRepository(),
          ),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          sshConnectionServiceProvider.overrideWithValue(service),
        ],
      );
      container.read(sessionsProvider);
      container.read(sessionManagerProvider);
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      final target = profile('ok.example.com');
      container.read(sessionsProvider.notifier).addSession(target);
      async.flushMicrotasks();
      container.read(sessionManagerProvider.notifier).openSession(target);
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      return (container: container, shell: service.lastShell!);
    }

    test('snippet waits for first output plus a quiet window, sent once', () {
      fakeAsync((async) {
        final env = connect(async);
        addTearDown(env.container.dispose);
        String sent() => String.fromCharCodes(env.shell.input);
        // Connected but silent: nothing may be written yet (the
        // old code wrote the snippet immediately at connect).
        expect(sent(), isNot(contains('__ht_cwd(){')));
        env.shell.emitOutput('Last login: Fri Nov 20 2026\r\n');
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 399));
        expect(sent(), isNot(contains('__ht_cwd(){')));
        async.elapse(const Duration(milliseconds: 1));
        expect(sent(), contains('__ht_cwd(){'));
        // More output and time must not re-send it.
        env.shell.emitOutput(r'root@host:~# ');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect('__ht_cwd(){'.allMatches(sent()).length, 1);
      });
    });

    test('snippet falls back to a deadline when the shell is silent', () {
      fakeAsync((async) {
        final env = connect(async);
        addTearDown(env.container.dispose);
        String sent() => String.fromCharCodes(env.shell.input);
        async.elapse(const Duration(milliseconds: 2999));
        expect(sent(), isNot(contains('__ht_cwd(){')));
        async.elapse(const Duration(milliseconds: 1));
        expect(sent(), contains('__ht_cwd(){'));
      });
    });
  });
}
