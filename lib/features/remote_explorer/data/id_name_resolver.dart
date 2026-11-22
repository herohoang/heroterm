/// Resolves numeric owner/group IDs from SFTP attributes to account
/// names, best-effort (table-view spec: "Username hoặc UID nếu server
/// không phân giải được tên").
///
/// SFTP itself carries only numeric UID/GID. Names come from one
/// read-only exec of the server's account databases (`/etc/passwd`,
/// `/etc/group`) per connection. Any failure — exec restricted,
/// files unreadable, odd formats — resolves to no names and the UI
/// falls back to the numeric IDs. Nothing is ever guessed: an ID
/// with no matching account line stays numeric.
typedef IdNameMaps = ({Map<int, String> users, Map<int, String> groups});

const _fetchCommand =
    "cat /etc/passwd; printf '\\n__HT_GROUPS__\\n'; cat /etc/group";

/// Fetches and parses both account databases with a single command.
/// Returns null when the command fails or yields nothing usable.
Future<IdNameMaps?> fetchIdNames(
  Future<String> Function(String command) runCommand,
) async {
  try {
    final output = await runCommand(_fetchCommand)
        .timeout(const Duration(seconds: 10));
    final marker = output.indexOf('__HT_GROUPS__');
    if (marker < 0) return null;
    final users = parsePasswdUsers(output.substring(0, marker));
    final groups = parseGroupNames(
      output.substring(marker + '__HT_GROUPS__'.length),
    );
    if (users.isEmpty && groups.isEmpty) return null;
    return (users: users, groups: groups);
  } catch (_) {
    return null;
  }
}

/// Parses `/etc/passwd` content (`name:x:uid:gid:...` per line).
Map<int, String> parsePasswdUsers(String content) {
  final result = <int, String>{};
  for (final line in content.split('\n')) {
    final fields = line.split(':');
    if (fields.length < 4) continue;
    final uid = int.tryParse(fields[2].trim());
    final name = fields[0].trim();
    if (uid != null && name.isNotEmpty) result[uid] = name;
  }
  return result;
}

/// Parses `/etc/group` content (`name:x:gid:members` per line).
Map<int, String> parseGroupNames(String content) {
  final result = <int, String>{};
  for (final line in content.split('\n')) {
    final fields = line.split(':');
    if (fields.length < 3) continue;
    final gid = int.tryParse(fields[2].trim());
    final name = fields[0].trim();
    if (gid != null && name.isNotEmpty) result[gid] = name;
  }
  return result;
}
