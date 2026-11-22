import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' as ssh;

import '../../../core/errors/app_error.dart';
import '../../remote_explorer/data/remote_file_service.dart';
import '../../sessions/domain/ssh_session.dart';
import '../domain/host_key.dart';
import 'known_hosts_store.dart';

/// A host key presented by a server that has no saved trust entry.
final class HostKeyChallenge {
  const HostKeyChallenge({
    required this.hostLabel,
    required this.keyType,
    required this.fingerprint,
  });

  final String hostLabel;
  final String keyType;
  final String fingerprint;
}

/// Asks the user to trust a previously unseen host key.
/// Returns true only on explicit trust.
typedef HostKeyPrompt = Future<bool> Function(HostKeyChallenge challenge);

/// Asks the user for a password that is not stored.
/// Returns null when the user cancels.
typedef PasswordPrompt = Future<String?> Function(
  String username,
  String hostLabel,
);

/// A live remote shell, behind an interface so the connection
/// controller can be tested without a real server (ADR-002 boundary).
abstract interface class RemoteShell {
  Stream<Uint8List> get stdout;
  Stream<Uint8List> get stderr;
  void writeInput(Uint8List bytes);
  void resize(int width, int height);
  Future<void> get done;
  int? get exitCode;
  Future<void> close();
}

final class _DartSshRemoteShell implements RemoteShell {
  _DartSshRemoteShell(this._client, this._session);

  final ssh.SSHClient _client;
  final ssh.SSHSession _session;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  Stream<Uint8List> get stderr => _session.stderr;

  @override
  void writeInput(Uint8List bytes) => _session.stdin.add(bytes);

  @override
  void resize(int width, int height) => _session.resizeTerminal(width, height);

  @override
  Future<void> get done => _session.done;

  @override
  int? get exitCode => _session.exitCode;

  @override
  Future<void> close() async {
    _session.close();
    _client.close();
  }
}

/// One established connection: an interactive shell plus lazily
/// opened file service and one-off command execution, all over the
/// same SSH transport.
abstract interface class RemoteConnection {
  RemoteShell get shell;

  /// The SFTP file service for this connection (opened once).
  Future<RemoteFileService> fileService();

  /// Runs a one-off command on a separate channel and returns its
  /// stdout. Note: this runs in the login directory — it cannot see
  /// the interactive shell's working directory.
  Future<String> runCommand(String command);

  Future<void> close();
}

final class _DartSshRemoteConnection implements RemoteConnection {
  _DartSshRemoteConnection(this._client, this._shell);

  final ssh.SSHClient _client;
  final _DartSshRemoteShell _shell;
  RemoteFileService? _fileService;

  @override
  RemoteShell get shell => _shell;

  @override
  Future<RemoteFileService> fileService() async {
    return _fileService ??= DartSshRemoteFileService(await _client.sftp());
  }

  @override
  Future<String> runCommand(String command) async {
    final session = await _client.execute(command);
    final buffer = StringBuffer();
    await for (final chunk in session.stdout) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));
    }
    await session.done;
    return buffer.toString().trim();
  }

  @override
  Future<void> close() => _shell.close();
}

/// The request to open one connection + shell.
final class ConnectRequest {
  const ConnectRequest({
    required this.profile,
    required this.storedSecret,
    required this.onHostKeyPrompt,
    required this.onPasswordPrompt,
    this.terminalWidth = 80,
    this.terminalHeight = 24,
  });

  final SshSession profile;

  /// The stored password (password auth) or key passphrase (key auth),
  /// read from the credential store by the caller. Null when nothing
  /// is stored — password auth then prompts.
  final String? storedSecret;
  final HostKeyPrompt onHostKeyPrompt;
  final PasswordPrompt onPasswordPrompt;
  final int terminalWidth;
  final int terminalHeight;
}

abstract interface class SshConnectionService {
  Future<RemoteConnection> connect(ConnectRequest request);
}

/// dartssh2-backed implementation.
final class DartSshConnectionService implements SshConnectionService {
  DartSshConnectionService(this._knownHosts);

  final KnownHostsStore _knownHosts;

  @override
  Future<RemoteConnection> connect(ConnectRequest request) async {
    final profile = request.profile;
    final hostLabel = '${profile.host}:${profile.port}';
    var hostKeyBlocked = false;

    ssh.SSHClient? client;
    try {
      final socket = await ssh.SSHSocket.connect(
        profile.host,
        profile.port,
        timeout: profile.connectionTimeout,
      );

      List<ssh.SSHKeyPair>? identities;
      if (profile.authMethod == AuthMethod.privateKey) {
        identities = await _loadIdentities(profile, request.storedSecret);
      }

      client = ssh.SSHClient(
        socket,
        username: profile.username,
        identities: identities,
        handshakeTimeout: profile.connectionTimeout,
        onPasswordRequest: profile.authMethod == AuthMethod.password
            ? () async =>
                  request.storedSecret ??
                  await request.onPasswordPrompt(profile.username, hostLabel)
            : null,
        onVerifyHostKey: (type, fingerprintBytes) async {
          final fingerprint = utf8.decode(fingerprintBytes);
          final stored = await _knownHosts.lookup(profile.host, profile.port);
          final decision = decideHostKey(
            stored,
            keyType: type,
            fingerprint: fingerprint,
          );
          switch (decision) {
            case HostKeyDecision.match:
              return true;
            case HostKeyDecision.changed:
              hostKeyBlocked = true;
              return false;
            case HostKeyDecision.unknown:
              final trusted = await request.onHostKeyPrompt(
                HostKeyChallenge(
                  hostLabel: hostLabel,
                  keyType: type,
                  fingerprint: fingerprint,
                ),
              );
              if (trusted) {
                await _knownHosts.save(
                  KnownHostEntry(
                    host: profile.host,
                    port: profile.port,
                    keyType: type,
                    fingerprint: fingerprint,
                  ),
                );
              }
              return trusted;
          }
        },
      );

      final session = await client.shell(
        pty: ssh.SSHPtyConfig(
          type: 'xterm-256color',
          width: request.terminalWidth,
          height: request.terminalHeight,
        ),
      );
      return _DartSshRemoteConnection(
        client,
        _DartSshRemoteShell(client, session),
      );
    } catch (e) {
      client?.close();
      if (hostKeyBlocked) {
        throw const AppError(
          category: AppErrorCategory.hostKeyChanged,
          userMessage:
              'The host key for this server has changed since it was '
              'trusted. The connection was blocked. If the server was '
              'legitimately reinstalled or re-keyed, verify the new '
              'fingerprint with the server administrator before '
              'trusting it.',
        );
      }
      throw mapConnectionError(e, hostLabel);
    }
  }

  Future<List<ssh.SSHKeyPair>> _loadIdentities(
    SshSession profile,
    String? passphrase,
  ) async {
    var path = profile.privateKeyPath ?? '';
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '';
      path = '$home${path.substring(1)}';
    }
    final file = File(path);
    if (!await file.exists()) {
      throw AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage:
            'Private key file not found, or macOS has not granted the '
            'app access to it: ${profile.privateKeyPath}. Edit the '
            'session and use Browse… to select the key file.',
      );
    }
    final String pem;
    try {
      pem = await file.readAsString();
    } on FileSystemException {
      throw AppError(
        category: AppErrorCategory.permissionDenied,
        userMessage:
            'macOS blocked access to the private key file '
            '${profile.privateKeyPath}. Edit the session and use '
            'Browse… to select the key file so the app is granted '
            'access.',
      );
    }
    try {
      return ssh.SSHKeyPair.fromPem(pem, passphrase);
    } on ssh.SSHKeyDecryptError {
      throw const AppError(
        category: AppErrorCategory.authentication,
        userMessage:
            'Could not decrypt the private key. The stored passphrase '
            'may be wrong; edit the session to update it.',
      );
    } on ssh.SSHKeyDecodeError {
      throw const AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage:
            'The private key format is not supported. HeroTerm reads '
            'OpenSSH and PEM (PKCS#1/PKCS#8) keys.',
      );
    }
  }
}

/// Maps transport/auth failures to typed, user-facing errors.
/// Messages never include secrets — only the host label and the
/// exception type.
AppError mapConnectionError(Object error, String hostLabel) {
  if (error is AppError) return error;
  if (error is ssh.SSHAuthFailError) {
    return AppError(
      category: AppErrorCategory.authentication,
      userMessage:
          'Authentication failed for $hostLabel. Check the username '
          'and the stored password or key.',
    );
  }
  if (error is ssh.SSHHostkeyError) {
    return AppError(
      category: AppErrorCategory.hostKeyChanged,
      userMessage:
          'Host key verification failed for $hostLabel. The '
          'connection was blocked.',
    );
  }
  if (error is TimeoutException) {
    return AppError(
      category: AppErrorCategory.timeout,
      userMessage:
          'Connection to $hostLabel timed out. Check that the server '
          'is reachable and the port is correct.',
    );
  }
  if (error is SocketException) {
    final osMessage = error.osError?.message ?? error.message;
    final isDns =
        osMessage.toLowerCase().contains('failed host lookup') ||
        osMessage.toLowerCase().contains('nodename') ||
        osMessage.toLowerCase().contains('no address');
    return AppError(
      category: AppErrorCategory.network,
      userMessage: isDns
          ? 'Could not resolve the host in $hostLabel. Check the '
                'hostname and your network connection.'
          : 'Could not connect to $hostLabel ($osMessage).',
    );
  }
  return AppError(
    category: AppErrorCategory.unknown,
    userMessage: 'Connection to $hostLabel failed.',
    diagnostic: error.runtimeType.toString(),
  );
}
