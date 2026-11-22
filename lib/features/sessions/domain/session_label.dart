import 'package:flutter/material.dart';

/// A user-defined label that can be attached to sessions
/// (user-directed replacement for the fixed environment list and
/// free-form tags, ADR-013). A label has a name and a colour; a
/// session can carry any number of labels, labels are shown on the
/// session item, and the list filters by them.
final class SessionLabel {
  const SessionLabel({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// ARGB colour value (see [labelPalette]).
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  Color get color => Color(colorValue);

  SessionLabel copyWith({String? name, int? colorValue, DateTime? updatedAt}) {
    return SessionLabel(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SessionLabel.fromJson(Map<String, Object?> json) {
    DateTime? parse(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return SessionLabel(
      id: json['id']! as String,
      name: json['name']! as String,
      colorValue: (json['colorValue'] as num?)?.toInt() ?? labelPalette[5],
      createdAt: parse(json['createdAt']) ?? DateTime.utc(1970),
      updatedAt: parse(json['updatedAt']) ?? DateTime.utc(1970),
    );
  }
}

/// The curated label colour palette (ARGB). Index-stable: stored
/// colours are values, not indexes, so reordering is safe.
const labelPalette = <int>[
  0xFFD32F2F, // red
  0xFFEF6C00, // orange
  0xFFF9A825, // amber
  0xFF2E7D32, // green
  0xFF00838F, // teal
  0xFF1565C0, // blue
  0xFF6A1B9A, // purple
  0xFFAD1457, // pink
  0xFF5D4037, // brown
  0xFF616161, // grey
];

/// The colour a label gets when it is created implicitly (data
/// migration, import, quick-create): the canonical environment
/// names keep the colours users already associate with them —
/// Production red, Staging orange, Development blue (ADR-013) —
/// everything else takes a stable palette slot by name hash.
int labelColorForName(String name) {
  switch (name.trim().toLowerCase()) {
    case 'production':
      return labelPalette[0];
    case 'staging':
      return labelPalette[1];
    case 'development':
      return labelPalette[5];
  }
  var hash = 0;
  for (final unit in name.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return labelPalette[hash % labelPalette.length];
}

/// Normalizes a label name for storage/comparison: trimmed,
/// single-spaced; empty when unusable.
String normalizeLabelName(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');
