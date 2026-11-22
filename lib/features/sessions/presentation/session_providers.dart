import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/security/credential_store.dart';
import '../../../core/security/secure_credential_store.dart';
import '../data/session_repository.dart';

/// The app's credential store. On macOS this is backed by the Keychain
/// (see [SecureCredentialStore]). Tests override this provider with
/// [InMemoryCredentialStore].
final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => SecureCredentialStore(),
);

/// The app's session-metadata repository: a JSON file in the
/// application support directory (ADR-006). Tests override this
/// provider with [InMemorySessionRepository] or a temp-directory
/// [JsonFileSessionRepository].
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => JsonFileSessionRepository(getApplicationSupportDirectory),
);
