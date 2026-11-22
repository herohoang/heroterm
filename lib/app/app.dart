import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'theme/app_theme.dart';

class HeroTermApp extends StatelessWidget {
  const HeroTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeroTerm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const AppShell(),
    );
  }
}
