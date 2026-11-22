# Architecture Decision Records

Keep this file current. Add a dated decision entry whenever a significant choice changes.

## ADR-001 — Flutter desktop, macOS first

**Status:** Accepted

**Context:** The product is a desktop SSH client with a sidebar, terminal, remote file explorer, drag-and-drop, and server metrics. The initial target is MacBook/macOS.

**Decision:** Use Flutter/Dart and ship macOS first. Keep platform-specific behavior behind small interfaces where practical.

**Consequences:** macOS integration (Keychain, Finder drag-and-drop, app packaging) needs explicit verification. Cross-platform support is not an MVP release blocker.

## ADR-002 — Separate terminal UI from SSH transport

**Status:** Accepted

**Decision:** Use a terminal emulator widget for rendering and a separate SSH connection service for interactive PTY transport.

**Consequences:** A terminal package alone is insufficient. The integration must handle byte streams, terminal resize, keyboard/control sequences, and disposal.

## ADR-003 — SFTP for remote file operations

**Status:** Accepted

**Decision:** Use SFTP for listing, rename, delete, upload, and download whenever supported.

**Consequences:** File paths and names are not interpolated into shell commands. File operation errors and progress are surfaced as typed state.

## ADR-004 — Keychain for secrets and explicit host-key trust

**Status:** Accepted

**Decision:** Use macOS Keychain for passwords/passphrases or imported key material; require host-key verification and explicit trust.

**Consequences:** Session metadata stores credential references only. Unknown or changed host keys must never be silently accepted.

## ADR-005 — Metrics describe the remote host

**Status:** Accepted

**Decision:** Footer metrics are collected from the connected remote host. Poll every 3–5 seconds by default and stop on disconnect.

**Consequences:** Metrics can be unavailable on unsupported remote systems. Do not show placeholder numbers as live values.

## ADR-006 — Milestone 1 metadata persistence and private-key handling

**Status:** Accepted

**Decision:** Session and folder metadata is persisted as a single JSON document (`heroterm-sessions.json`) in the application support directory, written atomically (temp file + rename). A corrupt file is preserved as `.corrupt` and the library starts empty instead of crashing. Private keys are referenced by file path only; the app never copies or imports key material. Passwords and key passphrases are stored exclusively in the credential store (macOS Keychain) under an opaque `credentialRef`.

**Consequences:** No database dependency is needed at this scale; the repository interface (`SessionRepository`) keeps a future move to SQLite possible without touching UI or state code. Deleting a folder never deletes sessions: they move to Ungrouped and subfolders move up one level (documented behavior required by the Milestone 1 acceptance criteria).

## ADR-007 — macOS sandbox entitlements: network client + user-selected files

**Status:** Accepted

**Decision:** The app stays in the macOS App Sandbox, with these entitlements in both Debug and Release profiles: `com.apple.security.network.client` (outgoing SSH connections — its absence caused "Operation not permitted" on connect), `com.apple.security.network.server` (debug profile), and `com.apple.security.files.user-selected.read-only`. Private keys are picked through the system open panel (Browse… in the session editor): selecting a file is what grants the sandboxed app read access to it.

**Consequences:** Password authentication works out of the box. A key path typed by hand to a location the app has no grant for (for example `~/.ssh`) may be unreadable after an app restart; the connect flow detects this and tells the user to re-select the file via Browse…. If this proves too limiting in practice, revisit with security-scoped bookmarks or an explicit "import key into the app container" option (which would supersede ADR-006) before any App Store distribution work in Milestone 7.

## ADR-008 — Working-directory tracking via OSC 7 shell integration

**Status:** Accepted

**Decision:** On connect, the app installs a small hook function into the interactive shell (bash: prepended to `PROMPT_COMMAND`; zsh: registered with `add-zsh-hook precmd`). At every prompt the hook prints an OSC 7 report (`file://host/path`). The connection layer scans the shell's raw output for these reports and the Remote Explorer follows them. The user's own dotfiles are never modified; the hook lives only in the session's shell process.

**Fallback (documented):** Shells that do not run the hook (for example `sh`, `fish`, or a shell whose startup files replace `PROMPT_COMMAND`) produce no reports. If none arrives within 6 seconds of connecting, the explorer shows a notice that cwd tracking is unavailable and the user navigates manually; the explorer's own navigation never depends on the terminal. A separate exec channel cannot substitute, because it runs in the login directory, not the shell's.

**Consequences:** `cd`, `pushd`/`popd`, and any other directory change are all tracked uniformly because the report comes from `$PWD` at prompt time. Paths are percent-decoded (spaces and unicode work).

## ADR-009 — Vendored xterm with an IME input patch

**Status:** Accepted

**Decision:** The `xterm` dependency is vendored at `third_party/xterm` (version 4.0.0, MIT) with one local patch to `lib/src/ui/custom_text_edit.dart` (see `third_party/xterm/VENDORED.md`). Upstream inserted the full editing text on every IME commit and reset the platform editing state to empty afterwards, which destroys input-method state kept across keystrokes. With Vietnamese Telex on macOS this turned the toggle sequence `w` → `ư` → `w` into a duplicated `ưư` in the terminal. The patch diffs committed text snapshots (excluding the active composing region, whose covered tail is held rather than deleted) and never resets the platform editing state.

**Consequences:** Upgrades of xterm must re-apply or re-check this patch; `test/terminal_ime_test.dart` covers the regression (Telex toggle, diacritic composition, duplicate re-sends, backspace, and the reset-restart duplication sequence).

**ADR-007 addendum (Milestone 4):** The user-selected files entitlement is upgraded from `read-only` to `read-write` in both profiles, so the macOS save panel used for downloads grants write access to the location the user picks. Key-file picking still only reads.

## ADR-010 — Explorer table view, persisted UI layout, owner/group resolution

**Status:** Accepted (post-MVP enhancement, user's spec in `docs/REMOTE_FILE_EXPLORER_TABLE_VIEW.md`)

**Decision:** (1) The Remote Explorer listing is a table with Name/Size/Last modified/Owner/Group/Permission columns, replacing the two-line list tiles. Sorting is a single primary column, folders-first, stable, computed client-side from SFTP metadata (`sortEntries` in the explorer domain). (2) Owner/group names: SFTP attributes carry only numeric UID/GID. HeroTerm resolves names best-effort with one read-only exec per connection (`cat /etc/passwd` + `cat /etc/group`, parsed locally, cached in explorer state) and falls back to the numeric IDs when resolution fails or an ID has no account entry — names are never guessed. This is metadata decoration only; all file operations remain SFTP-only. (3) Sidebar width (260–720 px) and per-column widths persist in a dedicated `heroterm-ui.json` in Application Support (same atomic-write pattern as ADR-006), restored at startup. (4) While implementing this, two latent defects were found and fixed: the Finder drop target (`DropUploadRegion`) was never actually mounted in the widget tree — it is now wrapped around the sidebar in `AppShell` — and the explorer only attached on the connection-state edge it observed, so a connection completing before its first frame left it unattached; mounting while already connected now attaches directly.

**Consequences:** The table scrolls horizontally when wider than the sidebar instead of hiding columns. Column geometry lives in one spec table (`explorerColumnSpecs`). Tests: domain sort/parser/preference tests, controller sort/label tests, and a widget test driving the real table (columns render, header tap re-sorts).

## ADR-011 — Multi-session tabs: a session manager owns per-tab runtime sessions

**Status:** Accepted (post-MVP enhancement, user's spec in `docs/MULTI_SESSION_TERMINAL_TABS.md`)

**Decision:** (1) The single-connection `ConnectionNotifier` is replaced by a `SessionManagerNotifier` owning a list of runtime `TerminalTab`s. A tab is distinct from the saved `SshSession` profile (spec section 5): it carries a stable runtime ID, its own `RemoteConnection`, its own xterm `Terminal` buffer, its own cwd tracking and error/notice state, and no credentials — secrets are read from the Keychain per connect, exactly as before. (2) All tabs' `TerminalView`s stay mounted in an `IndexedStack`, so switching tabs never recreates a connection or loses scrollback; input/output/resize route by the tab's own wiring. Closing a tab is idempotent (generation counter + null-safe runtime teardown) and releases only that tab's connection; the right neighbour (else the left) becomes active. (3) Host-key and password prompts are **serialized through one queue** across all tabs, each prompt attributed to its tab: two tabs can never show competing dialogs, and a prompt whose attempt already failed (or whose tab closed) is dropped instead of shown stale. Host-key policy is unchanged and verified per connection. (4) Opening a profile that already has a tab activates that tab (spec 2.2); a deliberate "Open another session" action in the picker creates a duplicate, and duplicate tabs are titled `name (n)`. A hard cap of 12 tabs protects resources (spec section 7); beyond it, opening is refused with a visible notice. (5) The Remote Explorer and the metrics footer always bind to the **active** tab: the explorer re-attaches on tab switches, remembers each tab's last browsed directory, and the metrics poller re-targets its exec channel to the newly active tab. The historical single-connection state survives as a derived provider (`connectionProvider`) projecting the active tab, so header/footer/drop-target consumers keep their shape. (6) Documented limits, chosen deliberately: quitting the app closes all sessions without confirmation (live SSH sessions are never promised to survive exit); there is no close warning for tabs running foreground processes because that is not reliably detectable over SSH; tab order/identity is runtime-only and not persisted (no secrets are ever persisted — only the saved profiles).

**Consequences:** The M2 `connection_controller.dart` is deleted; its test suite became `test/terminal_sessions_test.dart` (10 tests: concurrent routing, duplicate handling, neighbour activation, per-tab failure isolation, serialized prompts, tab limit). A live check against the local SSH fixture ran two concurrent real sessions (independent shell markers, per-tab exec + SFTP, closing one leaves the other fully usable) — 8/8. The fixture itself needed a fix found along the way: its per-connection channel bookkeeping was stored in class attributes shared across transports, so stale exec channel IDs from earlier connections corrupted SFTP channels on reused IDs.

## ADR-012 — Profile management completion: environment labels, shared-ref duplicates, test connection, import/export

**Status:** Accepted (post-MVP enhancement, user's spec in `docs/SSH_PROFILE_MANAGEMENT.md`, feature SSH-PROFILE-001)

**Verified already compliant (unchanged):** CRUD + folders (incl. nesting, beyond the spec's flat minimum), JSON persistence across restarts (ADR-006 — the spec's SQLite mention in its section 10 is treated as a suggestion; the established JSON store already meets the persistence and security requirements, so no migration), Keychain-only secrets by reference, private key by path with `~/` expanded at use time, strict field validation, transport-level connection timeouts, delete confirmations, and secret deletion only when unreferenced.

**Decision:** (1) Profiles gain `environment` (production/staging/development/other — an independent label, never derived from the group; legacy profiles load as `other`, the editor defaults new ones to development), `description` (≤500), `tags` (normalized: trimmed, case-insensitively deduplicated, capped), and `lastConnectionStatus` (success/failed outcome only). Folders gain a `type` (project/client/custom; legacy = custom). Search now also covers description, tags and group name, and combines with an environment filter. (2) **Duplicate semantics changed** to the spec's shared-reference option: a duplicate shares the original's Keychain reference (no second copy of the secret is created), is named `<name> Copy` with numeric suffixes, and opens in the editor for review. Safety comes from copy-on-write in `updateSession` (replacing/removing a secret on a profile whose reference is shared writes a fresh reference or detaches only that profile) plus the existing delete guard — so sharing can never leak an edit into, or delete a secret from, another profile. (3) Connection timeout range aligned to the spec: **1–120 s, default 15** (was 1–600/20). Profiles saved earlier with a longer timeout keep working but are flagged by validation when edited. (4) A missing private-key file is now a **warning** in the editor, not a save blocker (spec section 8); connecting and Test Connection still fail with the actionable error until the file is readable. (5) **Test Connection** (`SshConnectionTester`) runs a real connect through the normal SSH service — same host-key verification, prompts and profile timeout — then closes immediately; it is offered in the editor (on the unsaved draft) and in the session menu, and reports the typed, secret-free error. (6) **Import/Export** uses the spec's versioned JSON (`schemaVersion: 1`): export strips secrets AND Keychain reference IDs and embeds groups as `{name, type}`; import is strict (2 MB / 500-profile limits, schema, type, enum and range validation — malformed files are rejected whole with a readable reason), shows a preview with per-profile New/Duplicate status, and applies one of Skip / Import as Copy / Update Existing. The conflict identity is name+host+username+port (never host alone); groups match by name+type; Update preserves the existing profile's ID and stored credential; imported profiles never auto-connect. (7) The editor gained an unsaved-changes guard (confirm before discarding) and folder groups can be collapsed in the sidebar.

**Consequences:** One deliberate deviation: duplicate saves immediately and then opens the editor (the spec's "open the editor before saving" would need an unsaved-draft editor mode; the review intent is met without it). The M1 test asserting duplicate-copies-secret was rewritten to the shared-reference semantics.

## ADR-013 — Labels replace environment + tags; per-item appearance; endpoint moves to tooltip

**Status:** Accepted 2026-10-25 (user-directed revision of ADR-012 parts). **Supersedes:** the environment field, environment filter chips, PRODUCTION badge, and free-form tags from ADR-012. Everything else in ADR-012 (shared-reference duplicate, Test Connection, import/export discipline, timeout range, key warning, discard guard) stands.

**Context:** After using the profile-management build, the user found two parallel classification systems (folders AND environment filter AND name prefixes) redundant, and tags half-finished (searchable but displayed nowhere, with no filter of their own). They directed a merge into ONE concept, **Labels**, and asked for per-item icons/colours plus a cleaner session list.

**Decision:**
1. **Labels**: a library-level entity `SessionLabel {id, name, colorValue}`. A session carries any number of label IDs. Labels show as coloured pills on the session item, filter via coloured chips under the search box (a session must carry ALL selected labels), are assigned/created from the session editor, and are managed (rename/recolour/delete — delete detaches everywhere) from a label manager dialog.
2. **Removed**: `SshSession.environment`, the `SshEnvironment` enum, the PRODUCTION/STAGING/DEV badges, the environment filter chips, and the `tags` field. The only capability lost is the *automatic* production warning: a red "Production" label is a user discipline now, which the user explicitly accepted in exchange for one classification system.
3. **Migration is automatic and lossless**: on load, the repository extracts each legacy profile's environment (except `other`) and tags as label names; the controller creates the labels (Production keeps red `0xFFD32F2F`, Staging orange, Development blue; other names get a stable palette colour), assigns them, and persists the migrated library once. Import files written by older exports (with `environment`/`tags`) are honoured the same way; new exports write `labels` (names, like groups) plus `icon`/`colorValue`.
4. **Appearance**: sessions and folders each gain an optional curated icon (stored by string ID from an 18-icon set) and an optional ARGB colour from a 10-colour palette shared with labels. Icons/colours render in the sidebar, the tab picker, and the tab strip.
5. **Session list subtitle removed**: `username@host:port · Last: …` no longer renders under every session name; the same text is the item's hover tooltip. The tab picker keeps its endpoint subtitle (choosing the right server is its job).

**Consequences:** The library JSON gains a top-level `labels` array and per-session `labelIds`/`icon`/`colorValue`; `environment`/`tags` keys are no longer written. Search still covers label names (via the caller-supplied names), description and group name.

## ADR-014 — Fix terminal input desync: resync on connection restart, bounded take-back, word-boundary rebase

**Status:** Accepted 2026-10-26. **Amends:** ADR-009 (the vendored xterm IME patch). **Reported from macOS:** typing ordinary commands dropped characters, the cursor jumped to the start of the line, text overlapped, and commands were split mid-word (a screenshot shows `docker compose build queue` executed and `-worker` then run as its own command).

**Root cause (found by code inspection of the ADR-009 patch):** the patch diffs consecutive committed-text snapshots in the platform text buffer, which is only valid while both sides agree on the buffer's content. They stopped agreeing whenever the buffer restarted: `_openInputConnection()` pushes the initial (empty) editing state to every NEW connection — connections are closed on focus loss and reopened on focus gain (clicking the explorer/sidebar, dialogs, tab/app switches) — but `_committedText` was never reset, so the next keystroke was diffed against the entire typing history of the dead buffer. A character matching the history's prefix was swallowed (dropped characters), and the "removed" remainder was emitted as one backspace per character — a flood that deleted the shell's current input line mid-typing (cursor to line start, line cut in two, remainder submitted as a separate command). The same unbounded flood applied to any large divergence between snapshots.

**Decision:** Keep the ADR-009 design (diff committed snapshots, never reset per commit — that is what keeps stateful IMEs like Vietnamese Telex working) and harden it in `third_party/xterm/lib/src/ui/custom_text_edit.dart`:
1. **Resync at provable restarts**: opening a new input connection and `connectionClosed()` reset the tracking to the initial state; `setEditingState` keeps tracking in sync with what it pushes.
2. **Bounded take-back**: divergences whose removed tail exceeds 8 runes (a Vietnamese syllable is ≤ ~7) are a resync — adopt the new snapshot, emit nothing — never a backspace flood. Small IME corrections still diff normally.
3. **Word-boundary rebase**: once the committed buffer exceeds 128 characters, the next commit ending at a word boundary (space/newline, no composition active) rebases the platform buffer to empty, bounding both the per-keystroke diff cost and any residual desync. Rebasing only at word boundaries avoids upstream's failure mode (resetting mid-word restarted the IM and broke the Telex `w` toggle).

**Consequences:** Worst case after an unexpected in-connection restart is one swallowed update, not a destroyed input line. Three regression tests added (focus round-trip, large-divergence resync, long-buffer rebase); full suite 144 tests pass. The change is input-path only — nothing about SSH transport, rendering, or resize handling changed.

## ADR-015 — Typing corruption persists after ADR-014: withdraw the rebase, add opt-in input diagnostics

**Status:** Accepted 2026-10-26. **Amends:** ADR-014. **Second user report (macOS, same day):** after several `cd` commands typed fine, typing `nano` broke at the first letter — cursor jumped to the line start; a screenshot shows `na: command not found` executed and the fresh prompt line overwritten at its first columns.

**Assessment:** ADR-014's connection-open resync and take-back bound are kept (both are provably-correct sync properties and cap the worst case), but they did not eliminate the corruption, so the primary trigger is something the snapshot-diff model still mishandles in the real macOS event stream — which cannot be reproduced on the Linux dev VM (the macOS TextInputPlugin's exact update sequences are not observable there, and widget tests drive a simulated platform). Rather than guess a third time, this ADR (a) removes the one ADR-014 addition that itself mutates platform state mid-session, and (b) adds real instrumentation so the next report carries the actual event stream.

**Decision:**
1. **Withdraw the word-boundary rebase** (`_rebaseIfLong`). It was the only ADR-014 change that calls `setEditingState` mid-session — the same class of intervention that caused the original upstream Telex failure — making it a live suspect for the remaining desync (e.g. if the macOS plugin answers it with updates computed from its pre- or post-rebase model at unexpected times). The buffer grows unboundedly again; diff cost stays acceptable for interactive sessions, and the 8-rune take-back bound still caps desync damage.
2. **Opt-in input diagnostics**: pressing **⌘⇧L** toggles recording to `heroterm-input-log.txt` in Application Support (off by default, nothing is written while off). The vendored `CustomTextEdit` reports through a static `debugLog` sink (null in normal use): connection open/show/close events, every `updateEditingValue` (full text, composing range, selection, tracked length), every emitted insert/delete, and every `performAction`. The app additionally logs terminal→shell bytes (`OUT`), shell→terminal chunks (`IN`), and `RESIZE` events with millisecond timestamps (`lib/core/debug/input_debug_log.dart`, wired in `main.dart`, the session manager, and the AppShell shortcut). The file's start banner and the toggle snackbar both warn that typed content is recorded and passwords must not be typed while it is on; the file never leaves the user's machine unless they send it.
3. **Diagnosis protocol for the next report:** first localize with `cat` on the server (raw tty echo, no readline): corruption under `cat` incriminates the client input path; clean `cat` with a corrupting bash prompt incriminates the redraw/resize interaction. Then reproduce once with the log on and analyse the event stream around the corruption before changing the input model again.

**Consequences:** One deliberate, documented exception to the "no logging in lib" audit line: user-initiated diagnostics, off by default (see SECURITY_REVIEW). `package:xterm` now also exports `src/ui/custom_text_edit.dart` so the app can wire the sink and reuse its log escaping.

## ADR-016 — Edit File: built-in + external editors over SFTP (spec: EDIT_FILE_ENHANCEMENT)

**Status:** Accepted 2026-11-01. **Spec:** `docs/EDIT_FILE_ENHANCEMENT.md` (all five phases). The user delegated the design choices; the interpretations below are the ones implemented and are called out for review.

**Decision:**
1. **One tab strip, two document kinds.** Editor documents (built-in and external) render as chips beside terminal tabs in the existing tab strip; the workspace shows an editor surface while a document is active and returns to the terminal on terminal-tab activation or ⌘1–9. A separate `EditorNotifier` owns documents, keyed by (kind, terminal tab, remote path) — re-opening a file activates its document instead of duplicating it. Documents survive their terminal tab disconnecting/closing: content is never discarded, only saving needs the connection (spec §4).
2. **Built-in editor** (`lib/features/file_editor/`): files load through new `RemoteFileService` byte APIs (`stat`, `readBytes` with a hard cap, `writeBytes`). Guards per spec §4: 2 MB ceiling, NUL-byte binary sniff, strict UTF-8 decode (malformed input is refused, never lossy-decoded), UTF-8 BOM round-tripped. The pane is a `TextField` over a `HighlightingController` (single-pass scanner: comments/strings/numbers/keywords/key–value heads/tags/markdown headings for the spec's format list), a scroll-synced line-number gutter, find & replace with match highlighting, undo/redo via `UndoHistoryController`, ⌘S/⌘F/⌘W.
3. **Conflict detection on every save** (spec Phase 5, pulled into the save pipeline from the start): size + mtime captured at load and after each save; a mismatch blocks the write and offers Overwrite / Reload remote / Cancel. A failed save keeps content and the dirty flag.
4. **Two confirmations, kept distinct** (spec §2.5): the *before-save confirmation* (Settings → Save Confirmation) and the *unsaved-changes warning* on close (Save / Don't Save / Cancel, §2.4), which is never skippable. **Amendment (user acceptance, 2026-11-01):** the save confirmation is **ON by default** — the spec's baseline behaviour and the premise of Smart Save; the first implementation shipped it default-off by the implementer's judgement, which made the confirmation (and Smart Save's counting) invisible in acceptance testing. A stored value only counts as OFF once the user has actually toggled it (`saveConfirmConfigured`), so installs that merely carry the first build's default get the confirmation without a settings reset. Smart Save counts confirmed successful saves per **profile + remote path**; at 3, a one-time prompt offers "Don't Ask Again for This File"; records persist in `heroterm-ui.json` and are manageable in Settings ("Ask again").
5. **External editor**: download streams to a per-document temp workspace `<temp>/HeroTerm/<docId>/` (directory `chmod 700`; Temp Directory setting overrides the root), launched via `open -a <app>` behind an `ExternalEditorRuntime` interface. Watching targets the **directory**, not the file, so rename-based saves are seen; a change is reported only after debounce (700 ms) plus a stability window (350 ms, size+mtime unchanged). Auto Sync (default on) uploads through the same conflict-checked pipeline; failures keep the temp file and flag the document. Clean close deletes the temp file; a dirty close offers Sync / Discard / Cancel — unsynced content is never deleted silently.
6. **Settings** live in `UiPreferences` (same JSON store, backward-compatible defaults): a new File Editor group (default editor, external application, Auto Sync, Save Confirmation, Smart Save, Temp Directory) behind a gear in the connection header. Double-clicking a file row opens the **default editor**; folders deliberately keep no double-click handler so single-click navigation stays instant.
7. **Explorer integration**: file context menu gains **Edit** and **Open With…** (detected macOS editors + custom name/path + optional "set as default"). No file content is ever logged (SECURITY_REVIEW extended for temp files).

**Consequences:** `RemoteFileService` grows three methods (both test fakes updated). The highlighter is intentionally not a parser — good enough for config/code reading, and plain text can never be mis-tokenised into a crash. External-app launching (`open -a`) and the app-detection list are macOS behaviours that cannot be exercised on the Linux VM; they are covered by unit tests at the runtime seam and listed in MANUAL_TEST_CHECKLIST for Mac acceptance. Quitting the app with dirty editor documents is **not** guarded (macOS window-close interception needs platform work) — documents' unsaved text is lost on quit, same as unsaved terminal scrollback decisions in ADR-011; noted for a future phase.

## ADR-017 — Typing corruption round 3: lossless restarts, buffer rebased at line submission

**Context.** 2026-11-08, user report: the release build installed from the DMG still shows the round-1/2 symptoms — typing `docker compose` corrupts the line, cursor back at the line start — while a debug run does not. The ADR-015 diagnostic log was never captured, so the design constraint for this round is: stop depending on identifying the exact platform trigger; make every desync artefact the platform can produce *lossless by construction*. Code review of the ADR-014/015 diff engine found the remaining holes:

1. **Mid-connection buffer restarts swallow characters.** A restart that does not close the connection (so `connectionClosed` never fires) diverges against the accumulated baseline; ADR-014/015 resynced silently and dropped the retyped characters — the "first letter of the command breaks" report was this, codified in a test.
2. **A phantom empty snapshot wipes a short line.** A single update dropping a ≤ 8-rune line to `""` took the shrink path and emitted one backspace per character.
3. **The baseline grows for the whole connection.** Since ADR-015 withdrew the rebase, `_committedText` accumulates every line typed since connect; each artefact diverges against more history, and release builds (faster event flow, longer real sessions than a debug smoke test) hit the artefacts far more often.

**Decision.** Four changes in the vendored `custom_text_edit.dart`, all preserving the ADR-009 Telex behaviour and the ≤ 8-rune take-back bound for genuine tail edits (backspace, IME corrections):

1. **Restart = forward, never delete.** A divergence whose common prefix is far from the tail (or which shares no prefix while removing ≥ 3 runes) cannot be a keystroke — genuine edits only touch the tail. The new snapshot is forwarded whole as fresh input and adopted as the baseline. A large pure shrink whose surviving snapshot is short (≤ 8 runes) is treated the same (a restart's first snapshot whose first character coincides with the line's first character is shaped like a shrink); a large shrink to a long prefix still resyncs silently (replay/coalesced-burst artefact — the shell already shows that text).
2. **Phantom empty snapshots are ignored** when the baseline holds more than one rune: no adoption, no backspaces. The final backspace of a line (baseline of 1) still deletes normally.
3. **The buffer is rebased at line submission.** `performAction` (with no composition in flight) and any emitted insert containing a newline restart the platform buffer via `setEditingState`, so the baseline only ever holds the line currently being typed. This is not the ADR-015-withdrawn rebase: that one fired at word boundaries *mid-line, mid-typing*; this one fires once per submitted command, at the moment the shell consumes the line — the same boundary upstream resets at, moved from per-commit to per-line.
4. **Echo guard.** The submitted line's text is remembered across the rebase; a late platform update replaying it exactly is swallowed, and one coalesced with fresh typing has the submitted prefix stripped. Any unrelated value expires the guard; it is also cleared on connection open/close.

**Consequences.** The ADR-015 opt-in input log gains RESTART / PHANTOM / REBASE / ECHO lines, so a recurrence (if any) arrives with the artefact classified. Widget tests simulate restarts, phantom snapshots, and both Enter paths (action and in-text newline) against `TestTextInput`; the ADR-014 test that codified the swallow now asserts forwarding. What remains unobservable from the Linux VM is the macOS plugin's actual artefact stream — verification is the user's release-build typing pass in MANUAL_TEST_CHECKLIST.

## ADR-018 — Typing corruption round 4: the cursor is lost on terminal resize (reflow), not in the input stream

**Context.** 2026-11-08, after ADR-017: the user reports the cursor at the START of the prompt row again — but this time the typed text (`docker compose`, on a 65-cell prompt) is completely intact: no dropped characters, no backspace damage. Pixel measurement of the screenshot confirms the block cursor sits on the command row itself, column 0. So the input path (ADR-017) is holding; the desync is between the terminal buffer's cursor and the shell's model of it. Investigation, all reproduced in the VM:

1. Real bash/readline streams captured from a pty: plain appends while typing; after SIGWINCH a redraw `\r ESC[K \r <prompt+line>` (plus cursor-up + erase per previously wrapped segment when growing). Every well-formed stream leaves the cursor at the end of the line — bash never strands it at column 0 on its own.
2. The vendored buffer's `resize()` reflows wrapped lines but only CLAMPS the cursor (and clamps it once mid-method, before the reflow). Reproduced with the vendored `Terminal` alone: type a 54-cell line at width 40 (wraps), grow to 80 — the line merges into row 0 but the cursor stays at (14, 1), an empty row; bash's redraw then writes a DUPLICATE prompt line onto the wrong row. Shrink 80→50 with a 59-cell line: the cursor clamps to (49, 0), inside the text. Any width change with wrapped (or formerly wrapped) content desyncs the buffer cursor from the shell's model, and every later redraw compounds it — a redraw caught mid-flight, or a stranded cursor after an interleaved second resize, is exactly the reported frame.
3. Resizes are not exotic in this app: window drag/maximise/snap, dragging the Explorer sidebar (260–720 px), and the layout settle right after connect all change the column count, and HeroTerm forwarded every intermediate cell size to the server immediately — one SIGWINCH + redraw per step.

**Decision.**

1. **Anchor the cursor across reflow** (vendored `buffer.dart`): `Buffer.resize` captures a `CellAnchor` at the cursor BEFORE any adjustment (the mid-method clamp would otherwise destroy the offset first), lets the reflow engine reparent it through copies/merges (the machinery already existed for selection anchors), and restores `_cursorX/_cursorY` from the anchor's new line afterwards. Falls back to the upstream clamp when the anchor cannot be captured or its line disappears. Alt buffer unaffected (no reflow there).
2. **Debounce + dedupe the SSH window-change** (app side, `terminal_sessions.dart`): the local buffer still resizes instantly with the layout, but the server receives the first size immediately and later changes only after 120 ms of stability, skipping duplicates — one SIGWINCH/redraw per settled size instead of a storm.

**Consequences.** Regression tests (`test/terminal_reflow_cursor_test.dart`) drive the vendored terminal with the captured bash streams: grow keeps the cursor on its cell and the redraw lands on the same row with no duplicate line; shrink keeps the cursor on its cell in the second segment; a no-wrap resize leaves the cursor put. A known joint artifact remains out of scope: narrowing mid-line makes bash's redraw (which homes on the cursor's current row) leave one stale segment row — every reflowing terminal behaves this way; the shell recovers on the next redraw/Ctrl+L. The ADR-015 log's RESIZE lines now show exactly which sizes were forwarded, so a further recurrence can be classified from one reproduction.

## ADR-019 — Builds must identify themselves; no further typing fix without the captured event stream

**Context.** The typing saga is at five user reports and four mechanism fixes (ADR-014/015/017/018), each reproduced and test-covered in the VM — yet the user still sees the corruption on their Mac. Two observability gaps made every round slower than it should have been: (1) every build identifies as version `1.0.0+1`, so neither the user nor a screenshot can prove which commit an installed app was built from — a stale-install false trail cannot be excluded; (2) the ADR-015 event log, the one artifact that shows the actual macOS TextInputPlugin stream, has been requested in three rounds and never captured, so each fix targeted a mechanism PROVEN possible rather than the one PROVEN active on the user's machine.

**Decision.**

1. **Build stamp.** `lib/build_info.dart` exposes `buildId` from `--dart-define=BUILD_ID=...`; both release scripts pass the current git short hash. The stamp shows in the connection header (`build <hash>`) and in the input log's start banner (with the OS), so every screenshot and log file names its build. Plain `flutter run` shows `dev`.
2. **Data before the next fix.** No further change to the input path ships on inference alone. The next round starts from one of two user-supplied artifacts: the ⌘⇧L event log of one reproduction, or the `cat` discriminator (type a long line into `cat`: corruption there = the input stream itself; clean there but corrupted at the prompt = the shell-redraw/display side). This is a deliberate stop on speculative fixing, recorded so a future session does not restart the guessing cycle.

**Consequences.** The header gains a small permanent caption. When the log arrives, its banner's build hash ties it to an exact commit, and its RESIZE/UEV/EMIT/OUT/IN lines classify the active mechanism in one pass.
