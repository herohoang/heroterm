import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/core/errors/app_error.dart';
import 'package:heroterm/features/connection/data/connection_tester.dart';
import 'package:heroterm/features/connection/data/ssh_connection_service.dart';
import 'package:heroterm/features/remote_explorer/data/remote_file_service.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';

final class _Shell implements RemoteShell {
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

final class _Connection implements RemoteConnection {
  final _shell = _Shell();
  bool closed = false;
  @override
  RemoteShell get shell => _shell;
  @override
  Future<RemoteFileService> fileService() => throw UnimplementedError();
  @override
  Future<String> runCommand(String command) async => '';
  @override
  Future<void> close() async {
    closed = true;
    await _shell.close();
  }
}

final class _Service implements SshConnectionService {
  _Connection? lastConnection;
  @override
  Future<RemoteConnection> connect(ConnectRequest request) async {
    if (request.profile.host == 'authfail.example.com') {
      throw const AppError(
        category: AppErrorCategory.authentication,
        userMessage: 'Authentication failed.',
      );
    }
    lastConnection = _Connection();
    return lastConnection!;
  }
}

SshSession prof(String host) {
  final now = DateTime.utc(2026, 10, 25);
  return SshSession(
    id: 'p-$host',
    name: host,
    host: host,
    username: 'deploy',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('SshConnectionTester (profile spec 7.3)', () {
    test('success connects and closes immediately', () async {
      final service = _Service();
      final tester = SshConnectionTester(service);
      final result = await tester.test(
        prof('ok.example.com'),
        onHostKeyPrompt: (_) async => true,
        onPasswordPrompt: (_, _) async => null,
      );
      expect(result.success, isTrue);
      expect(result.message, contains('succeeded'));
      expect(service.lastConnection!.closed, isTrue);
    });

    test('failure surfaces the actionable, secret-free message', () async {
      final tester = SshConnectionTester(_Service());
      final result = await tester.test(
        prof('authfail.example.com'),
        onHostKeyPrompt: (_) async => true,
        onPasswordPrompt: (_, _) async => null,
      );
      expect(result.success, isFalse);
      expect(result.message, 'Authentication failed.');
    });
  });
}
