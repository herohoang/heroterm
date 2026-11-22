import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../features/remote_explorer/domain/remote_entry.dart';

/// Static description of one explorer table column: header label and
/// width policy (table-view spec section 4). Widths are persisted
/// per column through [UiPreferences].
final class ExplorerColumnSpec {
  const ExplorerColumnSpec({
    required this.label,
    required this.defaultWidth,
    required this.minWidth,
    required this.maxWidth,
    this.rightAligned = false,
  });

  final String label;
  final double defaultWidth;
  final double minWidth;
  final double maxWidth;
  final bool rightAligned;

  double clampWidth(double width) => width.clamp(minWidth, maxWidth).toDouble();
}

const explorerColumnSpecs = <ExplorerSortColumn, ExplorerColumnSpec>{
  ExplorerSortColumn.name: ExplorerColumnSpec(
    label: 'Name',
    defaultWidth: 210,
    minWidth: 90,
    maxWidth: 560,
  ),
  ExplorerSortColumn.size: ExplorerColumnSpec(
    label: 'Size',
    defaultWidth: 84,
    minWidth: 56,
    maxWidth: 180,
    rightAligned: true,
  ),
  ExplorerSortColumn.modified: ExplorerColumnSpec(
    label: 'Last modified',
    defaultWidth: 138,
    minWidth: 104,
    maxWidth: 220,
  ),
  ExplorerSortColumn.owner: ExplorerColumnSpec(
    label: 'Owner',
    defaultWidth: 96,
    minWidth: 56,
    maxWidth: 220,
  ),
  ExplorerSortColumn.group: ExplorerColumnSpec(
    label: 'Group',
    defaultWidth: 96,
    minWidth: 56,
    maxWidth: 220,
  ),
  ExplorerSortColumn.permission: ExplorerColumnSpec(
    label: 'Permission',
    defaultWidth: 108,
    minWidth: 88,
    maxWidth: 180,
  ),
};

/// Which editor a file double-click opens (Edit File spec §2.6).
enum DefaultEditorKind { builtin, external }

/// Per-file Smart Save state (Edit File spec §2.5), keyed by
/// `sessionId|remotePath` in [FileEditorSettings.smartSaveRecords].
final class SmartSaveRecord {
  const SmartSaveRecord({
    this.successfulSaves = 0,
    this.dontAskAgain = false,
    this.promptAnswered = false,
  });

  /// Consecutive successful saves of this file.
  final int successfulSaves;

  /// Skip the before-save confirmation for this file.
  final bool dontAskAgain;

  /// The "remember this file?" prompt was already shown once.
  final bool promptAnswered;

  SmartSaveRecord copyWith({
    int? successfulSaves,
    bool? dontAskAgain,
    bool? promptAnswered,
  }) {
    return SmartSaveRecord(
      successfulSaves: successfulSaves ?? this.successfulSaves,
      dontAskAgain: dontAskAgain ?? this.dontAskAgain,
      promptAnswered: promptAnswered ?? this.promptAnswered,
    );
  }

  Map<String, Object?> toJson() => {
    'saves': successfulSaves,
    'dontAsk': dontAskAgain,
    'answered': promptAnswered,
  };

  factory SmartSaveRecord.fromJson(Map<String, Object?> json) {
    return SmartSaveRecord(
      successfulSaves: json['saves'] is num
          ? (json['saves'] as num).toInt()
          : 0,
      dontAskAgain: json['dontAsk'] == true,
      promptAnswered: json['answered'] == true,
    );
  }
}

/// The File Editor settings group (Edit File spec §2.6).
final class FileEditorSettings {
  const FileEditorSettings({
    this.defaultEditor = DefaultEditorKind.builtin,
    this.externalApp = '',
    this.autoSync = true,
    this.confirmBeforeSave = true,
    this.saveConfirmConfigured = false,
    this.smartSaveEnabled = true,
    this.tempDirectory = '',
    this.smartSaveRecords = const {},
  });

  final DefaultEditorKind defaultEditor;

  /// The configured external editor: an `.app` bundle path or an
  /// application name for `open -a`. Empty = not configured.
  final String externalApp;

  /// Sync external-editor changes to the server automatically.
  final bool autoSync;

  /// Ask before overwriting the remote file on save. Distinct
  /// from the unsaved-changes warning when closing a dirty file —
  /// "Don't ask again" (Smart Save) only ever skips THIS one.
  final bool confirmBeforeSave;

  /// Whether the user has explicitly set [confirmBeforeSave] in
  /// Settings. The confirmation is ON by default (the spec's
  /// baseline, and the premise of Smart Save), so a stored
  /// `false` only takes effect once the user actually chose it —
  /// this flag is what distinguishes "default from the first
  /// release build" from "deliberately turned off".
  final bool saveConfirmConfigured;

  /// The confirmation behaviour in force.
  bool get effectiveConfirmBeforeSave =>
      saveConfirmConfigured ? confirmBeforeSave : true;

  /// Master switch for the Smart Save memory (§2.5).
  final bool smartSaveEnabled;

  /// Local directory for external-edit workspaces.
  /// Empty = the system temp directory.
  final String tempDirectory;

  final Map<String, SmartSaveRecord> smartSaveRecords;

  static String recordKey(String sessionId, String remotePath) =>
      '$sessionId|$remotePath';

  SmartSaveRecord recordFor(String sessionId, String remotePath) =>
      smartSaveRecords[recordKey(sessionId, remotePath)] ??
      const SmartSaveRecord();

  FileEditorSettings copyWith({
    DefaultEditorKind? defaultEditor,
    String? externalApp,
    bool? autoSync,
    bool? confirmBeforeSave,
    bool? saveConfirmConfigured,
    bool? smartSaveEnabled,
    String? tempDirectory,
    Map<String, SmartSaveRecord>? smartSaveRecords,
  }) {
    return FileEditorSettings(
      defaultEditor: defaultEditor ?? this.defaultEditor,
      externalApp: externalApp ?? this.externalApp,
      autoSync: autoSync ?? this.autoSync,
      confirmBeforeSave: confirmBeforeSave ?? this.confirmBeforeSave,
      saveConfirmConfigured:
          saveConfirmConfigured ?? this.saveConfirmConfigured,
      smartSaveEnabled: smartSaveEnabled ?? this.smartSaveEnabled,
      tempDirectory: tempDirectory ?? this.tempDirectory,
      smartSaveRecords: smartSaveRecords ?? this.smartSaveRecords,
    );
  }

  Map<String, Object?> toJson() => {
    'defaultEditor': defaultEditor.name,
    'externalApp': externalApp,
    'autoSync': autoSync,
    'confirmBeforeSave': confirmBeforeSave,
    'confirmSaveSet': saveConfirmConfigured,
    'smartSaveEnabled': smartSaveEnabled,
    'tempDirectory': tempDirectory,
    'smartSaveRecords': {
      for (final entry in smartSaveRecords.entries)
        entry.key: entry.value.toJson(),
    },
  };

  factory FileEditorSettings.fromJson(Map<String, Object?> json) {
    final records = <String, SmartSaveRecord>{};
    final rawRecords = json['smartSaveRecords'];
    if (rawRecords is Map) {
      for (final entry in rawRecords.entries) {
        final value = entry.value;
        if (entry.key is String && value is Map) {
          records[entry.key as String] = SmartSaveRecord.fromJson(
            value.cast<String, Object?>(),
          );
        }
      }
    }
    return FileEditorSettings(
      defaultEditor:
          DefaultEditorKind.values.asNameMap()[json['defaultEditor']] ??
          DefaultEditorKind.builtin,
      externalApp: json['externalApp'] is String
          ? json['externalApp'] as String
          : '',
      autoSync: json['autoSync'] != false,
      confirmBeforeSave: json['confirmBeforeSave'] != false,
      saveConfirmConfigured: json['confirmSaveSet'] == true,
      smartSaveEnabled: json['smartSaveEnabled'] != false,
      tempDirectory: json['tempDirectory'] is String
          ? json['tempDirectory'] as String
          : '',
      smartSaveRecords: records,
    );
  }
}

/// Layout preferences persisted across launches (sidebar width and
/// explorer column widths), restored at startup (table-view spec
/// sections 3–4) — plus the File Editor settings group (Edit File
/// spec §2.6), stored in the same file.
final class UiPreferences {
  const UiPreferences({
    this.sidebarWidth = 440,
    this.columnWidths = const {},
    this.fileEditor = const FileEditorSettings(),
  });

  static const minSidebarWidth = 260.0;
  static const maxSidebarWidth = 720.0;

  final double sidebarWidth;
  final Map<ExplorerSortColumn, double> columnWidths;
  final FileEditorSettings fileEditor;

  double get clampedSidebarWidth =>
      sidebarWidth.clamp(minSidebarWidth, maxSidebarWidth).toDouble();

  double columnWidth(ExplorerSortColumn column) {
    final spec = explorerColumnSpecs[column]!;
    return spec.clampWidth(columnWidths[column] ?? spec.defaultWidth);
  }

  UiPreferences copyWith({
    double? sidebarWidth,
    Map<ExplorerSortColumn, double>? columnWidths,
    FileEditorSettings? fileEditor,
  }) {
    return UiPreferences(
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      columnWidths: columnWidths ?? this.columnWidths,
      fileEditor: fileEditor ?? this.fileEditor,
    );
  }

  Map<String, Object?> toJson() => {
    'sidebarWidth': sidebarWidth,
    'columnWidths': {
      for (final entry in columnWidths.entries) entry.key.name: entry.value,
    },
    'fileEditor': fileEditor.toJson(),
  };

  factory UiPreferences.fromJson(Map<String, Object?> json) {
    final widths = <ExplorerSortColumn, double>{};
    final rawWidths = json['columnWidths'];
    if (rawWidths is Map) {
      for (final column in ExplorerSortColumn.values) {
        final value = rawWidths[column.name];
        if (value is num) {
          widths[column] = explorerColumnSpecs[column]!.clampWidth(
            value.toDouble(),
          );
        }
      }
    }
    final rawSidebar = json['sidebarWidth'];
    final rawEditor = json['fileEditor'];
    return UiPreferences(
      sidebarWidth: rawSidebar is num
          ? rawSidebar
                .toDouble()
                .clamp(minSidebarWidth, maxSidebarWidth)
                .toDouble()
          : 440,
      columnWidths: widths,
      fileEditor: rawEditor is Map
          ? FileEditorSettings.fromJson(rawEditor.cast<String, Object?>())
          : const FileEditorSettings(),
    );
  }
}

/// JSON file store for [UiPreferences], following the same pattern
/// as the session repository: one file in Application Support,
/// atomic writes, a corrupt file falls back to defaults.
final class UiPreferencesStore {
  UiPreferencesStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final dir = await _directoryProvider();
    return File('${dir.path}/heroterm-ui.json');
  }

  Future<UiPreferences> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const UiPreferences();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return const UiPreferences();
      return UiPreferences.fromJson(decoded);
    } catch (_) {
      return const UiPreferences();
    }
  }

  Future<void> save(UiPreferences preferences) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(preferences.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

final uiPreferencesStoreProvider = Provider<UiPreferencesStore>(
  (ref) => UiPreferencesStore(),
);

final uiPreferencesProvider =
    NotifierProvider<UiPreferencesNotifier, UiPreferences>(
      UiPreferencesNotifier.new,
    );

final class UiPreferencesNotifier extends Notifier<UiPreferences> {
  Timer? _saveTimer;
  bool _loaded = false;
  bool _userChanged = false;

  @override
  UiPreferences build() {
    ref.onDispose(() => _saveTimer?.cancel());
    unawaited(_load());
    return const UiPreferences();
  }

  Future<void> _load() async {
    final loaded = await ref.read(uiPreferencesStoreProvider).load();
    if (_loaded) return;
    _loaded = true;
    // Do not clobber a change the user made while loading.
    if (!_userChanged) {
      state = loaded;
    }
  }

  void setSidebarWidth(double width) {
    _userChanged = true;
    state = state.copyWith(
      sidebarWidth: width
          .clamp(UiPreferences.minSidebarWidth, UiPreferences.maxSidebarWidth)
          .toDouble(),
    );
    _scheduleSave();
  }

  void setColumnWidth(ExplorerSortColumn column, double width) {
    _userChanged = true;
    final widths = Map<ExplorerSortColumn, double>.of(state.columnWidths);
    widths[column] = explorerColumnSpecs[column]!.clampWidth(width);
    state = state.copyWith(columnWidths: widths);
    _scheduleSave();
  }

  void setFileEditorSettings(FileEditorSettings settings) {
    _userChanged = true;
    state = state.copyWith(fileEditor: settings);
    _scheduleSave();
  }

  void setSmartSaveRecord(String key, SmartSaveRecord record) {
    _userChanged = true;
    final records = Map<String, SmartSaveRecord>.of(
      state.fileEditor.smartSaveRecords,
    );
    records[key] = record;
    state = state.copyWith(
      fileEditor: state.fileEditor.copyWith(smartSaveRecords: records),
    );
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(ref.read(uiPreferencesStoreProvider).save(state));
    });
  }

  /// Writes pending changes immediately (e.g. at drag end).
  void flush() {
    _saveTimer?.cancel();
    unawaited(ref.read(uiPreferencesStoreProvider).save(state));
  }
}
