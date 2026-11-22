import 'package:flutter/material.dart';

/// Curated icon choices for sessions and folders (ADR-013): a
/// small, recognizable set beats an unbounded picker. Icons are
/// stored by stable string ID, never by code point, so the set can
/// evolve without breaking saved libraries.
const appearanceIconChoices = <String, IconData>{
  'server': Icons.dns_outlined,
  'database': Icons.storage_outlined,
  'cloud': Icons.cloud_outlined,
  'terminal': Icons.terminal,
  'code': Icons.code,
  'globe': Icons.language,
  'lock': Icons.lock_outline,
  'shield': Icons.shield_outlined,
  'rocket': Icons.rocket_launch_outlined,
  'cart': Icons.shopping_cart_outlined,
  'bank': Icons.account_balance_outlined,
  'home': Icons.home_outlined,
  'work': Icons.work_outline,
  'star': Icons.star_outline,
  'science': Icons.science_outlined,
  'bug': Icons.bug_report_outlined,
  'folder': Icons.folder_outlined,
  'box': Icons.inventory_2_outlined,
};

/// Resolves a stored icon ID to its icon, falling back to
/// [fallback] for unknown/absent IDs.
IconData appearanceIcon(String? id, {required IconData fallback}) {
  if (id == null) return fallback;
  return appearanceIconChoices[id] ?? fallback;
}

/// The colour palette offered for sessions and folders (ARGB) —
/// the same palette as labels, so the whole library speaks one
/// colour language.
const appearanceColorChoices = <int>[
  0xFFD32F2F,
  0xFFEF6C00,
  0xFFF9A825,
  0xFF2E7D32,
  0xFF00838F,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFAD1457,
  0xFF5D4037,
  0xFF616161,
];
