import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/remote_explorer/data/remote_file_service.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_entry.dart';
import 'package:heroterm/features/remote_explorer/presentation/explorer_controller.dart';
import 'package:heroterm/features/remote_explorer/presentation/remote_explorer.dart';

/// Minimal in-memory RemoteFileService over a fixed directory tree.
final class _TreeFileService implements RemoteFileService {
  _TreeFileService(this.tree);

  /// directory path -> entries shown inside it.
  final Map<String, List<RemoteEntry>> tree;

  @override
  Future<List<RemoteEntry>> list(String path) async =>
      List.of(tree[path] ?? const []);

  @override
  Future<String> canonicalize(String path) async => path;

  @override
  Future<String> homeDirectory() async => '/home/herotest';

  @override
  Future<bool> exists(String path) async => tree.containsKey(path);

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<void> deleteRecursively(String path) async {}

  @override
  Future<DownloadHandle> openDownload(String path) =>
      throw UnimplementedError();

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<UploadHandle> openUpload(String path) => throw UnimplementedError();

  @override
  Future<RemoteFileStat> stat(String path) => throw UnimplementedError();

  @override
  Future<Uint8List> readBytes(String path, {required int maxBytes}) =>
      throw UnimplementedError();

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      throw UnimplementedError();
}

RemoteEntry _file(String name, String path) => RemoteEntry(
  name: name,
  path: path,
  kind: RemoteEntryKind.file,
  size: 42,
  modifiedAt: DateTime.utc(2026, 11, 22, 9),
);

void main() {
  testWidgets('an empty subfolder still shows ".." and it navigates up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _TreeFileService({
      '/': const [],
      '/home/herotest': [_file('readme.txt', '/home/herotest/readme.txt')],
      '/home/herotest/empty': const [],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(explorerProvider.notifier)
        .attach(service, reportedCwd: '/home/herotest/empty');
    expect(
      container.read(explorerProvider).currentPath,
      '/home/herotest/empty',
    );
    expect(container.read(explorerProvider).entries, isEmpty);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RemoteExplorer())),
      ),
    );
    await tester.pumpAndSettle();

    // The empty state is expected — but it must not swallow the
    // parent row: without ".." the table offers no way back up.
    expect(find.text('This directory is empty.'), findsOneWidget);
    expect(find.text('..'), findsOneWidget);

    // Tapping ".." goes to the parent directory and its listing.
    await tester.tap(find.text('..'));
    await tester.pumpAndSettle();
    expect(container.read(explorerProvider).currentPath, '/home/herotest');
    expect(find.text('readme.txt'), findsOneWidget);
  });

  testWidgets('an empty root directory shows no ".." row', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = _TreeFileService({'/': const []});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(explorerProvider.notifier)
        .attach(service, reportedCwd: '/');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RemoteExplorer())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This directory is empty.'), findsOneWidget);
    expect(find.text('..'), findsNothing);
  });
}
