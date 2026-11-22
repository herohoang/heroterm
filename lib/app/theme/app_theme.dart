import 'package:flutter/material.dart';

/// Central theme for HeroTerm. Milestone 0 establishes a consistent,
/// keyboard-friendly desktop theme; visual polish continues in M7.
abstract final class AppTheme {
  static const _seed = Color(0xFF2DD4BF); // teal accent on dark surfaces

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0F1419),
      dividerColor: const Color(0xFF26313B),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 13.5),
        bodySmall: TextStyle(fontSize: 12),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return ThemeData(colorScheme: scheme, useMaterial3: true);
  }

  /// Monospace style used for terminal-adjacent and path/metric text.
  static const mono = TextStyle(
    fontFamily: 'Menlo',
    fontSize: 12.5,
    height: 1.35,
  );
}
