# ROADMAP — HeroTerm

This roadmap is an incremental plan, not a claim that features already exist. Update status only after implementation and verification.

## Milestone 0 — Project foundation

> Status 2026-10-24: **Milestone 0 acceptance criteria met.** The app
> was launched on the user's macOS machine and the expected shell was
> confirmed by screenshot (header + Disconnected state, Sessions
> sidebar, disconnected workspace, metrics footer showing
> unavailable). `flutter analyze` clean, `flutter test` 19 passed,
> format check clean on the authoring environment. Carried forward:
> Keychain read/write is exercised for real in Milestone 1 when
> credentials are first saved (its checkbox stays unticked until
> then), and final selection of terminal/SSH packages is deferred to
> the Milestone 2 spike (see `docs/DEPENDENCIES.md`).

- [x] Create Flutter macOS desktop app and verify it launches.
- [x] Establish linting, formatting, test layout, and CI-friendly commands.
- [x] Select and document terminal emulator and SSH/SFTP dependencies after compatibility review. *(Resolved in the Milestone 2 spike: dartssh2 4.1.0 + xterm 4.0.0 — see `docs/DEPENDENCIES.md`.)*
- [x] Establish theme, app shell, responsive desktop layout, and error model.
- [ ] Add secure credential storage abstraction backed by macOS Keychain.
- [x] Add architecture and threat-model documentation.

**Acceptance criteria**
- App runs on a supported macOS development machine.
- `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and `flutter test` can run.
- No credential is persisted in plain-text configuration.

## Milestone 1 — SSH Session Manager

> Status 2026-10-24: Implemented and verified on the authoring
> environment (`flutter analyze` clean, `flutter test` 31 passed,
> format check clean): session/folder CRUD, grouping with Ungrouped,
> JSON metadata persistence (ADR-006), Keychain credential lifecycle
> via the credential store (secrets never enter the JSON library —
> covered by canary tests), full profile fields, last-connected
> display, and search. Still pending user verification on macOS:
> create a session with a password, quit and reopen the app, and
> confirm the session survives and the password is in Keychain
> (that also closes the carried-over Milestone 0 Keychain item).

- [x] Session list shown when no host is connected.
- [x] Create, edit, duplicate, and delete session profiles.
- [x] Create, rename, reorder, and delete grouping folders.
- [x] Move sessions between folders; support an Ungrouped group.
- [x] Persist non-secret session metadata locally.
- [ ] Store passwords/passphrases securely in Keychain. *(Implemented via the Keychain-backed credential store; checkbox closes when exercised on a real Mac — see status note.)*
- [x] Support hostname, port, username, auth method (password/private key), and optional connection timeout.
- [x] Add connection status and last-used information.
- [x] Add search/filter for saved sessions.

**Acceptance criteria**
- Session and group changes survive restart. *(Verified by repository round-trip and controller reload tests; macOS quit/reopen check pending — see status note.)*
- Secret values are not written to the database, logs, or export files. *(Verified by canary tests over the persisted JSON.)*
- Deleting a group has a documented behavior for its sessions and requires confirmation if destructive. *(Documented in ADR-006: sessions move to Ungrouped, subfolders move up; the UI always confirms first.)*

## Milestone 2 — SSH connection and terminal

> Status 2026-10-24: Implemented (dartssh2 4.1.0 + xterm 4.0.0, see
> `docs/DEPENDENCIES.md`) and verified end-to-end against a real SSH
> server (a disposable paramiko server on the authoring VM):
> password auth + interactive PTY echo, private-key auth, first-use
> host-key prompt with SHA256 fingerprint, silent match on reconnect,
> wrong password mapped to a typed authentication error, and a
> tampered known-host entry blocked as host-key-changed — 8/8
> integration checks passed, plus unit/widget tests (45 total).
> User verification received 2026-10-24: after the ADR-007 sandbox
> fix, the user connected from the macOS app to a real server
> successfully (a Vietnamese-IME terminal input bug found during
> that session was fixed separately — see ADR-009).

- [x] Connect/disconnect with password authentication.
- [x] Connect/disconnect with supported private-key formats.
- [x] Verify host keys and show fingerprint on first connection.
- [x] Block connection on unexpected host-key changes until resolved.
- [x] Interactive shell with PTY.
- [x] Keyboard input, terminal output, Ctrl+C, common control sequences, and terminal resize.
- [x] Show connecting/connected/disconnected/error states.
- [x] Keep terminal session and UI lifecycle coordinated.
- [x] Support one active connection first; design state model to permit multiple tabs later.

**Acceptance criteria**
- Can log in to a test Linux server using each supported auth method. *(Verified against the VM test server for password and Ed25519 key auth; macOS UI check pending.)*
- Terminal supports ordinary interactive commands and long-running processes. *(PTY shell verified by integration echo tests; long-running process behavior is standard shell passthrough.)*
- Disconnect/reconnect does not leave a stuck loading state.
- Host-key verification works and is tested.

## Milestone 3 — Remote Explorer and working directory

> Status 2026-10-24: Implemented and verified end-to-end against a
> real SSH server (disposable paramiko server on the authoring VM):
> SFTP listing with kinds/sizes/permissions, subdirectory navigation,
> hidden files, names with spaces, symlink-to-directory resolution,
> missing-directory typed errors, and OSC 7 cwd tracking through a
> real bash (including `cd` into a path containing a space) — 11/11
> integration checks passed, plus unit/widget tests (58 total).
> Fallback for shells without the integration hook is defined in
> ADR-008. User verification received 2026-10-24: in the macOS app
> against a real server, the sidebar showed the folder contents and
> followed `cd` from the terminal.

- [x] Connected sidebar switches from saved sessions to Remote Explorer.
- [x] List remote files and directories through SFTP.
- [x] Click a directory to navigate into it.
- [x] Breadcrumb navigation to parent/ancestor directories.
- [x] Refresh directory listing.
- [x] Show hidden files and useful file metadata.
- [x] Track terminal working directory changes, including `cd`, `pushd/popd` where supported.
- [x] Define fallback behavior for unsupported shells or shell startup files.
- [x] Handle permissions, missing directories, symbolic links, and filenames with spaces/unicode.

**Acceptance criteria**
- Remote Explorer and terminal agree on the current working directory when shell integration is active. *(Verified live via OSC 7 reports, and confirmed by the user in the macOS app against a real server on 2026-10-24: sidebar followed `cd`.)*
- Navigation errors do not crash the app or silently change the current path. *(Verified: failed navigation keeps the previous path and listing, and surfaces the error with Retry.)*
- File listing is refreshed after successful mutations/transfers. *(Refresh control in place; mutations/transfers arrive in Milestone 4 and reuse it.)*

## Milestone 4 — File context actions

> Status 2026-10-24: Implemented. Verified by unit tests (70 total)
> and live SFTP checks against the paramiko test server (rename,
> 256 KB byte-exact download, file delete, recursive folder delete,
> exists/collision pre-checks — 7/7). Pending user verification in
> the macOS app. Note: the sandbox entitlement for user-selected
> files was upgraded from read-only to read-write so the download
> save panel grants write access (ADR-007 addendum).

- [x] Right-click a file to show context menu.
- [x] Rename with validation and collision handling.
- [x] Delete with explicit confirmation showing path/name.
- [x] Download to a user-selected local destination.
- [x] Progress, error, retry, and cancellation where supported.
- [x] Handle stale selections and permission errors.

**Acceptance criteria**
- Rename/Delete/Download operate through SFTP rather than unsafe shell string interpolation. ✓
- Delete cannot happen from a single accidental click. ✓ (Menu selection, then a confirmation dialog naming the full path.)
- A failed operation leaves the UI in a recoverable state. ✓ (Errors surface in the explorer banner; failed downloads remove the partial file; listings keep their previous state.)

## Milestone 5 — Drag-and-drop upload

> Status 2026-10-24: Implemented (desktop_drop 0.8.4). The user's
> first Mac test showed drops doing nothing: in the App Sandbox,
> Finder files are only readable after starting security-scoped
> access from the drop item's bookmark — the integration now does
> that for the duration of the upload, reports unreadable drops as
> a permission error instead of silently skipping them, and adds
> an Upload button (file picker) as a fallback in the explorer
> header. Verified by
> unit tests (76 total; collision overwrite/rename/skip, batch
> cancel, recursive folder drop) and live SFTP checks against the
> paramiko test server (300 KB byte-identical upload, overwrite
> truncation, subdirectory creation + upload — 7/7). Dropped
> folders upload recursively. The user confirmed on 2026-10-24
> that upload (drag-and-drop) works in the macOS app.

- [x] Accept one or multiple files dragged from macOS Finder.
- [x] Display a clear drop target and destination path.
- [x] Upload files into the current remote directory through SFTP.
- [x] Show per-file and aggregate progress.
- [x] Resolve filename collisions: overwrite, rename, or skip.
- [x] Handle permissions, disconnects, partial uploads, and retry/cancel where supported.
- [x] Refresh remote listing after successful upload.

**Acceptance criteria**
- Dropping a file into the explorer uploads it to the visible current directory. ✓
- Dropping while disconnected is rejected with a clear message. ✓ (Drop overlay and snackbar both say to connect first.)
- Failed/partial uploads are reported and do not appear as successful. ✓ (Per-file failures are listed; cancelled uploads delete the partial remote file.)

## Milestone 6 — Server metrics footer

> Status 2026-10-24: Implemented. One read-only exec command per
> poll collects `/proc/stat`, `/proc/meminfo` and `df -P /` behind
> section markers (10 s timeout); CPU uses the two-sample delta,
> memory uses MemTotal − MemAvailable, disk is for `/`. Polling
> runs every 4 s from connection start, never overlaps, and stops
> on disconnect; failures mark the last good values stale, and a
> server that cannot report yields unavailable — never invented
> numbers. Verified by unit tests (91 total; parsers, delta,
> stale/unavailable transitions) and live checks against the
> paramiko test server extended with real exec support (7/7:
> real memory/disk values on the first fetch, CPU percentage on
> the second). Pending user verification in the macOS app against
> a real server.

- [x] CPU usage percentage using two samples/delta, not a single `/proc/stat` snapshot.
- [x] Memory used/total and percentage, with documented Linux calculation using `MemAvailable`.
- [x] Disk usage percentage for a documented target filesystem (default `/`).
- [x] Poll every 3–5 seconds by default; avoid overlapping requests.
- [x] Stop polling on disconnect and surface unavailable metrics.
- [x] Handle unsupported OS/commands and permission restrictions.

**Acceptance criteria**
- Metrics describe the remote host, not the local Mac. ✓ (All values come from the remote host over the SSH exec channel.)
- Values are timestamped or visibly indicate stale/unavailable data. ✓ (Footer shows the sample time, a "Stale" state, or unavailable.)
- Metrics failures do not break the terminal or explorer. ✓ (The poller swallows failures into stale/unavailable state only.)

## Milestone 7 — Polish and release

> Status 2026-10-25: Implemented; 96 automated tests pass.
> Reconnect (button + ⌘⇧R) works after manual disconnect, a closed
> remote shell, or a failed attempt; connection timeouts were
> already enforced per session (socket + handshake) since
> Milestone 2. App shortcuts: ⌘/Ctrl+Shift+C connect, +D disconnect,
> +R reconnect. Loading/empty/error states audited — metrics footer
> gained a "collecting" state, and a real explorer-header layout
> overflow at sidebar width was found by a widget test and fixed
> (compact header buttons). Custom app icon (dark terminal tile,
> generated by `scripts/generate_app_icon.py`), product name set to
> HeroTerm, version 1.0.0. Packaging: `scripts/package_macos.sh`
> builds the `.app` and a drag-install `.dmg`; Developer ID signing
> + notarization are wired into the script but need the user's paid
> Apple Developer certificate on the Mac (plan in
> `docs/RELEASE.md`) — the actual signed/notarized DMG is the one
> item still outstanding. Security review in
> `docs/SECURITY_REVIEW.md`; manual checklist in
> `docs/MANUAL_TEST_CHECKLIST.md`; user guide in
> `docs/USER_GUIDE.md`; release notes in `CHANGELOG.md`.
> Multi-tab connections, saved snippets, and Windows/Linux are
> deferred until after MVP stability, per the original roadmap.

- [x] Keyboard shortcuts, accessibility, empty/loading/error states.
- [x] Reconnect behavior and connection timeout handling.
- [x] App icon, app metadata, signing/notarization plan, `.app` and `.dmg` packaging.
- [x] Automated tests and manual test checklist.
- [x] Security review for credential handling, host keys, logging, and file operations.
- [x] User documentation and release notes.
- [x] Consider multi-tab connections, saved snippets, and Windows/Linux only after MVP stability.

## Post-MVP enhancement — Remote Explorer table view

> Status 2026-10-25: Implemented from the user's spec
> (`docs/REMOTE_FILE_EXPLORER_TABLE_VIEW.md`); ADR-010 records the
> decisions. The listing became a sortable, resizable table
> (Name / Size / Last modified / Owner / Group / Permission):
> SFTP supplies numeric UID/GID and mode; account names resolve
> best-effort once per connection from `/etc/passwd` + `/etc/group`
> with numeric fallback. Sorting is folders-first and stable;
> column widths and the sidebar width (drag handle, 260–720 px)
> persist in `heroterm-ui.json` and restore at startup; double-click
> a column edge to auto-fit. Two latent bugs found and fixed along
> the way: the Finder drop target had never been mounted in the
> widget tree (now wraps the sidebar), and the explorer could miss
> its attach if a connection completed before its first frame.
> Verified by 114 automated tests plus live SFTP/exec checks
> (real UID/GID/mode from the test server; uid 0 → "root").
> Pending: user verification in the macOS app.

## Post-MVP enhancement — Multi-session terminal tabs

> Status 2026-10-25: Implemented from the user's spec
> (`docs/MULTI_SESSION_TERMINAL_TABS.md`); ADR-011 records the
> decisions. A session manager now owns one runtime session per
> tab (independent connection, terminal buffer, cwd tracking):
> tab strip with status dots and close buttons, a session picker
> panel on + / ⌘T (folder groups, search, already-open profiles
> switch instead of duplicating, deliberate "open another" with
> `name (n)` titles), host-key/password prompts serialized across
> tabs, explorer + metrics bound to the active tab, a 12-tab
> limit, and tab keyboard navigation (⌘1–9, Ctrl+Tab). Verified
> by 117 automated tests plus a live two-session check against
> the local SSH fixture (8/8: independent shells, per-tab exec
> and SFTP, closing one tab leaves the other usable). Pending:
> user verification in the macOS app.

## Post-MVP enhancement — SSH profile management (SSH-PROFILE-001)

> Status 2026-10-25: Implemented from the user's spec
> (`docs/SSH_PROFILE_MANAGEMENT.md`); ADR-012 records what was
> verified as already compliant (CRUD, folders, Keychain secrets,
> persistence, validation, delete guards) versus what was added:
> environment labels with a PRODUCTION badge and environment
> filter, description/tags, group types and collapsible groups,
> last-attempt outcome, shared-reference duplicates with
> copy-on-write secret edits, Test Connection (editor + menu),
> strict Import/Export JSON with preview and Skip/Copy/Update
> conflict handling, an unsaved-changes guard in the editor, and
> the timeout range aligned to 1–120 s (default 15). Verified by
> the full automated suite plus a live Test Connection check
> against the local SSH fixture (success, wrong-password failure
> with a secret-free message, export→import round trip).
> Pending: user verification in the macOS app.

## Suggested implementation order

1. Milestone 0
2. Milestone 1
3. Milestone 2
4. Milestone 3
5. Milestones 4 and 5
6. Milestone 6
7. Milestone 7

Do not start all milestones at once. Complete and verify one vertical slice at a time.

## Post-MVP revision — Labels & appearance (ADR-013)

> Status 2026-10-25: Per the user's direction after trying the
> profile build, the environment label/filter and tags were
> merged into one **Labels** feature (name + colour, multiple
> per session, filter chips, manager dialog), sessions and
> folders gained an optional icon + colour, and the session
> item's endpoint subtitle moved into a hover tooltip. Legacy
> environment/tags data migrates to labels automatically;
> old export files still import. Verified by the full automated
> suite (141 tests, including migration seeds/load and legacy
> import). Pending: user verification in the macOS app.

## Post-MVP enhancement — Edit File (ADR-016)

> Status 2026-11-01: Implemented from the user's spec
> (`docs/EDIT_FILE_ENHANCEMENT.md`), all five phases: built-in
> editor (tabs, highlighting, find/replace, undo/redo), dirty
> state + Save / Don't Save / Cancel, Smart Save confirmation,
> external macOS editor with temp workspace + watched auto
> sync, and conflict detection (size + mtime) with a File
> Editor settings group. Verified by the automated suite
> (165 tests) and a live SFTP round trip against the SSH
> fixture. Pending: user verification in the macOS app per
> MANUAL_TEST_CHECKLIST (especially `open -a` launching and
> the real-editor save/watch cycle).
