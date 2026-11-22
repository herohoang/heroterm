import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/sessions/data/session_repository.dart';
import 'package:heroterm/features/sessions/domain/session_folder.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';

SshSession sampleSession() {
  final now = DateTime.utc(2026, 10, 24, 12);
  return SshSession(
    id: 's1',
    name: 'Production',
    host: 'prod.example.com',
    port: 2222,
    username: 'deploy',
    authMethod: AuthMethod.privateKey,
    credentialRef: 'cred-1',
    privateKeyPath: '/Users/test/.ssh/id_ed25519',
    connectionTimeout: const Duration(seconds: 30),
    startupDirectory: '/var/www',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('JsonFileSessionRepository (TEST_PLAN: session persistence)', () {
    late Directory dir;
    late JsonFileSessionRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('heroterm_repo_test');
      repo = JsonFileSessionRepository(() async => dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('missing file loads as an empty library', () async {
      final library = await repo.load();
      expect(library.sessions, isEmpty);
      expect(library.folders, isEmpty);
    });

    test('save then load round-trips metadata exactly', () async {
      final now = DateTime.utc(2026, 10, 24, 12);
      final folder = SessionFolder(
        id: 'f1',
        name: 'Work',
        sortOrder: 3,
        createdAt: now,
        updatedAt: now,
      );
      await repo.save((
        sessions: [sampleSession()],
        folders: [folder],
        labels: const [],
        legacyLabelNames: const {},
      ));
      final loaded = await repo.load();
      expect(loaded.sessions.single.toJson(), sampleSession().toJson());
      expect(loaded.folders.single.toJson(), folder.toJson());
    });

    test('persisted JSON holds no secret material', () async {
      await repo.save((
        sessions: [sampleSession()],
        folders: const [],
        labels: const [],
        legacyLabelNames: const {},
      ));
      final raw = await File('${dir.path}/heroterm-sessions.json')
          .readAsString();
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final sessionJson =
          (decoded['sessions'] as List<Object?>).single as Map<String, Object?>;
      expect(sessionJson.keys, isNot(contains('password')));
      expect(sessionJson.keys, isNot(contains('secret')));
      expect(sessionJson.keys, isNot(contains('passphrase')));
      // Only the opaque reference is persisted.
      expect(sessionJson['credentialRef'], 'cred-1');
    });

    test('legacy environment/tags surface as label migration seeds '
        '(ADR-013)', () async {
      final file = File('${dir.path}/heroterm-sessions.json');
      await file.writeAsString(
        '{"version": 1, "sessions": [{'
        '"id": "s1", "name": "Old", "host": "old.example.com", '
        '"username": "deploy", "environment": "production", '
        '"tags": ["billing", "app"], '
        '"createdAt": "2026-10-24T00:00:00.000Z", '
        '"updatedAt": "2026-10-24T00:00:00.000Z"}], "folders": []}',
      );
      final library = await repo.load();
      expect(library.sessions.single.labelIds, isEmpty);
      expect(library.legacyLabelNames['s1'], ['Production', 'billing', 'app']);
      // 'other' means unspecified: no seed.
      await file.writeAsString(
        '{"version": 1, "sessions": [{'
        '"id": "s2", "name": "Plain", "host": "p.example.com", '
        '"username": "deploy", "environment": "other", '
        '"createdAt": "2026-10-24T00:00:00.000Z", '
        '"updatedAt": "2026-10-24T00:00:00.000Z"}], "folders": []}',
      );
      final library2 = await repo.load();
      expect(library2.legacyLabelNames, isEmpty);
    });

    test('corrupt file is preserved as .corrupt and loads empty', () async {
      final file = File('${dir.path}/heroterm-sessions.json');
      await file.writeAsString('this is not json');
      final library = await repo.load();
      expect(library.sessions, isEmpty);
      expect(await File('${file.path}.corrupt').exists(), isTrue);
    });
  });
}
