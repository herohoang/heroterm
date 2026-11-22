import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import 'app/app.dart';
import 'core/debug/input_debug_log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // ADR-015 diagnostics: the vendored text-edit widget reports to
  // this sink; it stays inert unless the user enables the input
  // log (⌘⇧L) at runtime.
  CustomTextEdit.debugLog = InputDebugLog.log;
  runApp(const ProviderScope(child: HeroTermApp()));
}
