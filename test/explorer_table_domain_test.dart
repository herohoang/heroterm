import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/app/ui_preferences.dart';
import 'package:heroterm/features/remote_explorer/data/id_name_resolver.dart';
import 'package:heroterm/features/remote_explorer/domain/remote_entry.dart';

RemoteEntry entry(
  String name, {
  RemoteEntryKind kind = RemoteEntryKind.file,
  int? size,
  DateTime? modifiedAt,
  int? uid,
  int? gid,
  int? modeValue,
  String? permissions,
}) {
  return RemoteEntry(
    name: name,
    path: '/srv/$name',
    kind: kind,
    size: size,
    modifiedAt: modifiedAt,
    uid: uid,
    gid: gid,
    modeValue: modeValue,
    permissions: permissions,
  );
}

List<String> names(List<RemoteEntry> entries) => [
  for (final e in entries) e.name,
];

void main() {
  group('sortEntries (table-view spec)', () {
    final files = [
      entry('banana.txt', size: 200),
      entry('Apple.txt', size: 50),
      entry('cherry.txt', size: 100),
      entry('zdir', kind: RemoteEntryKind.directory),
      entry('adir', kind: RemoteEntryKind.directory),
    ];

    test('name sort is case-insensitive, folders first', () {
      final sorted = sortEntries(
        files,
        column: ExplorerSortColumn.name,
        ascending: true,
      );
      expect(names(sorted), [
        'adir',
        'zdir',
        'Apple.txt',
        'banana.txt',
        'cherry.txt',
      ]);
    });

    test('descending reverses within groups, folders stay first', () {
      final sorted = sortEntries(
        files,
        column: ExplorerSortColumn.name,
        ascending: false,
      );
      expect(names(sorted), [
        'zdir',
        'adir',
        'cherry.txt',
        'banana.txt',
        'Apple.txt',
      ]);
    });

    test('size sort compares real numbers, not display strings', () {
      final sorted = sortEntries(
        files,
        column: ExplorerSortColumn.size,
        ascending: true,
      );
      // Folders (no size) tie and keep their incoming relative
      // order — the sort is stable.
      expect(names(sorted), [
        'zdir',
        'adir',
        'Apple.txt',
        'cherry.txt',
        'banana.txt',
      ]);
    });

    test('modified sort compares timestamps; missing is smallest', () {
      final sorted = sortEntries(
        [
          entry('new.txt', modifiedAt: DateTime.utc(2026, 5)),
          entry('old.txt', modifiedAt: DateTime.utc(2024, 5)),
          entry('nodate.txt'),
        ],
        column: ExplorerSortColumn.modified,
        ascending: true,
      );
      expect(names(sorted), ['nodate.txt', 'old.txt', 'new.txt']);
    });

    test('permission sort uses normalized bits', () {
      final sorted = sortEntries(
        [
          entry('a', modeValue: int.parse('100755', radix: 8)),
          entry('b', modeValue: int.parse('100644', radix: 8)),
          entry('c', modeValue: int.parse('100600', radix: 8)),
        ],
        column: ExplorerSortColumn.permission,
        ascending: true,
      );
      expect(names(sorted), ['c', 'b', 'a']);
    });

    test('owner sort uses labels (name when resolved, else the ID)', () {
      final sorted = sortEntries(
        [entry('x', uid: 1000), entry('y', uid: 0), entry('z', uid: 999)],
        column: ExplorerSortColumn.owner,
        ascending: true,
        ownerLabel: (e) => e.uid == 1000 ? 'deploy' : '${e.uid}',
      );
      // '0' < '999' < 'deploy' as label strings.
      expect(names(sorted), ['y', 'z', 'x']);
    });

    test('sort is stable for equal keys', () {
      final input = [
        entry('one', size: 10),
        entry('two', size: 10),
        entry('three', size: 10),
      ];
      final sorted = sortEntries(
        input,
        column: ExplorerSortColumn.size,
        ascending: false,
      );
      expect(names(sorted), ['one', 'two', 'three']);
    });
  });

  group('RemoteEntry permission display', () {
    test('permissionString prefixes by kind; bits mask the type', () {
      final dir = entry(
        'd',
        kind: RemoteEntryKind.directory,
        modeValue: int.parse('40755', radix: 8),
        permissions: 'rwxr-xr-x',
      );
      expect(dir.permissionString, 'drwxr-xr-x');
      expect(dir.permissionBits, int.parse('755', radix: 8));
      final file = entry(
        'f',
        modeValue: int.parse('100644', radix: 8),
        permissions: 'rw-r--r--',
      );
      expect(file.permissionString, '-rw-r--r--');
      expect(file.permissionBits, int.parse('644', radix: 8));
      expect(entry('g').permissionString, isNull);
    });
  });

  group('id-name parsers', () {
    test('parsePasswdUsers maps uid to name and skips junk', () {
      final users = parsePasswdUsers(
        'root:x:0:0:root:/root:/bin/bash\n'
        'deploy:x:1000:1000:Deploy:/home/deploy:/bin/bash\n'
        'broken-line\n'
        'nobody:x:65534:65534::/nonexistent:/usr/sbin/nologin\n',
      );
      expect(users, {0: 'root', 1000: 'deploy', 65534: 'nobody'});
    });

    test('parseGroupNames maps gid to name', () {
      final groups = parseGroupNames('root:x:0:\ndevs:x:1000:deploy\nbad\n');
      expect(groups, {0: 'root', 1000: 'devs'});
    });

    test('fetchIdNames returns null when the command fails', () async {
      final result = await fetchIdNames((_) async => throw StateError('no'));
      expect(result, isNull);
    });

    test('fetchIdNames splits the two databases on the marker', () async {
      final result = await fetchIdNames(
        (_) async =>
            'root:x:0:0::/root:/bin/bash\n'
            '__HT_GROUPS__\n'
            'wheel:x:10:root\n',
      );
      expect(result, isNotNull);
      expect(result!.users, {0: 'root'});
      expect(result.groups, {10: 'wheel'});
    });
  });

  group('UiPreferences', () {
    test('JSON round-trip preserves widths', () {
      const prefs = UiPreferences(
        sidebarWidth: 500,
        columnWidths: {ExplorerSortColumn.name: 260},
      );
      final restored = UiPreferences.fromJson(prefs.toJson());
      expect(restored.sidebarWidth, 500);
      expect(restored.columnWidth(ExplorerSortColumn.name), 260);
      // Untouched columns fall back to their defaults.
      expect(
        restored.columnWidth(ExplorerSortColumn.size),
        explorerColumnSpecs[ExplorerSortColumn.size]!.defaultWidth,
      );
    });

    test('out-of-range values are clamped on load', () {
      final restored = UiPreferences.fromJson({
        'sidebarWidth': 5000,
        'columnWidths': {'name': 10},
      });
      expect(restored.sidebarWidth, UiPreferences.maxSidebarWidth);
      expect(
        restored.columnWidth(ExplorerSortColumn.name),
        explorerColumnSpecs[ExplorerSortColumn.name]!.minWidth,
      );
    });
  });
}
