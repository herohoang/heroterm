import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/core/security/credential_store.dart';
import 'package:heroterm/features/sessions/data/profile_transfer.dart';
import 'package:heroterm/features/sessions/data/session_repository.dart';
import 'package:heroterm/features/sessions/domain/session_folder.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';
import 'package:heroterm/features/sessions/presentation/session_providers.dart';
import 'package:heroterm/features/sessions/presentation/sessions_controller.dart';

SshSession draft(String name) {
  final now = DateTime.utc(2026, 10, 24, 12);
  return SshSession(
    id: 'id-$name',
    name: name,
    host: 'example.com',
    username: 'deploy',
    createdAt: now,
    updatedAt: now,
  );
}

Future<ProviderContainer> loadedContainer({
  InMemorySessionRepository? repo,
  InMemoryCredentialStore? creds,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(
        repo ?? InMemorySessionRepository(),
      ),
      credentialStoreProvider.overrideWithValue(
        creds ?? InMemoryCredentialStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(sessionsProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  expect(container.read(sessionsProvider).isLoaded, isTrue);
  return container;
}

void main() {
  group('SessionsNotifier (Milestone 1)', () {
    test('addSession stores the secret only in the credential store', () async {
      final repo = InMemorySessionRepository();
      final creds = InMemoryCredentialStore();
      final container = await loadedContainer(repo: repo, creds: creds);
      final notifier = container.read(sessionsProvider.notifier);

      final created = await notifier.addSession(
        draft('Prod'),
        secret: 'canary-password-123',
      );

      expect(created.credentialRef, isNotNull);
      expect(await creds.read(created.credentialRef!), 'canary-password-123');
      final saved = await repo.load();
      expect(saved.sessions.single.credentialRef, created.credentialRef);
      expect(
        saved.sessions.single.toJson().values,
        isNot(contains('canary-password-123')),
      );
    });

    test('changes survive a restart (reload from the repository)', () async {
      final repo = InMemorySessionRepository();
      final first = await loadedContainer(repo: repo);
      final notifier = first.read(sessionsProvider.notifier);
      final folder = await notifier.addFolder('Work');
      await notifier.addSession(draft('Prod').copyWith(groupId: folder.id));

      final second = await loadedContainer(repo: repo);
      final state = second.read(sessionsProvider);
      expect(state.folders.single.name, 'Work');
      expect(state.sessions.single.name, 'Prod');
      expect(state.sessions.single.groupId, folder.id);
    });

    test('duplicate shares the credential reference (profile spec 6.4) '
        'and names the copy with a Copy suffix', () async {
      final creds = InMemoryCredentialStore();
      final container = await loadedContainer(creds: creds);
      final notifier = container.read(sessionsProvider.notifier);
      final created = await notifier.addSession(draft('Prod'), secret: 'pw');
      final copy = await notifier.duplicateSession(created.id);

      expect(copy, isNotNull);
      expect(copy!.name, 'Prod Copy');
      expect(copy.id, isNot(created.id));
      // Same reference, no second copy of the secret anywhere.
      expect(copy.credentialRef, created.credentialRef);
      expect(await creds.read(copy.credentialRef!), 'pw');

      // A second duplicate gets a numeric suffix.
      final copy2 = await notifier.duplicateSession(created.id);
      expect(copy2!.name, 'Prod Copy 2');

      // Deleting the original must not remove the shared secret
      // while the copies still reference it.
      await notifier.deleteSession(created.id);
      expect(await creds.read(copy.credentialRef!), 'pw');
      await notifier.deleteSession(copy.id);
      expect(await creds.read(copy.credentialRef!), 'pw');
      // Deleting the last referencing profile removes it.
      await notifier.deleteSession(copy2.id);
      expect(await creds.read(copy.credentialRef!), isNull);
    });

    test('editing a duplicate\'s secret copy-on-writes: the shared '
        'entry is untouched', () async {
      final creds = InMemoryCredentialStore();
      final container = await loadedContainer(creds: creds);
      final notifier = container.read(sessionsProvider.notifier);
      final created = await notifier.addSession(draft('Prod'), secret: 'pw');
      final copy = await notifier.duplicateSession(created.id);

      await notifier.updateSession(
        copy!.copyWith(name: 'Prod Copy'),
        secret: 'new-pw',
      );
      final after = container.read(sessionsProvider).sessions;
      final editedCopy = after.firstWhere((s) => s.id == copy.id);
      final original = after.firstWhere((s) => s.id == created.id);
      expect(editedCopy.credentialRef, isNot(original.credentialRef));
      expect(await creds.read(original.credentialRef!), 'pw');
      expect(await creds.read(editedCopy.credentialRef!), 'new-pw');
    });

    test('label filter (ALL selected labels) combines with search '
        '(ADR-013)', () async {
      final container = await loadedContainer();
      final notifier = container.read(sessionsProvider.notifier);
      final prod = await notifier.addLabel('Production');
      final billing = await notifier.addLabel('billing');
      await notifier.addSession(
        draft('Alpha').copyWith(labelIds: [prod.id, billing.id]),
      );
      await notifier.addSession(draft('Beta').copyWith(labelIds: [prod.id]));
      notifier.toggleLabelFilter(prod.id);
      var filtered = container.read(sessionsProvider).filteredSessions;
      expect(filtered.map((s) => s.name), ['Alpha', 'Beta']);
      notifier.toggleLabelFilter(billing.id);
      filtered = container.read(sessionsProvider).filteredSessions;
      expect(filtered.map((s) => s.name), ['Alpha']);
      notifier.setQuery('bet');
      filtered = container.read(sessionsProvider).filteredSessions;
      expect(filtered, isEmpty);
      notifier.clearFilters();
      filtered = container.read(sessionsProvider).filteredSessions;
      expect(filtered, hasLength(2));
    });

    test('label CRUD: dedupe by name, delete detaches everywhere', () async {
      final container = await loadedContainer();
      final notifier = container.read(sessionsProvider.notifier);
      final a = await notifier.addLabel('Ops');
      final dup = await notifier.addLabel(' ops ');
      expect(dup.id, a.id);
      final session = await notifier.addSession(
        draft('Prod').copyWith(labelIds: [a.id]),
      );
      await notifier.renameLabel(a.id, 'Operations');
      expect(container.read(sessionsProvider).labels.single.name, 'Operations');
      await notifier.deleteLabel(a.id);
      final state = container.read(sessionsProvider);
      expect(state.labels, isEmpty);
      expect(
        state.sessions.firstWhere((s) => s.id == session.id).labelIds,
        isEmpty,
      );
    });

    test('legacy environment/tags migrate to labels on load '
        '(ADR-013)', () async {
      final legacy = SshSession(
        id: 'legacy-1',
        name: 'Legacy',
        host: 'legacy.example.com',
        username: 'deploy',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final repo = InMemorySessionRepository((
        sessions: [legacy],
        folders: const [],
        labels: const [],
        legacyLabelNames: const {
          'legacy-1': ['Production', 'billing'],
        },
      ));
      final container = await loadedContainer(repo: repo);
      final state = container.read(sessionsProvider);
      expect(
        state.labels.map((l) => l.name),
        containsAll(['Production', 'billing']),
      );
      final production = state.labels.firstWhere((l) => l.name == 'Production');
      // Canonical colour: Production stays red after migration.
      expect(production.colorValue, 0xFFD32F2F);
      expect(state.sessions.single.labelIds, hasLength(2));
    });

    test('markConnectionFailed records the outcome only', () async {
      final container = await loadedContainer();
      final notifier = container.read(sessionsProvider.notifier);
      final created = await notifier.addSession(draft('Prod'));
      await notifier.markConnectionFailed(created.id);
      var saved = container.read(sessionsProvider).sessions.single;
      expect(saved.lastConnectionStatus, LastConnectionStatus.failed);
      expect(saved.lastConnectedAt, isNull);
      await notifier.markConnected(created.id);
      saved = container.read(sessionsProvider).sessions.single;
      expect(saved.lastConnectionStatus, LastConnectionStatus.success);
      expect(saved.lastConnectedAt, isNotNull);
    });

    test('import: skip/copy/update strategies and group matching '
        '(profile spec 6.5)', () async {
      final container = await loadedContainer();
      final notifier = container.read(sessionsProvider.notifier);
      final existing = await notifier.addSession(
        draft('Prod'),
        secret: 'keep-me',
      );
      // The import file intentionally uses the LEGACY environment/
      // tags fields (pre-label exports): they must land as labels.
      final imported = ProfileTransfer.parseImport('''
{
  "schemaVersion": 1,
  "profiles": [
    {"name": "Prod", "host": "example.com", "port": 22,
     "username": "deploy", "authMethod": "password",
     "environment": "production",
     "group": {"name": "BigERP", "type": "project"},
     "connectionTimeoutSeconds": 30, "description": "from import",
     "tags": ["app"]},
    {"name": "Fresh", "host": "fresh.example.com", "port": 2222,
     "username": "root", "authMethod": "password",
     "labels": ["Development"],
     "group": {"name": "BigERP", "type": "project"}}
  ]
}
''');
      // Prod conflicts (same name/host/username/port as draft()).
      var result = await notifier.importProfiles(
        imported,
        ImportConflictStrategy.skip,
      );
      expect(result.added, 1);
      expect(result.skipped, 1);
      var state = container.read(sessionsProvider);
      expect(state.sessions, hasLength(2));
      // The group was created once and shared by name+type.
      expect(state.folders, hasLength(1));
      expect(state.folders.single.type, FolderType.project);

      // Update: imported fields win, identity + secret survive.
      result = await notifier.importProfiles(
        imported,
        ImportConflictStrategy.update,
      );
      expect(result.updated, 2);
      state = container.read(sessionsProvider);
      final prod = state.sessions.firstWhere((s) => s.id == existing.id);
      expect(prod.description, 'from import');
      expect(prod.credentialRef, existing.credentialRef);
      // Legacy environment + tags became labels on the profile.
      final prodLabelNames = state.labelsOf(prod).map((l) => l.name).toSet();
      expect(prodLabelNames, containsAll(['Production', 'app']));
      final fresh = state.sessions.firstWhere((s) => s.name == 'Fresh');
      expect(state.labelsOf(fresh).map((l) => l.name), ['Development']);

      // Copy: the conflict arrives renamed, the new one duplicates too.
      result = await notifier.importProfiles(
        imported,
        ImportConflictStrategy.copy,
      );
      expect(result.added, 2);
      state = container.read(sessionsProvider);
      expect(state.sessions.map((s) => s.name), contains('Prod Copy 2'));
    });

    test('deleteSession removes its stored credential', () async {
      final creds = InMemoryCredentialStore();
      final container = await loadedContainer(creds: creds);
      final notifier = container.read(sessionsProvider.notifier);
      final created = await notifier.addSession(draft('Prod'), secret: 'pw');
      await notifier.deleteSession(created.id);
      expect(await creds.read(created.credentialRef!), isNull);
      expect(container.read(sessionsProvider).sessions, isEmpty);
    });

    test(
      'deleting a folder moves sessions to Ungrouped, never deletes',
      () async {
        final container = await loadedContainer();
        final notifier = container.read(sessionsProvider.notifier);
        final folder = await notifier.addFolder('Work');
        await notifier.addFolder('Sub', parentId: folder.id);
        await notifier.addSession(draft('Prod').copyWith(groupId: folder.id));

        await notifier.deleteFolder(folder.id);

        final state = container.read(sessionsProvider);
        expect(state.sessions.single.groupId, isNull);
        expect(state.folders.single.name, 'Sub');
        expect(state.folders.single.parentId, isNull);
      },
    );

    test('moveSession and search filter work', () async {
      final container = await loadedContainer();
      final notifier = container.read(sessionsProvider.notifier);
      final folder = await notifier.addFolder('Work');
      await notifier.addSession(draft('Alpha'));
      await notifier.addSession(draft('Beta'));

      await notifier.moveSession('id-Alpha', folder.id);
      var state = container.read(sessionsProvider);
      expect(
        state.sessions.firstWhere((s) => s.name == 'Alpha').groupId,
        folder.id,
      );

      notifier.setQuery('alp');
      state = container.read(sessionsProvider);
      expect(state.filteredSessions.map((s) => s.name), ['Alpha']);
    });

    test('updateSession with empty secret removes the credential', () async {
      final creds = InMemoryCredentialStore();
      final container = await loadedContainer(creds: creds);
      final notifier = container.read(sessionsProvider.notifier);
      final created = await notifier.addSession(draft('Prod'), secret: 'pw');
      await notifier.updateSession(created, secret: '');
      expect(await creds.read(created.credentialRef!), isNull);
      expect(
        container.read(sessionsProvider).sessions.single.credentialRef,
        isNull,
      );
    });
  });
}
