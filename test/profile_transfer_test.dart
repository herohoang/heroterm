import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/sessions/data/profile_transfer.dart';
import 'package:heroterm/features/sessions/domain/session_folder.dart';
import 'package:heroterm/features/sessions/domain/session_label.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';

SshSession profile({
  String name = 'BigERP Staging',
  String? groupId,
  String? credentialRef = 'keychain-ref-SECRET-ID',
}) {
  final now = DateTime.utc(2026, 10, 25);
  return SshSession(
    id: 'p1',
    name: name,
    host: 'staging.example.com',
    port: 2222,
    username: 'deploy',
    authMethod: AuthMethod.privateKey,
    credentialRef: credentialRef,
    privateKeyPath: '~/.ssh/id_ed25519',
    groupId: groupId,
    description: 'Staging application server',
    labelIds: ['l-stage', 'l-app'],
    icon: 'database',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('Profile export (spec 6.5)', () {
    test('export matches the spec shape and strips every secret', () {
      final folder = SessionFolder(
        id: 'f1',
        name: 'BigERP',
        type: FolderType.project,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final now = DateTime.utc(2026, 10, 25);
      final labelsById = {
        'l-stage': SessionLabel(
          id: 'l-stage',
          name: 'Staging',
          colorValue: labelPalette[1],
          createdAt: now,
          updatedAt: now,
        ),
        'l-app': SessionLabel(
          id: 'l-app',
          name: 'app',
          colorValue: labelPalette[5],
          createdAt: now,
          updatedAt: now,
        ),
      };
      final json = ProfileTransfer.exportJson(
        profiles: [profile(groupId: 'f1')],
        foldersById: {'f1': folder},
        labelsById: labelsById,
        exportedAt: DateTime.utc(2026, 10, 25),
      );
      // Secret stripping: neither the reference ID nor any
      // credential-flavoured key may appear anywhere in the output.
      expect(json, isNot(contains('keychain-ref-SECRET-ID')));
      expect(json.toLowerCase(), isNot(contains('credentialref')));
      expect(json.toLowerCase(), isNot(contains('password')));
      expect(json.toLowerCase(), isNot(contains('passphrase')));
      // And the portable shape parses back.
      final parsed = ProfileTransfer.parseImport(json);
      expect(parsed, hasLength(1));
      final p = parsed.single;
      expect(p.draft.name, 'BigERP Staging');
      expect(p.draft.authMethod, AuthMethod.privateKey);
      expect(p.draft.privateKeyPath, '~/.ssh/id_ed25519');
      expect(p.labelNames, ['Staging', 'app']);
      expect(p.draft.icon, 'database');
      expect(p.draft.credentialRef, isNull);
      expect(p.groupName, 'BigERP');
      expect(p.groupType, FolderType.project);
    });
  });

  group('Profile import validation (spec 6.5, section 9)', () {
    String wrap(String profiles) =>
        '{"schemaVersion": 1, "profiles": [$profiles]}';

    test('rejects malformed JSON and wrong shapes', () {
      expect(
        () => ProfileTransfer.parseImport('not json'),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport('[1,2]'),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () =>
            ProfileTransfer.parseImport('{"schemaVersion": 2, "profiles": []}'),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport('{"schemaVersion": 1}'),
        throwsA(isA<ProfileImportException>()),
      );
    });

    test('rejects out-of-range and invalid field values', () {
      const base =
          '"name": "x", "host": "ok.example.com", "username": "deploy"';
      expect(
        () => ProfileTransfer.parseImport(wrap('{$base, "port": 70000}')),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport(
          wrap('{$base, "connectionTimeoutSeconds": 121}'),
        ),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport(
          wrap('{"name": "x", "host": "not a host", "username": "deploy"}'),
        ),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport(
          wrap('{$base, "environment": "prod-ish"}'),
        ),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport(
          wrap('{$base, "authMethod": "privateKey"}'),
        ),
        throwsA(isA<ProfileImportException>()),
      );
      expect(
        () => ProfileTransfer.parseImport(
          wrap('{"name": "", "host": "ok.example.com", "username": "d"}'),
        ),
        throwsA(isA<ProfileImportException>()),
      );
    });

    test('applies spec defaults for omitted optional fields', () {
      final parsed = ProfileTransfer.parseImport(
        wrap('{"name": "x", "host": "ok.example.com", "username": "deploy"}'),
      );
      final p = parsed.single;
      expect(p.draft.port, 22);
      expect(p.draft.connectionTimeout, const Duration(seconds: 15));
      expect(p.labelNames, isEmpty);
      expect(p.draft.authMethod, AuthMethod.password);
      expect(p.groupName, isNull);
    });

    test('conflict key is name+host+username+port, never host alone', () {
      final a = ProfileTransfer.parseImport(
        wrap(
          '{"name": "one", "host": "h.example.com", "username": "a", '
          '"port": 22}',
        ),
      ).single;
      final b = ProfileTransfer.parseImport(
        wrap(
          '{"name": "two", "host": "h.example.com", "username": "a", '
          '"port": 22}',
        ),
      ).single;
      expect(a.conflictKey, isNot(b.conflictKey));
      final c = ProfileTransfer.parseImport(
        wrap(
          '{"name": "ONE", "host": "H.EXAMPLE.COM", "username": "a", '
          '"port": 22}',
        ),
      ).single;
      expect(a.conflictKey, c.conflictKey);
    });
  });
}
