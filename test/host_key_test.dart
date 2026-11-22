import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/connection/data/known_hosts_store.dart';
import 'package:heroterm/features/connection/domain/host_key.dart';

void main() {
  group('decideHostKey (FEATURE_SPEC section 8)', () {
    const stored = KnownHostEntry(
      host: 'example.com',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:abc',
    );

    test('no entry is unknown (prompt for trust)', () {
      expect(
        decideHostKey(null, keyType: 'ssh-ed25519', fingerprint: 'SHA256:abc'),
        HostKeyDecision.unknown,
      );
    });

    test('same type and fingerprint match', () {
      expect(
        decideHostKey(
          stored,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:abc',
        ),
        HostKeyDecision.match,
      );
    });

    test('different fingerprint is changed (must block)', () {
      expect(
        decideHostKey(
          stored,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:different',
        ),
        HostKeyDecision.changed,
      );
    });

    test('different key type is changed (must block)', () {
      expect(
        decideHostKey(stored, keyType: 'ssh-rsa', fingerprint: 'SHA256:abc'),
        HostKeyDecision.changed,
      );
    });
  });

  group('JsonFileKnownHostsStore', () {
    late Directory dir;
    late JsonFileKnownHostsStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('heroterm_hosts_test');
      store = JsonFileKnownHostsStore(() async => dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('saved entries survive a fresh store instance', () async {
      const entry = KnownHostEntry(
        host: 'example.com',
        port: 2222,
        keyType: 'ssh-ed25519',
        fingerprint: 'SHA256:xyz',
      );
      await store.save(entry);
      final reopened = JsonFileKnownHostsStore(() async => dir);
      final loaded = await reopened.lookup('example.com', 2222);
      expect(loaded?.fingerprint, 'SHA256:xyz');
      expect(await reopened.lookup('example.com', 22), isNull);
      await reopened.remove('example.com', 2222);
      final third = JsonFileKnownHostsStore(() async => dir);
      expect(await third.lookup('example.com', 2222), isNull);
    });
  });
}
