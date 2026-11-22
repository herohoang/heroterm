import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/core/security/credential_store.dart';
import 'package:heroterm/features/sessions/data/session_repository.dart';
import 'package:heroterm/features/sessions/domain/ssh_session.dart';
import 'package:heroterm/features/sessions/presentation/session_providers.dart';
import 'package:heroterm/features/sessions/presentation/sessions_controller.dart';
import 'package:heroterm/features/sessions/presentation/sessions_sidebar.dart';

void main() {
  testWidgets('a folder created on an empty library shows immediately', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(
          InMemorySessionRepository(),
        ),
        credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SessionsSidebar())),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(container.read(sessionsProvider).isLoaded, isTrue);
    expect(find.text('No sessions yet.'), findsOneWidget);

    // The user's exact path: New folder on a fresh library.
    await tester.tap(find.byKey(const Key('new-folder-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('folder-name')), 'Prod');
    await tester.tap(find.byKey(const Key('folder-save')));
    await tester.pumpAndSettle();

    expect(container.read(sessionsProvider).folders, hasLength(1));
    // Regression: the folder must render even though the library
    // still has zero sessions (the empty-state branch used to key
    // on sessions alone and swallowed the folder tree).
    expect(find.text('Prod'), findsOneWidget);

    // Once a session exists, the hint goes away and both render.
    final now = DateTime.utc(2026, 11, 20);
    await container
        .read(sessionsProvider.notifier)
        .addSession(
          SshSession(
            id: 's1',
            name: 'web-1',
            host: 'example.com',
            username: 'deploy',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('No sessions yet.'), findsNothing);
    expect(find.text('Prod'), findsOneWidget);
    expect(find.text('web-1'), findsOneWidget);
  });
}
