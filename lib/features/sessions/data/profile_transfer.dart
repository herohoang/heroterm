import 'dart:convert';

import '../domain/session_folder.dart';
import '../domain/session_label.dart';
import '../domain/ssh_session.dart';

/// Import/Export of SSH profiles as versioned JSON (profile spec
/// 6.5). The format is a SECURITY boundary:
///
/// * Export never contains secrets: no passwords, no passphrases,
///   no private-key contents, and not even the opaque Keychain
///   reference IDs.
/// * Import treats the file as untrusted input: strict schema and
///   type validation, size/count limits, enum and range checks.
///   Malformed input is rejected whole, with a readable reason;
///   no profile is ever auto-connected by an import.
abstract final class ProfileTransfer {
  static const schemaVersion = 1;
  static const maxImportBytes = 2 * 1024 * 1024;
  static const maxImportProfiles = 500;

  /// Serializes [profiles] to the export format. [foldersById]
  /// resolves each profile's group into its portable `{name, type}`
  /// form; [labelsById] resolves label IDs to portable names
  /// (ADR-013: labels travel by name, like groups).
  static String exportJson({
    required List<SshSession> profiles,
    required Map<String, SessionFolder> foldersById,
    required Map<String, SessionLabel> labelsById,
    required DateTime exportedAt,
  }) {
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'profiles': [
        for (final p in profiles)
          <String, Object?>{
            'name': p.name,
            'host': p.host,
            'port': p.port,
            'username': p.username,
            'authMethod': p.authMethod.name,
            'identityFilePath': p.privateKeyPath,
            'group': p.groupId == null
                ? null
                : <String, Object?>{
                    'name': foldersById[p.groupId!]?.name ?? '',
                    'type':
                        foldersById[p.groupId!]?.type.name ??
                        FolderType.custom.name,
                  },
            'connectionTimeoutSeconds': p.connectionTimeout.inSeconds,
            'description': p.description,
            'labels': [
              for (final id in p.labelIds)
                if (labelsById[id] != null) labelsById[id]!.name,
            ],
            'icon': p.icon,
            'colorValue': p.colorValue,
            'startupDirectory': p.startupDirectory,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Parses and strictly validates an import file. Throws
  /// [ProfileImportException] with a user-readable reason on any
  /// problem; nothing is returned partially.
  static List<ImportedProfile> parseImport(String content) {
    if (content.length > maxImportBytes) {
      throw const ProfileImportException(
        'The file is too large to be a profile export.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw const ProfileImportException('The file is not valid JSON.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const ProfileImportException(
        'The file does not contain a profile export object.',
      );
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw ProfileImportException(
        'Unsupported schema version: ${decoded['schemaVersion']} '
        '(expected $schemaVersion).',
      );
    }
    final rawProfiles = decoded['profiles'];
    if (rawProfiles is! List) {
      throw const ProfileImportException('The export has no "profiles" list.');
    }
    if (rawProfiles.length > maxImportProfiles) {
      throw const ProfileImportException(
        'The file contains too many profiles.',
      );
    }
    return [
      for (var i = 0; i < rawProfiles.length; i++)
        _parseProfile(rawProfiles[i], i),
    ];
  }

  static ImportedProfile _parseProfile(Object? raw, int index) {
    Never fail(String reason) =>
        throw ProfileImportException('Profile ${index + 1}: $reason');
    if (raw is! Map<String, Object?>) fail('is not an object.');

    String reqString(String key) {
      final v = raw[key];
      if (v is! String || v.trim().isEmpty) fail('"$key" is missing.');
      return v.trim();
    }

    int reqIntInRange(String key, int min, int max, {int? fallback}) {
      final v = raw[key];
      if (v == null && fallback != null) return fallback;
      if (v is! num || v != v.roundToDouble()) {
        fail('"$key" must be a whole number.');
      }
      final n = v.toInt();
      if (n < min || n > max) fail('"$key" must be between $min and $max.');
      return n;
    }

    T reqEnum<T extends Enum>(String key, List<T> values, {T? fallback}) {
      final v = raw[key];
      if (v == null && fallback != null) return fallback;
      for (final e in values) {
        if (e.name == v) return e;
      }
      fail('"$key" has an unsupported value: $v');
    }

    final name = reqString('name');
    if (name.length > 100) fail('"name" is too long.');
    final host = reqString('host');
    if (!SshSession.isValidHost(host)) fail('"host" is not a valid host.');
    final username = reqString('username');
    if (RegExp(r'\s').hasMatch(username) || username.length > 128) {
      fail('"username" is invalid.');
    }
    final port = reqIntInRange('port', 1, 65535, fallback: 22);
    final authMethod = reqEnum(
      'authMethod',
      AuthMethod.values,
      fallback: AuthMethod.password,
    );
    final timeout = reqIntInRange(
      'connectionTimeoutSeconds',
      1,
      120,
      fallback: 15,
    );
    final identityRaw = raw['identityFilePath'];
    if (identityRaw != null && identityRaw is! String) {
      fail('"identityFilePath" must be a string or null.');
    }
    final identity = (identityRaw as String?)?.trim();
    if (authMethod == AuthMethod.privateKey &&
        (identity == null || identity.isEmpty)) {
      fail('private-key profiles must name an "identityFilePath".');
    }
    final description = raw['description'];
    if (description != null && description is! String) {
      fail('"description" must be a string.');
    }
    if ((description as String? ?? '').length > 500) {
      fail('"description" is too long.');
    }
    // Labels (ADR-013) travel by name. Legacy fields from exports
    // written before labels existed are honoured too: an
    // 'environment' becomes its label name, and 'tags' become
    // label names.
    List<String> readNameList(String key) {
      final v = raw[key];
      if (v == null) return const [];
      if (v is! List) fail('"$key" must be a list of strings.');
      return [
        for (final t in v)
          if (t is String) t else fail('"$key" must contain only strings.'),
      ];
    }

    final labelNames = <String>[];
    void addLabelName(String rawName) {
      final n = normalizeLabelName(rawName);
      if (n.isEmpty || n.length > 40) return;
      if (!labelNames.any((x) => x.toLowerCase() == n.toLowerCase())) {
        labelNames.add(n);
      }
    }

    for (final n in readNameList('labels')) {
      addLabelName(n);
    }
    final legacyEnv = raw['environment'];
    if (legacyEnv != null) {
      const known = {'production', 'staging', 'development', 'other'};
      if (legacyEnv is! String || !known.contains(legacyEnv)) {
        fail('"environment" has an unsupported value: $legacyEnv');
      }
      if (legacyEnv != 'other') {
        addLabelName('${legacyEnv[0].toUpperCase()}${legacyEnv.substring(1)}');
      }
    }
    for (final n in readNameList('tags')) {
      addLabelName(n);
    }
    if (labelNames.length > 20) fail('too many labels.');
    final iconRaw = raw['icon'];
    if (iconRaw != null && iconRaw is! String) {
      fail('"icon" must be a string or null.');
    }
    final colorRaw = raw['colorValue'];
    if (colorRaw != null && colorRaw is! num) {
      fail('"colorValue" must be a number or null.');
    }
    String? groupName;
    var groupType = FolderType.custom;
    final groupRaw = raw['group'];
    if (groupRaw != null) {
      if (groupRaw is! Map<String, Object?>) fail('"group" is not an object.');
      final gName = groupRaw['name'];
      if (gName is! String || gName.trim().isEmpty) {
        fail('"group.name" is missing.');
      }
      groupName = gName.trim();
      final gType = groupRaw['type'];
      for (final t in FolderType.values) {
        if (t.name == gType) groupType = t;
      }
      if (gType != null && gType != groupType.name) {
        fail('"group.type" has an unsupported value: $gType');
      }
    }
    final startupRaw = raw['startupDirectory'];
    if (startupRaw != null && startupRaw is! String) {
      fail('"startupDirectory" must be a string or null.');
    }
    final startupDirectory = (startupRaw as String?)?.trim().isEmpty ?? true
        ? null
        : (startupRaw as String).trim();

    final now = DateTime.now();
    return ImportedProfile(
      draft: SshSession(
        // Placeholder id; the controller assigns a fresh one (or
        // the existing profile's, for update-existing imports).
        id: '',
        name: name,
        host: host,
        port: port,
        username: username,
        authMethod: authMethod,
        privateKeyPath: authMethod == AuthMethod.privateKey ? identity : null,
        description: description?.trim() ?? '',
        icon: iconRaw as String?,
        colorValue: (colorRaw as num?)?.toInt(),
        connectionTimeout: Duration(seconds: timeout),
        startupDirectory: startupDirectory,
        createdAt: now,
        updatedAt: now,
      ),
      groupName: groupName,
      groupType: groupType,
      labelNames: labelNames,
    );
  }
}

/// One validated profile from an import file, with its group and
/// labels still in portable name form for the controller to
/// resolve.
final class ImportedProfile {
  const ImportedProfile({
    required this.draft,
    required this.groupName,
    required this.groupType,
    required this.labelNames,
  });

  final SshSession draft;
  final String? groupName;
  final FolderType groupType;
  final List<String> labelNames;

  /// The duplicate identity used for conflict detection (spec 14):
  /// name + host + username + port — never the host alone, since
  /// many profiles may share one host.
  String get conflictKey =>
      '${draft.name.toLowerCase()}|${draft.host.toLowerCase()}|'
      '${draft.username}|${draft.port}';
}

final class ProfileImportException implements Exception {
  const ProfileImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// How an import handles profiles whose conflict key matches an
/// existing one (spec 6.5: never silently overwrite).
enum ImportConflictStrategy { skip, copy, update }
