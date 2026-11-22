import '../../../core/errors/app_error.dart';
import '../../sessions/domain/ssh_session.dart';
import 'ssh_connection_service.dart';

/// Outcome of a one-shot connection test (profile spec 7.3): a
/// success flag plus an actionable, secret-free message.
final class ConnectionTestResult {
  const ConnectionTestResult(this.success, this.message);

  final bool success;
  final String message;
}

/// Test Connection (profile spec 7.3): opens a real connection
/// through the normal SSH service — so host-key verification,
/// authentication and the profile's configured timeouts all apply
/// exactly as for a real connect — then closes it immediately.
/// No terminal session is created or kept.
final class SshConnectionTester {
  SshConnectionTester(this._service);

  final SshConnectionService _service;

  Future<ConnectionTestResult> test(
    SshSession profile, {
    String? storedSecret,
    required HostKeyPrompt onHostKeyPrompt,
    required PasswordPrompt onPasswordPrompt,
  }) async {
    try {
      final connection = await _service.connect(
        ConnectRequest(
          profile: profile,
          storedSecret: storedSecret,
          onHostKeyPrompt: onHostKeyPrompt,
          onPasswordPrompt: onPasswordPrompt,
        ),
      );
      await connection.close();
      return ConnectionTestResult(
        true,
        'Connection to ${profile.username}@${profile.host}:${profile.port} '
        'succeeded.',
      );
    } on AppError catch (e) {
      // AppError messages are user-facing and secret-free by design.
      return ConnectionTestResult(false, e.userMessage);
    } catch (e) {
      return const ConnectionTestResult(
        false,
        'Connection failed unexpectedly.',
      );
    }
  }
}
