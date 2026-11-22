import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heroterm/app/ui_preferences.dart';

void main() {
  group('FileEditorSettings persistence (ADR-016)', () {
    test('legacy JSON without a fileEditor section yields defaults', () {
      final prefs = UiPreferences.fromJson({'sidebarWidth': 500});
      expect(prefs.sidebarWidth, 500);
      expect(prefs.fileEditor.defaultEditor, DefaultEditorKind.builtin);
      expect(prefs.fileEditor.autoSync, isTrue);
      expect(prefs.fileEditor.effectiveConfirmBeforeSave, isTrue);
      expect(prefs.fileEditor.smartSaveEnabled, isTrue);
      expect(prefs.fileEditor.smartSaveRecords, isEmpty);
    });

    test('an explicit OFF for the save confirmation is honoured, '
        'a merely stored default is not', () {
      // Never configured: even a stored false is the old release
      // default, so the confirmation stays ON (spec baseline).
      expect(
        const FileEditorSettings(confirmBeforeSave: false)
            .effectiveConfirmBeforeSave,
        isTrue,
      );
      // Deliberately turned off in Settings: respected, and the
      // choice survives a JSON round trip.
      const off = FileEditorSettings(
        confirmBeforeSave: false,
        saveConfirmConfigured: true,
      );
      expect(off.effectiveConfirmBeforeSave, isFalse);
      final restored = UiPreferences.fromJson(
        UiPreferences(fileEditor: off).toJson(),
      );
      expect(restored.fileEditor.effectiveConfirmBeforeSave, isFalse);
    });

    test('settings and smart-save records round-trip', () {
      const key = 'profile-1|/etc/app.conf';
      final prefs = UiPreferences(
        fileEditor: FileEditorSettings(
          defaultEditor: DefaultEditorKind.external,
          externalApp: '/Applications/Visual Studio Code.app',
          autoSync: false,
          confirmBeforeSave: true,
          tempDirectory: '/tmp/custom',
          smartSaveRecords: {
            key: const SmartSaveRecord(
              successfulSaves: 3,
              dontAskAgain: true,
              promptAnswered: true,
            ),
          },
        ),
      );
      final restored = UiPreferences.fromJson(prefs.toJson());
      final settings = restored.fileEditor;
      expect(settings.defaultEditor, DefaultEditorKind.external);
      expect(settings.externalApp, '/Applications/Visual Studio Code.app');
      expect(settings.autoSync, isFalse);
      expect(settings.confirmBeforeSave, isTrue);
      expect(settings.tempDirectory, '/tmp/custom');
      final record = settings.recordFor('profile-1', '/etc/app.conf');
      expect(record.successfulSaves, 3);
      expect(record.dontAskAgain, isTrue);
      expect(record.promptAnswered, isTrue);
    });

    test('the store saves and reloads file editor settings', () async {
      final tmp = await Directory.systemTemp.createTemp('heroterm-prefs-');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final store = UiPreferencesStore(directoryProvider: () async => tmp);
      await store.save(
        const UiPreferences(
          fileEditor: FileEditorSettings(externalApp: 'TextEdit'),
        ),
      );
      final loaded = await store.load();
      expect(loaded.fileEditor.externalApp, 'TextEdit');
    });
  });
}
