import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/core/errors/app_error.dart';
import 'package:heroterm/features/remote_explorer/data/remote_file_service.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_entry.dart';
import 'package:heroterm/features/remote_explorer/presentation/explorer_controller.dart';

/// Mutable in-memory RemoteFileService: paths map to entries or
/// byte contents, so rename/delete/download behave like a real SFTP
/// server at the granularity the controller cares about.
final class FakeFileService implements RemoteFileService {
  FakeFileService(this.tree, {this.files = const {}});

  /// directory path -> entries, or an AppError value to throw.
  final Map<String, Object> tree;

  /// file path -> contents served by openDownload.
  final Map<String, List<int>> files;

  /// path -> bytes received through openUpload.
  final Map<String, List<int>> uploaded = {};

  final List<String> calls = [];

  @override
  Future<List<RemoteEntry>> list(String path) async {
    final result = tree[path];
    if (result is AppError) throw result;
    if (result is List<RemoteEntry>) return List.of(result);
    throw const AppError(
      category: AppErrorCategory.remotePathMissing,
      userMessage: 'missing',
    );
  }

  @override
  Future<String> canonicalize(String path) async => path;

  @override
  Future<String> homeDirectory() async => '/home/herotest';

  @override
  Future<bool> exists(String path) async {
    if (tree.containsKey(path) || files.containsKey(path)) return true;
    for (final entries in tree.values) {
      if (entries is List<RemoteEntry> && entries.any((e) => e.path == path)) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<void> rename(String from, String to) async {
    calls.add('rename $from -> $to');
    final parent = from.substring(0, from.lastIndexOf('/'));
    final entries = tree[parent];
    if (entries is List<RemoteEntry>) {
      final index = entries.indexWhere((e) => e.path == from);
      if (index >= 0) {
        final old = entries[index];
        entries[index] = RemoteEntry(
          name: to.split('/').last,
          path: to,
          kind: old.kind,
          size: old.size,
        );
      }
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    calls.add('deleteFile $path');
  }

  @override
  Future<void> deleteRecursively(String path) async {
    calls.add('deleteRecursively $path');
    tree.remove(path);
  }

  @override
  Future<void> createDirectory(String path) async {
    calls.add('mkdir $path');
    tree[path] = <RemoteEntry>[];
  }


  // Editor support (ADR-016): stat/read/write over the same maps.
  // Modification times come from a manual clock so tests can
  // simulate a remote change by bumping [mtimeTick].
  int mtimeTick = 1000;

  /// When true, writeBytes throws a permission error (editor
  /// failure-path tests).
  bool failWrites = false;
  final Map<String, int> writeCounts = {};
  final Map<String, List<int>> _written = {};

  @override
  Future<RemoteFileStat> stat(String path) async {
    calls.add('stat $path');
    final bytes = _written[path] ?? files[path] ?? uploaded[path];
    if (bytes != null) {
      return RemoteFileStat(
        size: bytes.length,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          mtimeTick * 1000,
          isUtc: true,
        ),
      );
    }
    if (tree.containsKey(path)) {
      return const RemoteFileStat(isDirectory: true);
    }
    throw const AppError(
      category: AppErrorCategory.remotePathMissing,
      userMessage: 'missing',
    );
  }

  @override
  Future<Uint8List> readBytes(String path, {required int maxBytes}) async {
    calls.add('readBytes $path');
    final bytes = _written[path] ?? files[path];
    if (bytes == null) {
      throw const AppError(
        category: AppErrorCategory.remotePathMissing,
        userMessage: 'missing',
      );
    }
    if (bytes.length > maxBytes) {
      throw const AppError(
        category: AppErrorCategory.unsupportedCapability,
        userMessage: 'too large',
      );
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    calls.add('writeBytes $path');
    if (failWrites) {
      throw AppError(
        category: AppErrorCategory.permissionDenied,
        userMessage: 'Permission denied: $path.',
      );
    }
    writeCounts[path] = (writeCounts[path] ?? 0) + 1;
    uploaded[path] = List.of(bytes);
    _written[path] = List.of(bytes);
    mtimeTick++;
  }

  @override
  Future<UploadHandle> openUpload(String path) async {
    calls.add('openUpload $path');
    var aborted = false;
    return UploadHandle(
      write: (data, onProgress) async {
        final bytes = <int>[];
        await for (final chunk in data) {
          if (aborted) return;
          bytes.addAll(chunk);
          onProgress(bytes.length);
        }
        if (!aborted) uploaded[path] = bytes;
      },
      abort: () async {
        aborted = true;
      },
      close: () async {},
    );
  }

  @override
  Future<DownloadHandle> openDownload(String path) async {
    final bytes = files[path];
    if (bytes == null) {
      throw const AppError(
        category: AppErrorCategory.remotePathMissing,
        userMessage: 'missing',
      );
    }
    return DownloadHandle(
      stream: Stream.value(bytes),
      totalBytes: bytes.length,
      close: () async {},
    );
  }
}

RemoteEntry dir(String name, String path) =>
    RemoteEntry(name: name, path: path, kind: RemoteEntryKind.directory);

RemoteEntry file(String name, String path, {int? size}) =>
    RemoteEntry(name: name, path: path, kind: RemoteEntryKind.file, size: size);

Future<ProviderContainer> makeContainer() async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(explorerProvider);
  return container;
}

Map<String, Object> sampleTree() => <String, Object>{
  '/home/herotest': [
    dir('docs', '/home/herotest/docs'),
    file('a.txt', '/home/herotest/a.txt'),
    file('.hidden', '/home/herotest/.hidden'),
  ],
  '/home/herotest/docs': [file('b.md', '/home/herotest/docs/b.md')],
  '/secret': const AppError(
    category: AppErrorCategory.permissionDenied,
    userMessage: 'Permission denied: /secret.',
  ),
};

void main() {
  group('ExplorerNotifier (Milestone 3)', () {
    test(
      'attach loads the home directory, sorted and hiding dotfiles',
      () async {
        final container = await makeContainer();
        final notifier = container.read(explorerProvider.notifier);
        await notifier.attach(FakeFileService(sampleTree()));
        final state = container.read(explorerProvider);
        expect(state.currentPath, '/home/herotest');
        expect(state.visible.map((e) => e.name), ['docs', 'a.txt']);
      },
    );

    test('showHidden reveals dotfiles', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(FakeFileService(sampleTree()));
      notifier.setShowHidden(true);
      expect(container.read(explorerProvider).visible.map((e) => e.name), [
        'docs',
        '.hidden',
        'a.txt',
      ]);
    });

    test('navigate into a subfolder and follow cwd reports', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(FakeFileService(sampleTree()));
      await notifier.navigateTo('/home/herotest/docs');
      expect(
        container.read(explorerProvider).currentPath,
        '/home/herotest/docs',
      );
      await notifier.onRemoteCwd('/home/herotest');
      expect(container.read(explorerProvider).currentPath, '/home/herotest');
    });

    test(
      'failed navigation keeps the current path and surfaces the error',
      () async {
        final container = await makeContainer();
        final notifier = container.read(explorerProvider.notifier);
        await notifier.attach(FakeFileService(sampleTree()));
        await notifier.navigateTo('/secret');
        final state = container.read(explorerProvider);
        expect(state.currentPath, '/home/herotest');
        expect(state.error?.category, AppErrorCategory.permissionDenied);
        expect(state.entries, isNotEmpty);
      },
    );

    test('followCwd off ignores terminal cwd reports', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(FakeFileService(sampleTree()));
      notifier.setFollowCwd(false);
      await notifier.onRemoteCwd('/home/herotest/docs');
      expect(container.read(explorerProvider).currentPath, '/home/herotest');
    });

    test('startup directory wins over home when provided', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(
        FakeFileService(sampleTree()),
        startupDirectory: '/home/herotest/docs',
      );
      expect(
        container.read(explorerProvider).currentPath,
        '/home/herotest/docs',
      );
    });
  });

  group('ExplorerNotifier path history (path bar)', () {
    test(
      'records visited paths most-recent-first without duplicates',
      () async {
        final container = await makeContainer();
        final notifier = container.read(explorerProvider.notifier);
        await notifier.attach(FakeFileService(sampleTree()));
        await notifier.navigateTo('/home/herotest/docs');
        await notifier.navigateTo('/home/herotest');
        await notifier.navigateTo('/home/herotest/docs');
        expect(container.read(explorerProvider).recentPaths, [
          '/home/herotest/docs',
          '/home/herotest',
        ]);
      },
    );

    test('failed navigation does not enter the history', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(FakeFileService(sampleTree()));
      await notifier.navigateTo('/secret');
      expect(container.read(explorerProvider).recentPaths, ['/home/herotest']);
    });
  });

  group('ExplorerNotifier file actions (Milestone 4)', () {
    test('rename succeeds and refreshes the listing', () async {
      final container = await makeContainer();
      final fake = FakeFileService(sampleTree());
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      final aTxt = container
          .read(explorerProvider)
          .entries
          .firstWhere((e) => e.name == 'a.txt');
      final error = await notifier.renameEntry(aTxt, 'renamed.txt');
      expect(error, isNull);
      expect(
        fake.calls,
        contains(
          'rename /home/herotest/a.txt -> '
          '/home/herotest/renamed.txt',
        ),
      );
      expect(
        container.read(explorerProvider).entries.map((e) => e.name),
        contains('renamed.txt'),
      );
    });

    test('rename colliding with an existing name is refused', () async {
      final container = await makeContainer();
      final fake = FakeFileService(sampleTree());
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      final aTxt = container
          .read(explorerProvider)
          .entries
          .firstWhere((e) => e.name == 'a.txt');
      final error = await notifier.renameEntry(aTxt, 'docs');
      expect(error, contains('already exists'));
      expect(fake.calls.where((c) => c.startsWith('rename')), isEmpty);
    });

    test('rename rejects invalid names before touching the server', () async {
      final container = await makeContainer();
      final fake = FakeFileService(sampleTree());
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      final aTxt = container
          .read(explorerProvider)
          .entries
          .firstWhere((e) => e.name == 'a.txt');
      expect(await notifier.renameEntry(aTxt, 'a/b'), contains('separators'));
      expect(await notifier.renameEntry(aTxt, '..'), isNotNull);
      expect(fake.calls, isEmpty);
    });

    test('delete file uses deleteFile; delete folder is recursive', () async {
      final container = await makeContainer();
      final fake = FakeFileService(sampleTree());
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      final entries = container.read(explorerProvider).entries;
      await notifier.deleteEntry(entries.firstWhere((e) => e.name == 'a.txt'));
      await notifier.deleteEntry(entries.firstWhere((e) => e.name == 'docs'));
      expect(fake.calls, contains('deleteFile /home/herotest/a.txt'));
      expect(fake.calls, contains('deleteRecursively /home/herotest/docs'));
    });

    test('download writes the file and reports a notice', () async {
      final container = await makeContainer();
      final fake = FakeFileService(
        sampleTree(),
        files: {'/home/herotest/a.txt': 'hello-bytes'.codeUnits},
      );
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      final aTxt = container
          .read(explorerProvider)
          .entries
          .firstWhere((e) => e.name == 'a.txt');
      final target =
          '${Directory.systemTemp.path}/heroterm-dl-test-${DateTime.now().microsecondsSinceEpoch}.bin';
      await notifier.downloadEntry(aTxt, target);
      final state = container.read(explorerProvider);
      expect(state.isTransferring, isFalse);
      expect(state.error, isNull);
      expect(state.notice, contains('Downloaded a.txt'));
      expect(await File(target).readAsString(), 'hello-bytes');
      await File(target).delete();
    });

    test('failed download leaves no partial file and sets the error', () async {
      final container = await makeContainer();
      final fake = FakeFileService(sampleTree()); // no file contents
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      final aTxt = container
          .read(explorerProvider)
          .entries
          .firstWhere((e) => e.name == 'a.txt');
      final target =
          '${Directory.systemTemp.path}/heroterm-dl-fail-${DateTime.now().microsecondsSinceEpoch}.bin';
      await notifier.downloadEntry(aTxt, target);
      final state = container.read(explorerProvider);
      expect(state.error, isNotNull);
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('ExplorerNotifier upload (Milestone 5)', () {
    Future<({ProviderContainer c, FakeFileService fake, ExplorerNotifier n})>
    setup() async {
      final container = await makeContainer();
      final fake = FakeFileService(sampleTree());
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(fake);
      return (c: container, fake: fake, n: notifier);
    }

    Future<File> tempFile(String name, String content) async {
      // Unique parent dir so the file itself can keep the exact
      // name the test wants to collide (or not) with.
      final dir = await Directory(
        '${Directory.systemTemp.path}/heroterm-up-'
        '${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final file = File('${dir.path}/$name');
      await file.writeAsString(content);
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      return file;
    }

    test('uploads a dropped file into the current directory', () async {
      final (:c, :fake, :n) = await setup();
      final local = await tempFile('new.txt', 'fresh-bytes');
      var asked = false;
      await n.uploadLocalPaths(
        [local.path],
        askCollision: (name, path) async {
          asked = true;
          return null;
        },
      );
      expect(asked, isFalse);
      expect(fake.uploaded['/home/herotest/new.txt'], 'fresh-bytes'.codeUnits);
      expect(c.read(explorerProvider).notice, contains('Uploaded 1 file'));
    });

    test('collision skip keeps the existing remote file', () async {
      final (:c, :fake, :n) = await setup();
      final local = await tempFile('a.txt', 'replacement');
      await n.uploadLocalPaths(
        [local.path],
        askCollision: (name, path) async =>
            (choice: CollisionChoice.skip, applyToAll: false),
      );
      expect(fake.uploaded, isEmpty);
      expect(c.read(explorerProvider).notice, contains('skipped'));
    });

    test('collision rename uploads under a numbered name', () async {
      final (:fake, :n, c: _) = await setup();
      final local = await tempFile('a.txt', 'second-copy');
      await n.uploadLocalPaths(
        [local.path],
        askCollision: (name, path) async =>
            (choice: CollisionChoice.rename, applyToAll: false),
      );
      expect(
        fake.uploaded['/home/herotest/a (1).txt'],
        'second-copy'.codeUnits,
      );
    });

    test('collision overwrite replaces the remote bytes', () async {
      final (:fake, :n, c: _) = await setup();
      final local = await tempFile('a.txt', 'overwritten');
      await n.uploadLocalPaths(
        [local.path],
        askCollision: (name, path) async =>
            (choice: CollisionChoice.overwrite, applyToAll: false),
      );
      expect(fake.uploaded['/home/herotest/a.txt'], 'overwritten'.codeUnits);
    });

    test('cancelling at the collision prompt aborts the batch', () async {
      final (:c, :fake, :n) = await setup();
      final local = await tempFile('a.txt', 'never-sent');
      await n.uploadLocalPaths([
        local.path,
      ], askCollision: (name, path) async => null);
      expect(fake.uploaded, isEmpty);
      expect(c.read(explorerProvider).notice, contains('Upload cancelled'));
    });

    test('an unreadable dropped path surfaces a permission error', () async {
      final (:c, :fake, :n) = await setup();
      await n.uploadLocalPaths([
        '/definitely/not/here/ghost.txt',
      ], askCollision: (name, path) async => null);
      final state = c.read(explorerProvider);
      expect(state.error?.category, AppErrorCategory.permissionDenied);
      expect(state.error?.userMessage, contains('ghost.txt'));
      expect(fake.uploaded, isEmpty);
    });

    test('dropping a folder uploads it recursively with mkdirs', () async {
      final (:fake, :n, c: _) = await setup();
      final dir = await Directory(
        '${Directory.systemTemp.path}/heroterm-drop-'
        '${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      await Directory('${dir.path}/sub').create();
      await File('${dir.path}/top.txt').writeAsString('top');
      await File('${dir.path}/sub/deep.txt').writeAsString('deep');
      await n.uploadLocalPaths([
        dir.path,
      ], askCollision: (name, path) async => null);
      final rootName = dir.path.split('/').last;
      expect(fake.calls, contains('mkdir /home/herotest/$rootName/sub'));
      expect(
        fake.uploaded['/home/herotest/$rootName/top.txt'],
        'top'.codeUnits,
      );
      expect(
        fake.uploaded['/home/herotest/$rootName/sub/deep.txt'],
        'deep'.codeUnits,
      );
    });
  });

  group('ExplorerNotifier table view (sort + owner labels)', () {
    Map<String, Object> tableTree() => <String, Object>{
      '/home/herotest': [
        dir('docs', '/home/herotest/docs'),
        RemoteEntry(
          name: 'big.bin',
          path: '/home/herotest/big.bin',
          kind: RemoteEntryKind.file,
          size: 3000,
          uid: 1000,
          gid: 1000,
        ),
        RemoteEntry(
          name: 'small.txt',
          path: '/home/herotest/small.txt',
          kind: RemoteEntryKind.file,
          size: 500,
          uid: 0,
          gid: 0,
        ),
      ],
    };

    test('setSort by size orders numerically, folders always first; '
        'clicking again reverses within groups', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(FakeFileService(tableTree()));

      notifier.setSort(ExplorerSortColumn.size);
      var state = container.read(explorerProvider);
      expect(state.sortColumn, ExplorerSortColumn.size);
      expect(state.sortAscending, isTrue);
      expect(state.visible.map((e) => e.name), [
        'docs',
        'small.txt',
        'big.bin',
      ]);

      notifier.setSort(ExplorerSortColumn.size);
      state = container.read(explorerProvider);
      expect(state.sortAscending, isFalse);
      expect(state.visible.map((e) => e.name), [
        'docs',
        'big.bin',
        'small.txt',
      ]);
    });

    test('owner labels resolve from fetched id names, with numeric '
        'fallback for unknown IDs', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(
        FakeFileService(tableTree()),
        fetchIdNames: () async =>
            (users: {1000: 'deploy'}, groups: {1000: 'devs'}),
      );
      await Future<void>.delayed(Duration.zero);
      final state = container.read(explorerProvider);
      final big = state.entries.singleWhere((e) => e.name == 'big.bin');
      final small = state.entries.singleWhere((e) => e.name == 'small.txt');
      expect(state.ownerLabelOf(big), 'deploy');
      expect(state.groupLabelOf(big), 'devs');
      // uid 0 was not in the fetched map: numeric fallback, no guess.
      expect(state.ownerLabelOf(small), '0');
    });

    test('selection is tracked and cleared when the folder changes', () async {
      final container = await makeContainer();
      final notifier = container.read(explorerProvider.notifier);
      await notifier.attach(FakeFileService(tableTree()));
      notifier.selectEntry('/home/herotest/big.bin');
      expect(
        container.read(explorerProvider).selectedPath,
        '/home/herotest/big.bin',
      );
      await notifier.refresh();
      expect(container.read(explorerProvider).selectedPath, isNull);
    });
  });
}
