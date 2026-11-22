Multi-Session Terminal Tabs Specification
Project: Hero SSH
Feature: Multiple simultaneous SSH sessions with terminal tabs
Status: Implemented (2026-10-25 — see the implementation status section at the end)
Last updated: 2026-10-25
1. Objective
Allow users to keep multiple SSH connections open at the same time and switch between them quickly without disconnecting or losing each terminal's state.

The terminal workspace uses a tab bar. Selecting New Tab (+) opens a session picker sidebar where the user can choose a saved SSH connection and open it as another terminal tab.
2. User experience
2.1 Terminal tab bar
- Display a tab for each terminal session opened in the current workspace.
- Each tab shows a recognizable connection label, such as production-01, plus a connection-state indicator.
- The active tab is visually distinct and its terminal occupies the main terminal area.
- Provide a + action at the end of the tab bar to create another session.
- If there are more tabs than fit in the available width, allow horizontal scrolling and keep the active tab visible.
- Tabs should support close actions. Closing a tab must not close other sessions.
- When a tab is closed, activate a nearby remaining tab. If no tabs remain, show an empty state with an action to open a session.
- Warn before closing a session that has an active foreground process or unsaved terminal workflow, where reliably detectable.
2.2 New-session picker sidebar
When the user clicks +, open a secondary sidebar/panel beside the terminal workspace containing saved SSH connections.
- Show connection name and useful identifying details such as host, username, and port.
- Provide search/filter for quickly finding a saved connection.
- Group connections by existing folders/groups if the connection manager supports them.
- Clicking a connection starts a new SSH session and creates a new terminal tab.
- Keep the picker open if the user wants to open several connections in sequence; provide a clear close/back action.
- If the selected connection is already open, offer to switch to its existing tab rather than silently creating a duplicate. A deliberate “Open another session” action may still be supported.
- If connection setup fails, show the error in the picker or a non-blocking notification and keep existing tabs intact.
2.3 Session lifecycle and status
Each tab has its own independent SSH connection and terminal state.

Suggested states:
- Connecting — connection handshake is in progress.
- Connected — session is ready for input.
- Reconnecting — an optional recovery attempt is in progress.
- Disconnected — connection ended or was lost.
- Error — connection could not be established or failed.
The UI must not imply that a session is connected when it is not. A failed or disconnected session should remain identifiable, with actions to reconnect or close it.
3. Behavior requirements
1. Users can maintain multiple SSH sessions concurrently, subject to system/server resource limits.
2. Switching tabs preserves each session's live terminal output and scrollback as far as the terminal implementation allows.
3. Input, output, resize events, and connection state must be routed only to the corresponding session.
4. Switching tabs must not recreate the SSH connection or reset the terminal.
5. Opening a new session must not interrupt sessions already running.
6. Closing one tab releases only that tab's SSH channel/process and terminal resources.
7. App shutdown behavior should be explicit: either close all sessions after confirmation or follow a documented persistence/reconnect strategy. Do not promise that live SSH processes survive application exit unless implemented.
8. Reuse the saved connection profile; do not expose stored passwords or private-key contents in the picker.
9. Support keyboard navigation between tabs and a shortcut for creating a new tab, following macOS conventions where feasible.
10. Tab labels should handle duplicate connection names, for example by showing host/port or a disambiguating suffix.
4. Layout and interaction
- Preserve the existing application layout: connection/file explorer on the left and terminal workspace on the right.
- The terminal workspace contains the tab strip at the top and the active terminal below.
- The session picker is a temporary panel associated with +; it should not permanently replace the existing file explorer.
- On narrow windows, prioritize terminal usability: the picker may overlay or temporarily collapse part of the workspace rather than forcing unusably narrow columns.
- Persist UI preferences such as tab ordering only if this can be done without persisting credentials or live session secrets.
5. Suggested data model
A runtime TerminalSession should be distinct from the saved SSH connection profile.
- sessionId: unique runtime identifier.
- connectionProfileId: reference to the saved connection.
- displayTitle: tab label.
- status: connecting / connected / reconnecting / disconnected / error.
- createdAt: session start time.
- terminalState: terminal instance, scrollback and size state.
- connectionError: sanitized, user-displayable error when applicable.
The connection profile stores reusable connection settings. Runtime sessions store ephemeral state and must not store plaintext credentials unnecessarily.
6. Architecture notes
- Maintain a session manager that owns the lifecycle of each SSH connection.
- Keep one terminal emulator instance (for example, xterm.js) per runtime session, or use an equivalent design that preserves independent buffers.
- Use a stable session ID to route terminal input/output and resize messages.
- Separate UI tab state from SSH transport state so rendering or switching tabs cannot accidentally reconnect or destroy a session.
- Ensure cleanup is idempotent: closing a tab twice or handling a disconnect race must not leak resources or close another session.
- For a Tauri/Rust implementation, keep SSH transport/session ownership in the backend and send events tagged with the session ID to the frontend.
7. Error handling and security
- Sanitize connection errors before displaying them; never include passwords, private-key contents, or authentication secrets in logs/toasts.
- Do not share terminal input, output, environment data, or credentials between sessions.
- Verify host keys according to the application's SSH host-key policy for every new connection.
- Handle connection timeouts, authentication failures, remote disconnects, and app/network interruptions without crashing the workspace.
- Set a practical configurable limit or show a clear warning if too many sessions are opened and resources are constrained.
---

## Implementation status (2026-10-25, ADR-011)

Implemented in full against this spec; decisions recorded as
ADR-011 in `docs/DECISIONS.md`.

- A `SessionManagerNotifier` owns one runtime `TerminalTab` per
  open session (stable runtime ID, own connection, own terminal
  buffer, own cwd tracking), replacing the single-connection
  controller. All tab terminals stay mounted (`IndexedStack`), so
  switching never reconnects or loses scrollback (3.2, 3.4, 3.5).
- Tab strip (2.1): label + status dot per tab, active tab
  highlighted, horizontal scrolling with the active tab kept
  visible, per-tab close, neighbour activation on close, and the
  pre-existing empty state (selected session + Connect) when no
  tabs remain.
- Picker (2.2): temporary panel beside the workspace (inline on
  wide windows, overlay on narrow ones), folder groups, search,
  stays open for sequences. Already-open profiles show an "Open"
  badge — tapping switches to the tab; a separate button opens
  another session deliberately. Duplicate tabs are titled
  `name (n)` (3.10). Picker never displays stored secrets (3.8).
- Lifecycle (2.3, 3.6, 3.7): states map to
  connecting/connected/disconnected/failed per tab; a failed or
  ended tab stays visible with Reconnect/Close actions; closing
  is idempotent and releases only that tab's resources. **App
  shutdown closes all sessions without confirmation** — the
  documented strategy; live sessions are not persisted.
- Keyboard (3.9): ⌘T picker, ⌘1–9 jump to tab, Ctrl+Tab /
  Ctrl+Shift+Tab cycle, ⌘⇧W close active tab; ⌘⇧C/D/R now act on
  the selected session / active tab respectively.
- Errors & security (section 7): host-key and password prompts
  are serialized through one queue across tabs and attributed to
  the prompting tab; a stale prompt (failed attempt, closed tab)
  is never shown. Host keys are verified per connection as
  before. Sessions share nothing: input, output, exec and SFTP
  are routed by tab. The practical limit is **12 tabs**; opening
  beyond it is refused with a visible notice.
- Deliberate deviation: the "warn before closing a tab with an
  active foreground process" item (2.1) is **not** implemented —
  it is conditioned on reliable detection, which SSH does not
  provide (an exec probe cannot distinguish a foreground job
  from an idle shell dependably); tabs close immediately, like a
  terminal window. Tab ordering is runtime-only (section 4
  permits persisting it but does not require it).
- The Remote Explorer and metrics footer bind to the active tab;
  the explorer re-attaches on tab switches and remembers each
  tab's last browsed directory.
- Verification: 117 automated tests (manager unit tests covering
  concurrent routing, duplicate handling, neighbour activation,
  per-tab failure isolation, prompt serialization and the tab
  limit, plus a widget test driving connect → picker → second
  tab → switch → close), and a live check with two concurrent
  real SSH sessions against a local fixture server (8/8).
