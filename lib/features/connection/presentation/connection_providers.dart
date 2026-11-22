import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/known_hosts_store.dart';
import '../data/connection_tester.dart';
import '../data/ssh_connection_service.dart';

/// Trusted host keys, persisted as JSON in the application support
/// directory. Tests override with [InMemoryKnownHostsStore].
final knownHostsStoreProvider = Provider<KnownHostsStore>(
  (ref) => JsonFileKnownHostsStore(getApplicationSupportDirectory),
);

/// The SSH transport service (dartssh2). Tests override with a fake.
final sshConnectionServiceProvider = Provider<SshConnectionService>(
  (ref) => DartSshConnectionService(ref.watch(knownHostsStoreProvider)),
);

/// One-shot connection tester (Test Connection, profile spec 7.3).
final connectionTesterProvider = Provider<SshConnectionTester>(
  (ref) => SshConnectionTester(ref.watch(sshConnectionServiceProvider)),
);
