import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_entry.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_path.dart';

RemoteEntry entry(
  String name,
  RemoteEntryKind kind, {
  bool targetIsDirectory = false,
}) {
  return RemoteEntry(
    name: name,
    path: '/x/$name',
    kind: kind,
    targetIsDirectory: targetIsDirectory,
  );
}

void main() {
  group('entry ordering and filtering', () {
    test('directories first, then files, case-insensitive by name', () {
      final entries = [
        entry('banana.txt', RemoteEntryKind.file),
        entry('Zoo', RemoteEntryKind.directory),
        entry('apple.txt', RemoteEntryKind.file),
        entry('Docs', RemoteEntryKind.directory),
      ];
      final visible = visibleEntries(entries, showHidden: true);
      expect(visible.map((e) => e.name), [
        'Docs',
        'Zoo',
        'apple.txt',
        'banana.txt',
      ]);
    });

    test('symlink to a directory sorts and navigates as a directory', () {
      final link = entry(
        'alink',
        RemoteEntryKind.symlink,
        targetIsDirectory: true,
      );
      expect(link.isNavigable, isTrue);
      final visible = visibleEntries([
        entry('m.txt', RemoteEntryKind.file),
        link,
      ], showHidden: true);
      expect(visible.first.name, 'alink');
    });

    test('hidden files are filtered unless requested', () {
      final entries = [
        entry('.env', RemoteEntryKind.file),
        entry('a.txt', RemoteEntryKind.file),
      ];
      expect(visibleEntries(entries, showHidden: false).length, 1);
      expect(visibleEntries(entries, showHidden: true).length, 2);
    });
  });

  group('RemotePath.parseOsc7', () {
    test('decodes a plain file URL', () {
      expect(
        RemotePath.parseOsc7('file://server/home/herotest/docs'),
        '/home/herotest/docs',
      );
    });

    test('percent-decodes spaces and unicode escapes', () {
      expect(
        RemotePath.parseOsc7('file:///home/herotest/my%20dir'),
        '/home/herotest/my dir',
      );
    });

    test('rejects non-file payloads', () {
      expect(RemotePath.parseOsc7('https://example.com/x'), isNull);
      expect(RemotePath.parseOsc7('file://host-only'), isNull);
      expect(RemotePath.parseOsc7(''), isNull);
    });
  });

  group('formatRemoteSize', () {
    test('formats bytes through TB', () {
      expect(formatRemoteSize(0), '0 B');
      expect(formatRemoteSize(1023), '1023 B');
      expect(formatRemoteSize(1024), '1.0 KB');
      expect(formatRemoteSize(1536), '1.5 KB');
      expect(formatRemoteSize(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
