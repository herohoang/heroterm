# Feature Specification

## 1. Product overview

**HeroTerm** is a macOS-first desktop SSH client built with Flutter. The primary layout has a sidebar, central terminal/work area, and a bottom status/metrics footer.

## 2. Primary application states

### Disconnected
- Sidebar shows saved SSH sessions and user-created grouping folders.
- User can create/edit/delete sessions and manage folders.
- Terminal area shows a useful empty state and a connect action.
- Server metrics are hidden or shown as unavailable; never show fake values.

### Connecting
- Show the selected session and progress.
- Disable duplicate connect actions where appropriate.
- Provide timeout/error feedback and a safe retry path.

### Connected
- Sidebar switches to Remote Explorer for the connected host.
- Terminal shows an interactive remote shell.
- Footer shows remote CPU, RAM, and disk metrics.
- Connection identity (session/host/user) remains visible.

### Disconnected after a session
- Stop metrics polling and file operations.
- Show connection loss and provide reconnect/disconnect actions.
- Do not lose saved session profiles.

## 3. SSH session management

A session profile contains:
- `id`: stable unique identifier.
- `name`: user-facing label.
- `host`: hostname or IP.
- `port`: default 22.
- `username`.
- `authMethod`: password or private key.
- `credentialReference`: identifier for a Keychain item; never the secret itself.
- `privateKeyFormat` / passphrase reference if needed.
- `groupId`: optional grouping folder.
- `createdAt`, `updatedAt`, `lastConnectedAt`.
- Optional connection timeout and startup directory.

Session folders contain:
- `id`, `name`, `parentId` (optional), `sortOrder`, timestamps.
- Nested folders may be supported; avoid excessive nesting.
- Sessions without a folder belong to `Ungrouped`.

Required actions:
- Create, edit, duplicate, delete session.
- Create, rename, reorder, delete folder.
- Move session between groups.
- Search sessions by name, host, or username.
- Ask for confirmation when deleting a folder could affect contained sessions.

### Profile management completion (post-MVP, spec: `docs/SSH_PROFILE_MANAGEMENT.md`, ADR-012)

**Revision (ADR-013, user-directed):** the environment label, environment filter and tags above were replaced by user **Labels** (name + colour, multiple per profile, coloured filter chips, shown on each item), sessions and folders gained an optional icon + colour, and the session list's endpoint subtitle moved into a hover tooltip. Legacy environment/tags data migrates to labels automatically (Production stays red).

- [x] Every profile carries an **environment** label
      (Production / Staging / Development / Other), independent of
      its group. Production shows a full-word `PRODUCTION` badge —
      never colour alone. The list filters by environment,
      combined with search (which also covers description, tags
      and group name); the no-results state can clear all filters.
- [x] Profiles carry an optional description (≤500 chars) and
      deduplicated tags; folders carry a type (Project / Client /
      Custom) and can be collapsed in the sidebar.
- [x] The profile records the last connection attempt's outcome
      (success / failed, no detail) beside `lastConnectedAt`.
- [x] Duplicate shares the original's Keychain reference (no
      secret copy) with copy-on-write edits; the copy is named
      `<name> Copy` (numeric suffix when taken) and opens in the
      editor for review.
- [x] **Test Connection** in the editor and the session menu: a
      real connect through the SSH layer (host-key verification,
      prompts, the profile's timeout), closed immediately, with
      actionable secret-free errors. Timeout range is 1–120 s
      (default 15); a missing key file warns in the editor instead
      of blocking the save.
- [x] **Import/Export** as versioned JSON: export contains no
      secrets and no Keychain reference IDs; import validates
      strictly, previews New/Duplicate status, and resolves
      conflicts as Skip / Import as Copy / Update Existing
      (identity = name+host+username+port; groups match by
      name+type; imports never auto-connect).
- [x] The editor asks before discarding unsaved changes.

## 4. Authentication and trust

- Support password and private-key authentication.
- Use macOS Keychain for secrets and private-key material where feasible.
- If private key is selected from a file, decide and document whether to reference the file or import it into Keychain; do not silently copy it.
- Verify server host keys.
- On first connection, display host fingerprint and require explicit trust.
- If the key changes, block connection and show a security warning.
- Never default to accepting every host key.
- Never log secret data.

## 5. Interactive terminal

- Terminal must use an interactive PTY shell, not a sequence of non-interactive commands.
- Must support keyboard input/output, Ctrl+C, common control sequences, and resizing.
- Terminal emulator and SSH transport are separate components.
- Terminal state should survive normal widget rebuilds.
- On disconnect, stop sending input and show a recoverable state.
- Initial MVP may support one active SSH connection; keep the connection model extensible for tabs.

### Multiple sessions in tabs (post-MVP enhancement, spec: `docs/MULTI_SESSION_TERMINAL_TABS.md`)

- [x] Several SSH sessions stay open concurrently, each in its own
      tab with a status indicator (connecting / connected /
      disconnected / failed); the tab strip scrolls horizontally
      and keeps the active tab visible.
- [x] Each tab owns an independent connection, terminal buffer and
      scrollback; switching tabs never reconnects or resets a
      terminal; closing a tab releases only that session and
      activates a neighbouring tab.
- [x] The + button (or ⌘T) opens a temporary session picker panel
      grouped by folder with search; it stays open for opening
      several sessions in sequence. Opening an already-open profile
      activates its tab; "Open another session" deliberately opens
      a duplicate, titled `name (n)`.
- [x] Host-key and password prompts are serialized across tabs and
      attributed to the prompting tab; a failed tab never disturbs
      the others and offers Reconnect / Close.
- [x] The Remote Explorer and metrics footer always follow the
      active tab; the explorer remembers each tab's last directory.
- [x] Practical limit of 12 simultaneous tabs with a visible
      notice beyond it. Quitting the app closes all sessions (no
      live-session persistence is promised). Keyboard: ⌘T picker,
      ⌘1–9 jump, Ctrl+Tab / Ctrl+Shift+Tab cycle, ⌘⇧W close tab.

## 6. Remote Explorer

### Navigation
- On connection, initialize the remote working directory from the remote shell or a safe remote home-directory query.
- Clicking a directory navigates into it.
- Breadcrumb items navigate to that ancestor.
- Parent navigation is available except at filesystem root.
- Refresh re-queries SFTP.
- Display hidden files.
- Show name, kind, and optional size/modified time/permissions.
- Current path must be visible.

### Table view (post-MVP enhancement, spec: `docs/REMOTE_FILE_EXPLORER_TABLE_VIEW.md`)
- The listing is a multi-column table: Name (icon by kind), Size
  (human-readable; `—` for folders), Last modified
  (`yyyy-MM-dd HH:mm` local time), Owner, Group, Permission
  (`ls`-style string such as `drwxr-xr-x`; octal in the tooltip).
- Owner/Group come from SFTP attributes, which carry numeric
  UID/GID only. Names are resolved best-effort once per connection
  from the server's `/etc/passwd` and `/etc/group` (one read-only
  exec); unresolved IDs display as numbers, missing data as `—` —
  never guessed.
- Clicking a column header sorts ascending, clicking again
  reverses. Folders always stay first; the comparison then applies
  within each group (name case-insensitive, size/timestamp numeric,
  permission by normalized bits). Sorting is stable and purely
  client-side over the fetched metadata.
- Columns resize by dragging the right edge of the header
  (per-column min/max); double-clicking the edge auto-fits to the
  widest visible value. Rows are single-line with ellipsis and a
  full-path tooltip on the name.
- The sidebar itself resizes by dragging its right edge
  (260–720 px), never squeezing the terminal below a usable width.
  Sidebar width and column widths persist in `heroterm-ui.json`
  (Application Support) and are restored on the next launch.
- When the table is wider than the sidebar it scrolls horizontally;
  the current row selection is tracked in explorer state and
  cleared when the directory changes.

### Synchronization with terminal
- When the user executes `cd`, the Explorer should follow the shell's current working directory.
- A robust shell integration protocol is preferred over guessing from command text.
- Shell integration may require supported shell startup configuration; do not silently overwrite user dotfiles.
- If shell integration is unavailable, keep Explorer navigation independent and clearly indicate that terminal cwd synchronization is unavailable.
- Never parse terminal output as the only source of truth for file paths.

### File operations
- Right-click a file to open a context menu:
  - Rename
  - Delete
  - Download
- Rename:
  - Prompt for a new name.
  - Reject empty names, `.`/`..`, path separators, and invalid names.
  - Handle name collisions and permission errors.
- Delete:
  - Show confirmation with target name and full remote path.
  - Do not delete recursively unless a separate explicit directory-delete feature is designed.
  - Treat symbolic links carefully; do not follow a link and delete its target unexpectedly.
- Download:
  - Let the user select a local destination.
  - Show progress and error state.
  - Do not overwrite local files without confirmation.
- After successful mutation, refresh the current directory.

## 7. Upload by drag and drop

- Accept one or multiple local files dragged from macOS Finder.
- Drop target is the current remote directory displayed by the Explorer.
- Show destination path before starting.
- Use SFTP for transfer.
- Handle filename collisions with overwrite, rename, or skip options.
- Show per-file progress and aggregate progress where feasible.
- Support cancel/retry if the selected transport API supports it.
- On disconnect, mark in-progress transfers as failed/cancelled; never show false success.
- Refresh directory listing after each successful upload.
- Initial scope is local Finder → current remote directory. Remote-to-remote drag-and-drop is out of scope.

## 8. Server metrics footer

Show metrics for the connected remote server:
- CPU usage percent.
- Memory used / total and percent.
- Disk usage percent for `/` by default.
- Last update or stale/unavailable indicator.

Implementation notes:
- Linux CPU percentage requires two `/proc/stat` samples and a delta calculation.
- Memory should use `/proc/meminfo`, with `MemAvailable` as the preferred basis for estimated used memory.
- Disk usage can use a safe read-only `df` invocation for the chosen filesystem.
- Metrics polling default: 3–5 seconds; never allow overlapping polls.
- Stop polling on disconnect.
- Unsupported platforms/commands should yield an unavailable state, not fabricated values.
- Keep metric commands read-only and time-bounded.

## 9. Error handling

Errors should be actionable and not expose secrets. Distinguish:
- DNS/network failure.
- Authentication failure.
- Host key unknown/changed.
- Timeout.
- Permission denied.
- Remote path missing.
- File exists/collision.
- Transfer interruption.
- Unsupported shell/metrics capability.

Show user-friendly messages and optionally provide sanitized diagnostic details. Never include passwords, private-key contents, or authentication tokens.

## 10. Out of scope for first MVP

- Remote desktop/VNC.
- Full text editor for remote files.
- Remote-to-remote transfers.
- Port forwarding/tunnels.
- SFTP synchronization/mirroring.
- Multi-hop SSH/bastion hosts.
- Windows/Linux builds as release targets.
- Script marketplace or command execution automation.

## 11. Edit File (post-MVP enhancement, ADR-016)

Extends section 6. Behaviour specified by `docs/EDIT_FILE_ENHANCEMENT.md`:

- File context menu: **Edit** (built-in editor), **Open With…**
  (external macOS application), Download, Rename, Delete.
  Double-clicking a file opens the configured default editor.
- Built-in editor: one tab per file in the workspace tab strip,
  name + full path + dirty/clean state, syntax highlighting for
  the spec's format list, undo/redo, find & replace, line
  numbers. Limits: 2 MB, text only (binary sniff), UTF-8 only.
- Closing a dirty file always asks (Save / Don't Save / Cancel);
  a failed save keeps the editor open with its content.
- Save Confirmation (on by default, switchable in Settings)
  asks before an upload; Smart Save offers to skip it per file
  after 3 confirmed saves and never skips the close warning.
- External editor: the file is downloaded to a private temp
  workspace, opened in the chosen macOS app, watched with
  debounce + stability checks, and synced back (automatically
  when Auto Sync is on). Sync failures keep the local copy.
- Conflict detection: a save never silently overwrites a remote
  file whose size or mtime changed since it was loaded.
