/// Abstraction over secure secret storage (ARCHITECTURE: Credential store).
///
/// Implementations store secrets by an opaque [credentialId]. Session
/// metadata only ever holds that id (`credentialRef`), never the secret
/// itself. Secrets must never be written to SQLite, JSON/YAML config,
/// logs, or source control (SECURITY.md).
abstract interface class CredentialStore {
  Future<void> write(String credentialId, String secret);
  Future<String?> read(String credentialId);
  Future<void> delete(String credentialId);
}

/// In-memory implementation for tests and UI previews only.
/// Never use this for real credentials in a released build.
final class InMemoryCredentialStore implements CredentialStore {
  final Map<String, String> _secrets = <String, String>{};

  @override
  Future<void> write(String credentialId, String secret) async {
    _secrets[credentialId] = secret;
  }

  @override
  Future<String?> read(String credentialId) async => _secrets[credentialId];

  @override
  Future<void> delete(String credentialId) async {
    _secrets.remove(credentialId);
  }
}
