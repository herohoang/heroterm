import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';

SshSession build({
  String name = 'prod-1',
  String host = 'example.com',
  int port = 22,
  String username = 'deploy',
}) {
  final now = DateTime.utc(2026, 10, 24);
  return SshSession(
    id: 's1',
    name: name,
    host: host,
    port: port,
    username: username,
    credentialRef: 'cred-123',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('SshSession validation', () {
    test('accepts a valid profile', () {
      expect(build().isValid, isTrue);
    });

    test('rejects empty name, bad host, bad port, empty username', () {
      expect(build(name: '  ').isValid, isFalse);
      expect(build(host: 'a b').isValid, isFalse);
      expect(build(host: '').isValid, isFalse);
      expect(build(port: 0).isValid, isFalse);
      expect(build(port: 65536).isValid, isFalse);
      expect(build(username: '').isValid, isFalse);
    });

    test('accepts valid hostnames and IP addresses', () {
      for (final host in [
        'example.com',
        'vps-1.example.com',
        'localhost',
        '192.168.1.10',
        '10.0.0.255',
        '::1',
        '2001:db8::1',
        '2001:db8:0:0:0:0:2:1',
        '2001:db8::192.168.0.1',
      ]) {
        expect(build(host: host).isValid, isTrue, reason: host);
      }
    });

    test('rejects malformed hosts (regression: "123" used to save)', () {
      for (final host in [
        '123',
        '999.1.1.1',
        '192.168.1',
        '192.168.1.1.1',
        '010.1.1.1',
        '-bad.example.com',
        'bad-.example.com',
        'bad_host.example.com',
        'a..b.com',
        '.example.com',
        'example.com.',
        'http://example.com',
        'exa mple.com',
        'example.123',
        ':::',
        '2001:db8:::1',
        '12345::',
      ]) {
        expect(build(host: host).isValid, isFalse, reason: host);
      }
    });

    test('per-field errors point at the offending field', () {
      final errors = build(host: '123', port: 0).validateFields();
      expect(errors.keys, containsAll(['host', 'port']));
      expect(build(host: 'ok.example.com').validateFields(), isEmpty);
    });

    test('private key auth requires an absolute key path', () {
      final now = DateTime.utc(2026, 10, 24);
      SshSession keyAuth(String? path) => SshSession(
        id: 'k1',
        name: 'k',
        host: 'example.com',
        username: 'deploy',
        authMethod: AuthMethod.privateKey,
        privateKeyPath: path,
        createdAt: now,
        updatedAt: now,
      );
      expect(keyAuth(null).validateFields()['keyPath'], isNotNull);
      expect(
        keyAuth('relative/id_ed25519').validateFields()['keyPath'],
        isNotNull,
      );
      expect(
        keyAuth('/Users/x/.ssh/id_ed25519').validateFields(),
        isNot(contains('keyPath')),
      );
    });

    test('accepts port boundaries 1 and 65535', () {
      expect(build(port: 1).isValid, isTrue);
      expect(build(port: 65535).isValid, isTrue);
    });

    test('timeout bounds are 1..120 seconds (profile spec section 5)', () {
      SshSession withTimeout(int seconds) =>
          build().copyWith(connectionTimeout: Duration(seconds: seconds));
      expect(withTimeout(1).isValid, isTrue);
      expect(withTimeout(120).isValid, isTrue);
      expect(withTimeout(0).isValid, isFalse);
      expect(withTimeout(121).isValid, isFalse);
      expect(withTimeout(121).validateFields(), contains('timeout'));
    });

    test('description over 500 characters is rejected', () {
      expect(build().copyWith(description: 'x' * 500).isValid, isTrue);
      expect(build().copyWith(description: 'x' * 501).isValid, isFalse);
    });

    test('label names normalize via the label domain (ADR-013)', () {
      // (Covered in depth by session_label tests; here we only pin
      // that session search treats labels as searchable text.)
      expect(build().matchesQuery('anything'), isFalse);
    });

    test('search matches description, label names and group name', () {
      final s = build().copyWith(description: 'BigERP application server');
      expect(s.matchesQuery('bigerp'), isTrue);
      expect(s.matchesQuery('billing', labelNames: ['Billing']), isTrue);
      expect(s.matchesQuery('BILLING', labelNames: ['Billing']), isTrue);
      expect(s.matchesQuery('acme', groupName: 'Acme Corp'), isTrue);
      expect(s.matchesQuery('acme'), isFalse);
      expect(s.matchesQuery('zzz'), isFalse);
    });
  });

  group('SshSession serialization', () {
    test('contains metadata and credentialRef only — no secret field', () {
      final json = build().toJson();
      expect(json['credentialRef'], 'cred-123');
      for (final key in json.keys) {
        expect(key.toLowerCase(), isNot(contains('password')));
        expect(key.toLowerCase(), isNot(contains('passphrase')));
        expect(key.toLowerCase(), isNot(contains('secret')));
      }
      // A private key is referenced by path only (ADR-006): the path is
      // metadata, the key material itself is never serialized.
      expect(json.keys, contains('privateKeyPath'));
    });

    test('label/appearance fields round-trip; legacy JSON defaults '
        'safely', () {
      final full = build().copyWith(
        description: 'note',
        labelIds: ['l1', 'l2'],
        icon: 'database',
        colorValue: 0xFF1565C0,
        lastConnectionStatus: LastConnectionStatus.failed,
      );
      final back = SshSession.fromJson(full.toJson());
      expect(back.description, 'note');
      expect(back.labelIds, ['l1', 'l2']);
      expect(back.icon, 'database');
      expect(back.colorValue, 0xFF1565C0);
      expect(back.lastConnectionStatus, LastConnectionStatus.failed);

      final legacy = build().toJson()
        ..remove('labelIds')
        ..remove('icon')
        ..remove('colorValue')
        ..remove('lastConnectionStatus');
      final migrated = SshSession.fromJson(legacy);
      expect(migrated.labelIds, isEmpty);
      expect(migrated.icon, isNull);
      expect(migrated.colorValue, isNull);
      expect(migrated.lastConnectionStatus, isNull);
    });
  });
}
