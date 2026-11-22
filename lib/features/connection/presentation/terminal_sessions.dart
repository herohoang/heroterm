import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:xterm/xterm.dart';

import '../../../core/debug/input_debug_log.dart';
import '../../../core/errors/app_error.dart';
import '../../remote_explorer/data/remote_file_service.dart';
import '../../remote_explorer/domain/remote_path.dart';
import '../../sessions/domain/ssh_session.dart';
import '../../sessions/presentation/session_providers.dart';
import '../../sessions/presentation/sessions_controller.dart';
import '../data/ssh_connection_service.dart';
import '../domain/connection_state.dart';
import 'connection_providers.dart';

final class HostKeyPromptState {
  const HostKeyPromptState(this.challenge);
  final HostKeyChallenge challenge;
}

final class PasswordPromptState {
  const PasswordPromptState({required this.username, required this.hostLabel});
  final String username;
  final String hostLabel;
}

/// The connection view of ONE terminal session, kept in its
/// historical shape: the active tab is projected into it by
/// [connectionProvider] so header/footer/explorer consumers keep
/// reading a single state.
final class SshConnectionState {
  const SshConnectionState({
    this.status = ConnectionStatus.disconnected,
    this.profile,
    this.terminal,
    this.error,
    this.notice,
    this.hostKeyPrompt,
    this.passwordPrompt,
    this.remoteCwd,
    this.cwdTrackingSupported = true,
  });

  final ConnectionStatus status;
  final SshSession? profile;
  final Terminal? terminal;
  final AppError? error;
  final String? notice;
  final HostKeyPromptState? hostKeyPrompt;
  final PasswordPromptState? passwordPrompt;
  final String? remoteCwd;
  final bool cwdTrackingSupported;

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isBusy =>
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.disconnecting;
}

/// One runtime terminal session (spec: MULTI_SESSION_TERMINAL_TABS
/// section 5). Distinct from the saved [SshSession] profile: a tab
/// is ephemeral, owns a live connection and terminal buffer, and
/// never stores credentials.
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.profile,
    required this.terminal,
    required this.createdAt,
    required this.title,
    this.status = ConnectionStatus.disconnected,
    this.error,
    this.notice,
    this.remoteCwd,
    this.cwdTrackingSupported = true,
  });

  /// Stable runtime ID used to route I/O and resize events.
  final String id;
  final SshSession profile;
  final Terminal terminal;
  final DateTime createdAt;

  /// Tab label; duplicates of one profile get a ` (n)` suffix.
  final String title;
  final ConnectionStatus status;
  final AppError? error;
  final String? notice;
  final String? remoteCwd;
  final bool cwdTrackingSupported;

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isBusy =>
      status == ConnectionStatus.connecting ||
      status == ConnectionStatus.disconnecting;

  TerminalTab copyWith({
    ConnectionStatus? status,
    Terminal? terminal,
    AppError? error,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    String? remoteCwd,
    bool? cwdTrackingSupported,
    String? title,
  }) {
    return TerminalTab(
      id: id,
      profile: profile,
      createdAt: createdAt,
      terminal: terminal ?? this.terminal,
      title: title ?? this.title,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
      remoteCwd: remoteCwd ?? this.remoteCwd,
      cwdTrackingSupported: cwdTrackingSupported ?? this.cwdTrackingSupported,
    );
  }
}

final class TabsState {
  const TabsState({
    this.tabs = const [],
    this.activeTabId,
    this.hostKeyPrompt,
    this.hostKeyPromptTabId,
    this.passwordPrompt,
    this.passwordPromptTabId,
    this.notice,
  });

  final List<TerminalTab> tabs;
  final String? activeTabId;
  final HostKeyPromptState? hostKeyPrompt;
  final String? hostKeyPromptTabId;
  final PasswordPromptState? passwordPrompt;
  final String? passwordPromptTabId;

  /// One-shot manager-level message (e.g. tab limit reached).
  final String? notice;

  TerminalTab? get activeTab {
    for (final tab in tabs) {
      if (tab.id == activeTabId) return tab;
    }
    return null;
  }

  TerminalTab? tabById(String id) {
    for (final tab in tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  TabsState copyWith({
    List<TerminalTab>? tabs,
    String? activeTabId,
    bool clearActiveTabId = false,
    HostKeyPromptState? hostKeyPrompt,
    bool clearHostKeyPrompt = false,
    String? hostKeyPromptTabId,
    PasswordPromptState? passwordPrompt,
    bool clearPasswordPrompt = false,
    String? passwordPromptTabId,
    String? notice,
    bool clearNotice = false,
  }) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      activeTabId: clearActiveTabId ? null : (activeTabId ?? this.activeTabId),
      hostKeyPrompt: clearHostKeyPrompt
          ? null
          : (hostKeyPrompt ?? this.hostKeyPrompt),
      hostKeyPromptTabId: clearHostKeyPrompt
          ? null
          : (hostKeyPromptTabId ?? this.hostKeyPromptTabId),
      passwordPrompt: clearPasswordPrompt
          ? null
          : (passwordPrompt ?? this.passwordPrompt),
      passwordPromptTabId: clearPasswordPrompt
          ? null
          : (passwordPromptTabId ?? this.passwordPromptTabId),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

/// The hook installed into bash/zsh interactive shells so each prompt
/// reports the working directory as an OSC 7 escape (ADR-008).
const shellIntegrationSnippet =
    "__ht_cwd(){ printf '\\033]7;file://%s%s\\007' \"\${HOSTNAME:-localhost}\" \"\$PWD\"; }; "
    "if [ -n \"\${BASH_VERSION:-}\" ]; then "
    "PROMPT_COMMAND=\"__ht_cwd\${PROMPT_COMMAND:+;\$PROMPT_COMMAND}\"; "
    "elif [ -n \"\${ZSH_VERSION:-}\" ]; then "
    "autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd __ht_cwd; fi";

final sessionManagerProvider =
    NotifierProvider<SessionManagerNotifier, TabsState>(
      SessionManagerNotifier.new,
    );

/// The active tab projected as a single-connection state, for
/// consumers that only ever deal with the visible session (header
/// chip, metrics gate, drop target, prompt dialogs).
final connectionProvider = Provider<SshConnectionState>((ref) {
  final tabs = ref.watch(sessionManagerProvider);
  final active = tabs.activeTab;
  return SshConnectionState(
    status: active?.status ?? ConnectionStatus.disconnected,
    profile: active?.profile,
    terminal: active?.terminal,
    error: active?.error,
    notice: active?.notice,
    hostKeyPrompt: tabs.hostKeyPrompt,
    passwordPrompt: tabs.passwordPrompt,
    remoteCwd: active?.remoteCwd,
    cwdTrackingSupported: active?.cwdTrackingSupported ?? true,
  );
});

final class _TabRuntime {
  RemoteConnection? connection;
  Timer? cwdWatchdog;
  Timer? resizeTimer;
  String? lastSentResize;
  String oscTail = '';
  int generation = 0;
  Completer<bool>? hostKeyCompleter;
  Completer<String?>? passwordCompleter;
}

/// Owns the lifecycle of every open terminal session (spec section
/// 6): one SSH connection and one terminal buffer per tab, routed by
/// tab ID; closing is idempotent and never touches other tabs.
final class SessionManagerNotifier extends Notifier<TabsState> {
  /// Practical cap on simultaneous sessions (spec section 7).
  static const maxTabs = 12;

  final _runtimes = <String, _TabRuntime>{};
  Future<void> _promptChain = Future<void>.value();
  static const _uuid = Uuid();

  @override
  TabsState build() => const TabsState();

  _TabRuntime _runtime(String tabId) =>
      _runtimes.putIfAbsent(tabId, _TabRuntime.new);

  void _updateTab(String tabId, TerminalTab Function(TerminalTab) update) {
    state = state.copyWith(
      tabs: [
        for (final tab in state.tabs)
          if (tab.id == tabId) update(tab) else tab,
      ],
    );
  }

  /// Opens [profile] in a tab. When a tab for this profile already
  /// exists, activates it instead of silently duplicating (spec
  /// 2.2); use [openAdditionalSession] to force another tab.
  Future<TerminalTab?> openSession(SshSession profile) async {
    for (final tab in state.tabs) {
      if (tab.profile.id == profile.id) {
        activateTab(tab.id);
        return tab;
      }
    }
    return openAdditionalSession(profile);
  }

  /// Always creates a new tab for [profile] and connects it.
  Future<TerminalTab?> openAdditionalSession(SshSession profile) async {
    if (state.tabs.length >= maxTabs) {
      state = state.copyWith(
        notice:
            'Tab limit reached ($maxTabs). Close a tab before opening '
            'another session.',
      );
      return null;
    }
    final tab = TerminalTab(
      id: _uuid.v4(),
      profile: profile,
      terminal: Terminal(maxLines: 10000),
      createdAt: DateTime.now(),
      title: profile.name,
    );
    _runtimes[tab.id] = _TabRuntime();
    state = state.copyWith(
      tabs: [...state.tabs, tab],
      activeTabId: tab.id,
      clearNotice: true,
    );
    _retitle();
    await _connectTab(tab.id);
    return state.tabById(tab.id);
  }

  void activateTab(String tabId) {
    if (state.tabById(tabId) == null) return;
    state = state.copyWith(activeTabId: tabId);
  }

  /// Activates the next/previous tab, wrapping around (keyboard
  /// navigation, spec 3.9).
  void activateRelativeTab(int delta) {
    if (state.tabs.length < 2) return;
    final index = state.tabs.indexWhere((t) => t.id == state.activeTabId);
    if (index < 0) return;
    // Dart's % is non-negative for a positive divisor: wraps around.
    activateTab(state.tabs[(index + delta) % state.tabs.length].id);
  }

  /// Closes one tab and releases only its resources. Idempotent:
  /// closing twice, or racing a disconnect, is a no-op the second
  /// time. Activates a neighbouring tab when the active one closes.
  Future<void> closeTab(String tabId) async {
    final index = state.tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;
    final runtime = _runtimes.remove(tabId);
    runtime?.generation++;
    runtime?.cwdWatchdog?.cancel();
    runtime?.resizeTimer?.cancel();
    runtime?.hostKeyCompleter?.complete(false);
    runtime?.passwordCompleter?.complete(null);
    final connection = runtime?.connection;
    runtime?.connection = null;

    final remaining = [
      for (final tab in state.tabs)
        if (tab.id != tabId) tab,
    ];
    var nextActive = state.activeTabId;
    if (state.activeTabId == tabId) {
      if (remaining.isEmpty) {
        nextActive = null;
      } else {
        final neighbour = index < remaining.length
            ? remaining[index]
            : remaining.last;
        nextActive = neighbour.id;
      }
    }
    state = state.copyWith(
      tabs: remaining,
      activeTabId: nextActive,
      clearActiveTabId: nextActive == null,
    );
    _retitle();
    await connection?.close();
  }

  Future<void> disconnectTab(String tabId) async {
    final tab = state.tabById(tabId);
    final runtime = _runtimes[tabId];
    if (tab == null || runtime == null) return;
    runtime.generation++;
    runtime.cwdWatchdog?.cancel();
    runtime.resizeTimer?.cancel();
    final connection = runtime.connection;
    if (connection == null) {
      _updateTab(
        tabId,
        (t) =>
            t.copyWith(status: ConnectionStatus.disconnected, clearError: true),
      );
      return;
    }
    _updateTab(
      tabId,
      (t) => t.copyWith(status: ConnectionStatus.disconnecting),
    );
    runtime.connection = null;
    await connection.close();
    if (state.tabById(tabId) != null) {
      _updateTab(
        tabId,
        (t) => t.copyWith(
          status: ConnectionStatus.disconnected,
          notice: 'Disconnected.',
        ),
      );
    }
  }

  /// Reconnects a tab that is open but not live (after a manual
  /// disconnect, a closed remote shell, or a failed attempt).
  Future<void> reconnectTab(String tabId) async {
    final tab = state.tabById(tabId);
    if (tab == null || tab.isConnected || tab.isBusy) return;
    await _connectTab(tabId);
  }

  /// Convenience wrappers acting on the active tab.
  Future<void> disconnectActive() async {
    final id = state.activeTabId;
    if (id != null) await disconnectTab(id);
  }

  Future<void> reconnectActive() async {
    final id = state.activeTabId;
    if (id != null) await reconnectTab(id);
  }

  Future<void> closeActive() async {
    final id = state.activeTabId;
    if (id != null) await closeTab(id);
  }

  /// Clears the active tab's error/notice (failed tabs settle back
  /// to a plain disconnected state that offers Reconnect).
  void dismissActiveError() {
    final tab = state.activeTab;
    if (tab == null) return;
    _updateTab(
      tab.id,
      (t) => t.copyWith(
        status: t.status == ConnectionStatus.failed
            ? ConnectionStatus.disconnected
            : t.status,
        clearError: true,
        clearNotice: true,
      ),
    );
  }

  void clearNotice() => state = state.copyWith(clearNotice: true);

  /// The SFTP file service of one tab's live connection.
  Future<RemoteFileService?> fileServiceFor(String tabId) async {
    final tab = state.tabById(tabId);
    final connection = _runtimes[tabId]?.connection;
    if (tab == null || connection == null || !tab.isConnected) return null;
    return connection.fileService();
  }

  /// Runs a one-off read-only command on one tab's connection.
  Future<String> runCommandFor(String tabId, String command) async {
    final tab = state.tabById(tabId);
    final connection = _runtimes[tabId]?.connection;
    if (tab == null || connection == null || !tab.isConnected) {
      throw const AppError(
        category: AppErrorCategory.unknown,
        userMessage: 'Not connected to a server.',
      );
    }
    return connection.runCommand(command);
  }

  Future<void> _connectTab(String tabId) async {
    final tab0 = state.tabById(tabId);
    if (tab0 == null) return;
    final runtime = _runtime(tabId);
    final generation = ++runtime.generation;
    final profile = tab0.profile;

    // A (re)connect gets a fresh terminal buffer.
    final terminal = Terminal(maxLines: 10000);
    _updateTab(
      tabId,
      (t) => t.copyWith(
        status: ConnectionStatus.connecting,
        terminal: terminal,
        clearError: true,
        clearNotice: true,
        cwdTrackingSupported: true,
      ),
    );

    String? storedSecret;
    final credentialRef = profile.credentialRef;
    if (credentialRef != null) {
      storedSecret = await ref
          .read(credentialStoreProvider)
          .read(credentialRef);
    }

    try {
      final connection = await ref
          .read(sshConnectionServiceProvider)
          .connect(
            ConnectRequest(
              profile: profile,
              storedSecret: storedSecret,
              onHostKeyPrompt: (challenge) => _promptHostKey(tabId, challenge),
              onPasswordPrompt: (username, hostLabel) =>
                  _promptPassword(tabId, username, hostLabel),
            ),
          );
      if (generation != runtime.generation || state.tabById(tabId) == null) {
        await connection.close();
        return;
      }
      runtime.connection = connection;
      final shell = connection.shell;

      terminal.onOutput = (data) {
        InputDebugLog.log('OUT "${CustomTextEditState.escapeForLog(data)}"');
        shell.writeInput(utf8.encode(data));
      };
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _forwardResize(tabId, runtime, shell, width, height);
      };
      shell.stdout.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        InputDebugLog.log('IN "${CustomTextEditState.escapeForLog(text)}"');
        _scanForCwdReport(tabId, text);
        terminal.write(text);
      });
      shell.stderr.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      );
      shell.done.then((_) {
        if (state.tabById(tabId)?.isConnected == true &&
            identical(runtime.connection?.shell, shell)) {
          runtime.connection = null;
          runtime.cwdWatchdog?.cancel();
          runtime.resizeTimer?.cancel();
          final code = shell.exitCode;
          _updateTab(
            tabId,
            (t) => t.copyWith(
              status: ConnectionStatus.disconnected,
              notice: code == null
                  ? 'The remote shell closed the connection.'
                  : 'Remote shell exited (code $code).',
            ),
          );
        }
      });

      _updateTab(tabId, (t) => t.copyWith(status: ConnectionStatus.connected));

      // Shell integration first (so the first tracked prompt already
      // reports), then the optional startup-directory cd.
      shell.writeInput(utf8.encode('$shellIntegrationSnippet\n'));
      final startup = profile.startupDirectory?.trim() ?? '';
      if (startup.isNotEmpty) {
        shell.writeInput(
          utf8.encode("cd '${startup.replaceAll("'", "'\\''")}'\n"),
        );
      }

      runtime.cwdWatchdog?.cancel();
      runtime.resizeTimer?.cancel();
      runtime.cwdWatchdog = Timer(const Duration(seconds: 6), () {
        if (generation == runtime.generation &&
            state.tabById(tabId)?.isConnected == true &&
            state.tabById(tabId)?.remoteCwd == null) {
          _updateTab(tabId, (t) => t.copyWith(cwdTrackingSupported: false));
        }
      });

      await ref.read(sessionsProvider.notifier).markConnected(profile.id);
    } catch (e) {
      final error = e is AppError
          ? e
          : AppError(
              category: AppErrorCategory.unknown,
              userMessage: 'Connection failed.',
              diagnostic: e.runtimeType.toString(),
            );
      runtime.connection = null;
      if (state.tabById(tabId) != null) {
        _updateTab(
          tabId,
          (t) => t.copyWith(status: ConnectionStatus.failed, error: error),
        );
        await ref
            .read(sessionsProvider.notifier)
            .markConnectionFailed(profile.id);
      }
      runtime.hostKeyCompleter?.complete(false);
      runtime.passwordCompleter?.complete(null);
    }
  }

  static final _osc7Pattern = RegExp(
    r'\x1B\]7;(file://[^\x07\x1B]*)(?:\x07|\x1B\\)',
  );

  /// Forwards a terminal size to the SSH server (ADR-018).
  ///
  /// The local buffer resizes immediately (the render layer drives
  /// it), but the server should not see every intermediate size:
  /// each window-change raises SIGWINCH and makes the shell
  /// redraw its input line, and a burst of them (window drag,
  /// layout settling after connect) interleaves redraws with
  /// reflows. The first size goes out immediately; later changes
  /// are deduplicated and debounced until the size is stable.
  void _forwardResize(
    String tabId,
    _TabRuntime runtime,
    RemoteShell shell,
    int width,
    int height,
  ) {
    final size = '${width}x$height';
    InputDebugLog.log('RESIZE $size');
    if (size == runtime.lastSentResize) return;
    if (runtime.lastSentResize == null) {
      runtime.lastSentResize = size;
      shell.resize(width, height);
      return;
    }
    runtime.resizeTimer?.cancel();
    runtime.resizeTimer = Timer(const Duration(milliseconds: 120), () {
      if (state.tabById(tabId) == null) return;
      if (!identical(runtime.connection?.shell, shell)) return;
      if (runtime.lastSentResize == size) return;
      runtime.lastSentResize = size;
      shell.resize(width, height);
    });
  }

  void _scanForCwdReport(String tabId, String text) {
    final runtime = _runtimes[tabId];
    final tab = state.tabById(tabId);
    if (runtime == null || tab == null) return;
    runtime.oscTail += text;
    var match = _osc7Pattern.firstMatch(runtime.oscTail);
    while (match != null) {
      final path = RemotePath.parseOsc7(match.group(1)!);
      runtime.oscTail = runtime.oscTail.substring(match.end);
      if (path != null && path != tab.remoteCwd) {
        _updateTab(
          tabId,
          (t) => t.copyWith(remoteCwd: path, cwdTrackingSupported: true),
        );
      }
      match = _osc7Pattern.firstMatch(runtime.oscTail);
    }
    if (runtime.oscTail.length > 1024) {
      runtime.oscTail = runtime.oscTail.substring(
        runtime.oscTail.length - 1024,
      );
    }
  }

  /// Gives duplicate tabs of one profile a ` (n)` suffix so tabs
  /// stay distinguishable (spec 3.10).
  void _retitle() {
    final counts = <String, int>{};
    var changed = false;
    final retitled = <TerminalTab>[];
    for (final tab in state.tabs) {
      final n = (counts[tab.profile.id] ?? 0) + 1;
      counts[tab.profile.id] = n;
      final title = n == 1 ? tab.profile.name : '${tab.profile.name} ($n)';
      if (title != tab.title) changed = true;
      retitled.add(tab.copyWith(title: title));
    }
    if (changed) state = state.copyWith(tabs: retitled);
  }

  Future<T> _enqueuePrompt<T>(Future<T> Function() body) {
    final result = _promptChain.then((_) => body());
    _promptChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _promptHostKey(String tabId, HostKeyChallenge challenge) {
    return _enqueuePrompt(() async {
      // The attempt may have failed or the tab closed while this
      // prompt waited its turn — never show a stale prompt.
      final tab = state.tabById(tabId);
      if (tab == null || tab.status == ConnectionStatus.failed) return false;
      final runtime = _runtime(tabId);
      state = state.copyWith(
        hostKeyPrompt: HostKeyPromptState(challenge),
        hostKeyPromptTabId: tabId,
      );
      final completer = Completer<bool>();
      runtime.hostKeyCompleter = completer;
      final trust = await completer.future;
      runtime.hostKeyCompleter = null;
      if (state.hostKeyPromptTabId == tabId) {
        state = state.copyWith(clearHostKeyPrompt: true);
      }
      return trust;
    });
  }

  void resolveHostKeyPrompt(bool trust) {
    final tabId = state.hostKeyPromptTabId;
    state = state.copyWith(clearHostKeyPrompt: true);
    if (tabId != null) {
      final completer = _runtimes[tabId]?.hostKeyCompleter;
      _runtimes[tabId]?.hostKeyCompleter = null;
      completer?.complete(trust);
    }
  }

  Future<String?> _promptPassword(
    String tabId,
    String username,
    String hostLabel,
  ) {
    return _enqueuePrompt(() async {
      final tab = state.tabById(tabId);
      if (tab == null || tab.status == ConnectionStatus.failed) return null;
      final runtime = _runtime(tabId);
      state = state.copyWith(
        passwordPrompt: PasswordPromptState(
          username: username,
          hostLabel: hostLabel,
        ),
        passwordPromptTabId: tabId,
      );
      final completer = Completer<String?>();
      runtime.passwordCompleter = completer;
      final password = await completer.future;
      runtime.passwordCompleter = null;
      if (state.passwordPromptTabId == tabId) {
        state = state.copyWith(clearPasswordPrompt: true);
      }
      return password;
    });
  }

  void resolvePasswordPrompt(String? password) {
    final tabId = state.passwordPromptTabId;
    state = state.copyWith(clearPasswordPrompt: true);
    if (tabId != null) {
      final completer = _runtimes[tabId]?.passwordCompleter;
      _runtimes[tabId]?.passwordCompleter = null;
      completer?.complete(password);
    }
  }
}
