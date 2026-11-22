enum AuthMethod { password, privateKey }

/// Outcome of the most recent connection attempt (no sensitive
/// detail is stored, only the outcome).
enum LastConnectionStatus { success, failed }

/// Non-secret SSH session metadata (ARCHITECTURE data model).
///
/// Secrets are never part of this model: [credentialRef] is only an
/// opaque id into the credential store (macOS Keychain). A private key
/// is referenced by its file path ([privateKeyPath]); the key file is
/// never copied or imported by the app (ADR-006). Its passphrase, when
/// the user provides one, is stored in the credential store under
/// [credentialRef] just like a password.
final class SshSession {
  const SshSession({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    this.port = 22,
    this.authMethod = AuthMethod.password,
    this.credentialRef,
    this.privateKeyPath,
    this.groupId,
    this.description = '',
    this.labelIds = const [],
    this.icon,
    this.colorValue,
    this.connectionTimeout = const Duration(seconds: 15),
    this.startupDirectory,
    required this.createdAt,
    required this.updatedAt,
    this.lastConnectedAt,
    this.lastConnectionStatus,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final String? credentialRef;
  final String? privateKeyPath;
  final String? groupId;

  /// Free-text note, at most 500 characters.
  final String description;

  /// IDs of the user labels attached to this profile (ADR-013 —
  /// labels replaced the fixed environment list and free-form
  /// tags). Order is display order.
  final List<String> labelIds;

  /// Appearance: a curated icon ID (see session_appearance.dart)
  /// and an ARGB colour; both optional.
  final String? icon;
  final int? colorValue;
  final Duration connectionTimeout;
  final String? startupDirectory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastConnectedAt;
  final LastConnectionStatus? lastConnectionStatus;

  SshSession copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    AuthMethod? authMethod,
    String? credentialRef,
    bool clearCredentialRef = false,
    String? privateKeyPath,
    bool clearPrivateKeyPath = false,
    String? groupId,
    bool clearGroupId = false,
    String? description,
    List<String>? labelIds,
    String? icon,
    bool clearIcon = false,
    int? colorValue,
    bool clearColor = false,
    Duration? connectionTimeout,
    String? startupDirectory,
    bool clearStartupDirectory = false,
    DateTime? updatedAt,
    DateTime? lastConnectedAt,
    LastConnectionStatus? lastConnectionStatus,
  }) {
    return SshSession(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      credentialRef: clearCredentialRef
          ? null
          : (credentialRef ?? this.credentialRef),
      privateKeyPath: clearPrivateKeyPath
          ? null
          : (privateKeyPath ?? this.privateKeyPath),
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      description: description ?? this.description,
      labelIds: labelIds ?? this.labelIds,
      icon: clearIcon ? null : (icon ?? this.icon),
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      startupDirectory: clearStartupDirectory
          ? null
          : (startupDirectory ?? this.startupDirectory),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      lastConnectionStatus: lastConnectionStatus ?? this.lastConnectionStatus,
    );
  }

  /// Per-field validation problems keyed by field name; an empty map
  /// means the profile is valid. Used by the editor to show errors
  /// next to each input, and by [validate] for whole-profile checks.
  /// (TEST_PLAN: session profile validation.)
  Map<String, String> validateFields() {
    final errors = <String, String>{};

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      errors['name'] = 'Name is required.';
    } else if (trimmedName.length > 100) {
      errors['name'] = 'Name must be at most 100 characters.';
    } else if (trimmedName.contains('\n')) {
      errors['name'] = 'Name must be a single line.';
    }

    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) {
      errors['host'] = 'Host is required.';
    } else if (!isValidHost(trimmedHost)) {
      errors['host'] =
          'Enter a valid hostname (e.g. vps.example.com), IPv4 address '
          '(e.g. 192.168.1.10), or IPv6 address.';
    }

    if (port < 1 || port > 65535) {
      errors['port'] = 'Port must be a number between 1 and 65535.';
    }

    final trimmedUser = username.trim();
    if (trimmedUser.isEmpty) {
      errors['username'] = 'Username is required.';
    } else if (RegExp(r'\s').hasMatch(trimmedUser)) {
      errors['username'] = 'Username must not contain spaces.';
    } else if (!RegExp(r'^[A-Za-z0-9._@\\-]+$').hasMatch(trimmedUser)) {
      errors['username'] =
          'Username may only contain letters, digits, . _ - @ and \\.';
    } else if (trimmedUser.length > 128) {
      errors['username'] = 'Username is too long.';
    }

    if (connectionTimeout <= Duration.zero ||
        connectionTimeout > const Duration(seconds: 120)) {
      errors['timeout'] = 'Timeout must be between 1 and 120 seconds.';
    }

    if (description.length > 500) {
      errors['description'] = 'Description must be at most 500 characters.';
    }

    if (authMethod == AuthMethod.privateKey) {
      final path = privateKeyPath?.trim() ?? '';
      if (path.isEmpty) {
        errors['keyPath'] =
            'A private key path is required for key authentication.';
      } else if (!path.startsWith('/') && !path.startsWith('~/')) {
        errors['keyPath'] =
            'Private key path must be absolute (start with / or ~/).';
      } else if (path.endsWith('/')) {
        errors['keyPath'] = 'Private key path must point to a file.';
      }
    }

    final dir = startupDirectory?.trim() ?? '';
    if (dir.isNotEmpty && !dir.startsWith('/') && !dir.startsWith('~/')) {
      errors['startupDirectory'] =
          'Startup directory must be an absolute path (start with /).';
    }

    return errors;
  }

  /// Returns a list of validation problems; empty means valid.
  List<String> validate() => validateFields().values.toList();

  /// Strict host validation: a DNS hostname, an IPv4 address, or an
  /// IPv6 address. A digits-and-dots value is treated as an IPv4
  /// address and must be a complete, valid one — a bare number such
  /// as "123" is rejected, as are hostnames with empty labels,
  /// leading/trailing hyphens, underscores, or an all-numeric final
  /// label.
  static bool isValidHost(String value) {
    final h = value;
    if (h.isEmpty || h.length > 253) return false;
    if (h.contains(':')) return _isValidIpv6(h);
    if (RegExp(r'^[0-9.]+$').hasMatch(h)) return _isValidIpv4(h);
    final labels = h.split('.');
    final labelPattern = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$');
    for (final label in labels) {
      if (label.isEmpty || label.length > 63) return false;
      if (!labelPattern.hasMatch(label)) return false;
    }
    // An all-numeric final label means it is a malformed IP, not a name.
    if (RegExp(r'^[0-9]+$').hasMatch(labels.last)) return false;
    return true;
  }

  static bool _isValidIpv4(String h) {
    final parts = h.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
      // Reject leading zeros ("010") and stray characters.
      if (part != n.toString()) return false;
    }
    return true;
  }

  static bool _isValidIpv6(String h) {
    var input = h;
    // An embedded IPv4 tail counts as two groups: validate it, then
    // replace it with two dummy hex groups and validate the rest.
    var extraGroups = 0;
    if (input.contains('.')) {
      final lastColon = input.lastIndexOf(':');
      if (lastColon < 0) return false;
      if (!_isValidIpv4(input.substring(lastColon + 1))) return false;
      input = '${input.substring(0, lastColon + 1)}0:0';
    }
    final halves = input.split('::');
    if (halves.length > 2) return false;
    final groupPattern = RegExp(r'^[0-9A-Fa-f]{1,4}$');
    int countGroups(String part) {
      if (part.isEmpty) return 0;
      final groups = part.split(':');
      for (final g in groups) {
        if (!groupPattern.hasMatch(g)) return -1;
      }
      return groups.length;
    }

    if (halves.length == 2) {
      final left = countGroups(halves[0]);
      final right = countGroups(halves[1]);
      if (left < 0 || right < 0) return false;
      return left + right + extraGroups < 8;
    }
    final only = countGroups(input);
    return only >= 0 && only + extraGroups == 8;
  }

  bool get isValid => validate().isEmpty;

  /// Case-insensitive substring search across the profile's text
  /// fields: name, host, username, description, and — when the
  /// caller supplies them — the group/folder name and the names of
  /// the profile's labels.
  bool matchesQuery(
    String query, {
    String? groupName,
    Iterable<String> labelNames = const [],
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        host.toLowerCase().contains(q) ||
        username.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        labelNames.any((t) => t.toLowerCase().contains(q)) ||
        (groupName?.toLowerCase().contains(q) ?? false);
  }

  /// Serializes metadata only. There is deliberately no secret field:
  /// secrets live in the credential store, referenced by [credentialRef].
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'authMethod': authMethod.name,
    'credentialRef': credentialRef,
    'privateKeyPath': privateKeyPath,
    'groupId': groupId,
    'description': description,
    'labelIds': labelIds,
    'icon': icon,
    'colorValue': colorValue,
    'connectionTimeoutSeconds': connectionTimeout.inSeconds,
    'startupDirectory': startupDirectory,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastConnectedAt': lastConnectedAt?.toIso8601String(),
    'lastConnectionStatus': lastConnectionStatus?.name,
  };

  factory SshSession.fromJson(Map<String, Object?> json) {
    DateTime? parseNullable(Object? v) =>
        v is String ? DateTime.tryParse(v) : null;
    T? enumByName<T extends Enum>(List<T> values, Object? raw) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return null;
    }

    return SshSession(
      id: json['id']! as String,
      name: json['name']! as String,
      host: json['host']! as String,
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username']! as String,
      authMethod: AuthMethod.values.byName(
        (json['authMethod'] as String?) ?? 'password',
      ),
      credentialRef: json['credentialRef'] as String?,
      privateKeyPath: json['privateKeyPath'] as String?,
      groupId: json['groupId'] as String?,
      description: (json['description'] as String?) ?? '',
      // Label/appearance fields (ADR-013) default gracefully for
      // libraries saved before they existed; the legacy
      // environment/tags values are migrated to labels by the
      // repository, not here.
      labelIds: [
        for (final t in (json['labelIds'] as List<Object?>? ?? const []))
          if (t is String) t,
      ],
      icon: json['icon'] as String?,
      colorValue: (json['colorValue'] as num?)?.toInt(),
      connectionTimeout: Duration(
        seconds: (json['connectionTimeoutSeconds'] as num?)?.toInt() ?? 15,
      ),
      startupDirectory: json['startupDirectory'] as String?,
      createdAt: parseNullable(json['createdAt']) ?? DateTime.utc(1970),
      updatedAt: parseNullable(json['updatedAt']) ?? DateTime.utc(1970),
      lastConnectedAt: parseNullable(json['lastConnectedAt']),
      lastConnectionStatus: enumByName(
        LastConnectionStatus.values,
        json['lastConnectionStatus'],
      ),
    );
  }
}
