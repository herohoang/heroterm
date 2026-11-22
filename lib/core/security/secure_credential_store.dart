import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_store.dart';

/// [CredentialStore] backed by flutter_secure_storage, which uses the
/// macOS Keychain on macOS.
///
/// macOS note (verified against the flutter_secure_storage docs during
/// Milestone 0 dependency review): enabling Keychain Sharing via the
/// `keychain-access-groups` entitlement requires a provisioning profile,
/// which breaks distribution for free developer accounts. HeroTerm does
/// not share keychain items with other apps, so it uses the legacy
/// (non-data-protection) keychain on macOS via
/// `MacOsOptions(usesDataProtectionKeychain: false)` and does not add
/// the Keychain Sharing entitlement.
final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  static String _key(String credentialId) => 'heroterm.cred.$credentialId';

  @override
  Future<void> write(String credentialId, String secret) =>
      _storage.write(key: _key(credentialId), value: secret);

  @override
  Future<String?> read(String credentialId) =>
      _storage.read(key: _key(credentialId));

  @override
  Future<void> delete(String credentialId) =>
      _storage.delete(key: _key(credentialId));
}
