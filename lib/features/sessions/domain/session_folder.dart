/// What a group represents (profile spec 5.1): a project, a
/// client, or a custom grouping.
enum FolderType { project, client, custom }

/// A user-defined grouping folder for SSH sessions.
/// Sessions with a null folder belong to the implicit "Ungrouped" group.
final class SessionFolder {
  const SessionFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.type = FolderType.custom,
    this.icon,
    this.colorValue,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? parentId;
  final FolderType type;

  /// Appearance: a curated icon ID (see session_appearance.dart)
  /// and an ARGB colour; both optional (ADR-013).
  final String? icon;
  final int? colorValue;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  SessionFolder copyWith({
    String? name,
    String? parentId,
    bool clearParentId = false,
    FolderType? type,
    String? icon,
    bool clearIcon = false,
    int? colorValue,
    bool clearColor = false,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return SessionFolder(
      id: id,
      name: name ?? this.name,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
      type: type ?? this.type,
      icon: clearIcon ? null : (icon ?? this.icon),
      colorValue: clearColor ? null : (colorValue ?? this.colorValue),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<String> validate() {
    final problems = <String>[];
    if (name.trim().isEmpty) problems.add('Folder name must not be empty.');
    if (parentId != null && parentId == id) {
      problems.add('A folder cannot be its own parent.');
    }
    return problems;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'parentId': parentId,
    'type': type.name,
    'icon': icon,
    'colorValue': colorValue,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SessionFolder.fromJson(Map<String, Object?> json) {
    DateTime? parse(Object? v) => v is String ? DateTime.tryParse(v) : null;
    var type = FolderType.custom;
    for (final v in FolderType.values) {
      if (v.name == json['type']) type = v;
    }
    return SessionFolder(
      id: json['id']! as String,
      name: json['name']! as String,
      parentId: json['parentId'] as String?,
      type: type,
      icon: json['icon'] as String?,
      colorValue: (json['colorValue'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: parse(json['createdAt']) ?? DateTime.utc(1970),
      updatedAt: parse(json['updatedAt']) ?? DateTime.utc(1970),
    );
  }
}
