enum RemoteEntryKind { directory, file, symlink, other }

/// One row of a remote directory listing (FEATURE_SPEC section 6).
final class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.kind,
    this.size,
    this.modifiedAt,
    this.permissions,
    this.linkTarget,
    this.targetIsDirectory = false,
    this.uid,
    this.gid,
    this.modeValue,
  });

  final String name;

  /// Absolute remote POSIX path.
  final String path;
  final RemoteEntryKind kind;

  /// Byte size for files; null when the server did not report one.
  final int? size;

  final DateTime? modifiedAt;

  /// Permission string in `rwxr-xr-x` form, when available.
  final String? permissions;

  /// For symlinks, the resolved target path when it could be read.
  final String? linkTarget;

  /// For symlinks: whether the link target is a directory, resolved
  /// through stat when the listing was built. The explorer treats
  /// such links as navigable.
  final bool targetIsDirectory;

  /// Numeric owner user ID from SFTP attributes, when reported.
  /// SFTP carries IDs, not names — name resolution is a separate
  /// best-effort layer (see the explorer's id-name resolver).
  final int? uid;

  /// Numeric owning group ID from SFTP attributes, when reported.
  final int? gid;

  /// Raw mode value from SFTP attributes (file-type bits plus
  /// permission bits), when reported.
  final int? modeValue;

  /// Permission bits only (`mode & 0o7777`), the normalized value
  /// used for display (octal) and sorting.
  int? get permissionBits => modeValue == null ? null : modeValue! & 0xFFF;

  /// Full `ls`-style permission string, e.g. `drwxr-xr-x`,
  /// `-rw-r--r--`, `lrwxrwxrwx`. Null when no permissions reported.
  String? get permissionString {
    final perms = permissions;
    if (perms == null) return null;
    final prefix = switch (kind) {
      RemoteEntryKind.directory => 'd',
      RemoteEntryKind.symlink => 'l',
      RemoteEntryKind.file => '-',
      RemoteEntryKind.other => '?',
    };
    return '$prefix$perms';
  }

  bool get isDirectory => kind == RemoteEntryKind.directory;
  bool get isHidden => name.startsWith('.');

  bool get isNavigable =>
      isDirectory || (kind == RemoteEntryKind.symlink && targetIsDirectory);
}

/// Directories first, then files, each group ordered by name
/// (case-insensitive). Symlinks sort with the group of their target
/// when resolved, otherwise with files.
int compareRemoteEntries(RemoteEntry a, RemoteEntry b) {
  final ad = isDirLike(a);
  final bd = isDirLike(b);
  if (ad != bd) return ad ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

List<RemoteEntry> visibleEntries(
  List<RemoteEntry> entries, {
  required bool showHidden,
}) {
  final filtered = entries.where((e) => showHidden || !e.isHidden).toList();
  filtered.sort(compareRemoteEntries);
  return filtered;
}

/// Columns the explorer table can sort by (table-view spec).
enum ExplorerSortColumn { name, size, modified, owner, group, permission }

/// Whether [entry] groups with directories for folders-first
/// ordering (a symlink to a directory counts as a directory).
bool isDirLike(RemoteEntry entry) =>
    entry.isDirectory ||
    (entry.kind == RemoteEntryKind.symlink && entry.targetIsDirectory);

/// Sorts [entries] for the table view.
///
/// Policy (uniform for every column, per spec): directories first,
/// then the column comparison within each group; [ascending] flips
/// the column comparison only, never the folders-first grouping.
/// Name compares case-insensitively; size/modified compare the real
/// values (missing values sort as smallest); owner/group compare
/// the labels from [ownerLabel]/[groupLabel] (which already encode
/// the name-or-ID fallback); permission compares the normalized
/// permission bits. The sort is stable: equal keys keep their
/// incoming order (Dart's [List.sort] is not stable, so the
/// original index breaks ties).
List<RemoteEntry> sortEntries(
  List<RemoteEntry> entries, {
  required ExplorerSortColumn column,
  required bool ascending,
  String Function(RemoteEntry entry)? ownerLabel,
  String Function(RemoteEntry entry)? groupLabel,
}) {
  String ownerOf(RemoteEntry e) =>
      ownerLabel?.call(e) ?? (e.uid?.toString() ?? '');
  String groupOf(RemoteEntry e) =>
      groupLabel?.call(e) ?? (e.gid?.toString() ?? '');

  int keyCompare(RemoteEntry a, RemoteEntry b) {
    return switch (column) {
      ExplorerSortColumn.name => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      ExplorerSortColumn.size => (a.size ?? -1).compareTo(b.size ?? -1),
      ExplorerSortColumn.modified => (a.modifiedAt ?? _epoch).compareTo(
        b.modifiedAt ?? _epoch,
      ),
      ExplorerSortColumn.owner => ownerOf(
        a,
      ).toLowerCase().compareTo(ownerOf(b).toLowerCase()),
      ExplorerSortColumn.group => groupOf(
        a,
      ).toLowerCase().compareTo(groupOf(b).toLowerCase()),
      ExplorerSortColumn.permission => (a.permissionBits ?? -1).compareTo(
        b.permissionBits ?? -1,
      ),
    };
  }

  final decorated = [
    for (var i = 0; i < entries.length; i++) (index: i, entry: entries[i]),
  ];
  decorated.sort((x, y) {
    final aDir = isDirLike(x.entry);
    final bDir = isDirLike(y.entry);
    if (aDir != bDir) return aDir ? -1 : 1;
    var result = keyCompare(x.entry, y.entry);
    if (!ascending) result = -result;
    if (result != 0) return result;
    return x.index.compareTo(y.index);
  });
  return [for (final item in decorated) item.entry];
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Human-readable byte size for the explorer's metadata line.
String formatRemoteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
