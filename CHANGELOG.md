# Changelog

## Unreleased

- **Build stamp (ADR-019)** — the connection header now shows
  `build <git hash>` (release scripts stamp it automatically),
  and the input debug log's banner records the build and OS,
  so any screenshot or log file identifies exactly which build
  produced it.
- **Terminal cursor desync on resize (ADR-018)** — after the
  window (or the Explorer sidebar) changed the terminal's width
  while a long command line was wrapped, the text stayed intact
  but the cursor ended up back at the start of the line and
  later shell redraws landed on the wrong row: the buffer's
  resize reflow never tracked the cursor. The cursor is now
  anchored to its cell across reflows, and size changes are
  forwarded to the server debounced (one redraw per settled
  size instead of a storm while dragging).
- **Terminal typing corruption, round 3 (ADR-017)** — the
  release build could still drop the first character(s) after a
  platform text-buffer restart, or wipe a short command line
  when a phantom empty snapshot arrived (cursor jumping to the
  line start while typing e.g. `docker compose`). Restarts are
  now forwarded losslessly as fresh input, phantom empty
  snapshots are ignored, and the input buffer restarts at every
  submitted line (with an echo guard against late replays of
  the submitted line) so a desync can never reach further than
  the line being typed. Vietnamese Telex behaviour unchanged.
- **Edit File (ADR-016)** — edit remote files without leaving
  HeroTerm: **Edit** in the explorer's file menu opens a built-in
  editor (tabs beside the terminal tabs, syntax highlighting,
  line numbers, find & replace, undo/redo, ⌘S/⌘F/⌘W) and
  **Open With…** opens the file in a macOS app with watched
  auto-sync from a private temp workspace. Saves are
  conflict-checked (size + mtime) and never silently overwrite;
  closing a dirty file asks Save / Don't Save / Cancel; an
  a Save Confirmation (on by default) with Smart Save ("Don't
  ask again for this file" after 3 saves) lives in the new File Editor
  settings group (header gear), alongside the default editor,
  external application, Auto Sync and temp directory settings.
- **Shareable installer** (`scripts/package_macos.sh`): the
  packaging script now produces a recipient-ready
  `HeroTerm-<version>.dmg` — it auto-detects a Developer ID
  identity when one exists (ad-hoc with release entitlements
  otherwise), bundles a bilingual install guide covering the
  first-launch Gatekeeper steps, signs the .dmg itself when a
  Developer ID is available, and writes a SHA-256 checksum file
  next to the .dmg so recipients can verify the download.

- **One-command local install**: `scripts/install_macos.sh`
  builds the release app, signs it with a stable keychain
  identity when available (ad-hoc otherwise), and installs it
  into `/Applications` on the same Mac, replacing the previous
  copy.

- **Terminal typing diagnostics** (ADR-015): the ADR-014 fix
  did not fully cure the macOS typing corruption, so its
  mid-session buffer rebase is withdrawn, and an opt-in input
  log (⌘⇧L) now records the terminal's input/output event
  stream to `heroterm-input-log.txt` for diagnosis. Off by
  default; nothing is recorded while it is off.

- **Terminal typing fix** (ADR-014): typing could drop
  characters, jump the cursor to the line start, and split
  commands in two after the terminal lost and regained focus —
  the text-input tracking fell out of sync with the platform
  buffer and flooded the shell with backspaces. The input layer
  now resyncs whenever a new input connection opens, caps how
  much text a single edit can take back, and rebases its buffer
  at word boundaries.

- **Labels, appearance, cleaner session list** (ADR-013,
  user-directed revision of the profile spec): the fixed
  environment list and free-form tags are replaced by **Labels**
  — named, coloured, multiple per session — shown on each session
  item and filterable via chips under the search box. Existing
  environment/tags data migrates to labels automatically
  (Production stays red). Sessions and folders can pick an icon
  and a colour. The session item's `user@host` subtitle moved
  into a hover tooltip. Exports now carry labels by name; older
  export files still import.

- **SSH profile management** (spec:
  `docs/SSH_PROFILE_MANAGEMENT.md`, ADR-012): profiles gained an
  environment label (Production shows a full-word PRODUCTION
  badge), description and tags, and a last-attempt outcome;
  folders gained a type (Project/Client/Custom) and can be
  collapsed. Search covers description/tags/group name and
  combines with an environment filter. **Test Connection** is
  available in the profile form and the session menu.
  **Import/Export** writes versioned JSON with no secrets and no
  Keychain references; import validates strictly, previews
  duplicates, and offers Skip / Import as Copy / Update Existing.
  Duplicate now shares the original's Keychain reference (no
  secret copy) with copy-on-write secret edits, and is named
  `<name> Copy`. The editor warns instead of blocking when a key
  file is missing, and asks before discarding unsaved changes.
  Connection timeout range is now 1–120 s (default 15).
  (The environment label/filter and tags from this entry were
  later replaced by Labels — see ADR-013 above.)

- **Multi-session terminal tabs** (spec:
  `docs/MULTI_SESSION_TERMINAL_TABS.md`, ADR-011): keep several
  SSH sessions open at once, each in its own tab with a status
  indicator and an independent terminal buffer. A session picker
  panel (+ button or ⌘T) with search and folder groups opens new
  tabs and stays open for sequences; opening an already-open
  profile switches to its tab, with a deliberate "open another"
  action for duplicates (`name (n)` titles). Host-key/password
  prompts are serialized across tabs; the explorer and metrics
  footer follow the active tab; 12-tab limit; keyboard tab
  navigation (⌘1–9, Ctrl+Tab, ⌘⇧W closes a tab). The
  single-connection controller was replaced by a session manager;
  app shutdown closes all sessions (documented, no live-session
  persistence).

- **Remote Explorer table view** (spec:
  `docs/REMOTE_FILE_EXPLORER_TABLE_VIEW.md`, ADR-010): the listing
  is now a table with Name / Size / Last modified / Owner / Group /
  Permission columns. Header clicks sort (folders first, stable,
  client-side); column edges drag to resize and double-click to
  auto-fit; the sidebar itself is drag-resizable (260–720 px);
  sidebar and column widths persist across launches. Owner/Group
  show resolved account names when the server provides them via
  `/etc/passwd` + `/etc/group`, numeric IDs otherwise.
- Fixed: the Finder drag-and-drop target was never mounted in the
  widget tree (only the Upload button path was live); it now wraps
  the sidebar as designed in Milestone 5.
- Fixed: the explorer could stay unattached when a connection
  completed before the explorer's first frame.

## 1.0.0 — 2026-10-25

First MVP release (macOS).

- **Sessions:** SSH profiles in folders with search; strict
  per-field validation; metadata in local JSON, passwords and key
  passphrases in the macOS Keychain only; private keys referenced
  by path via a sandboxed file picker.
- **Terminal:** interactive PTY over SSH (dartssh2 + xterm, vendored
  with a fix for Vietnamese Telex IME composition); host-key
  first-use trust with SHA-256 fingerprint, changed keys blocked.
- **Remote Explorer:** SFTP sidebar that follows the terminal's
  working directory (OSC 7), breadcrumb + editable path bar with
  recent-folder history, rename/download/delete with confirmation
  and cancellable progress, Finder drag-and-drop upload (including
  folders) with collision handling, plus an Upload-button fallback.
- **Server metrics footer:** remote CPU (two-sample delta), memory
  (MemAvailable basis) and disk for `/`, polled every 4 s with
  stale/unavailable states — never fabricated values.
- **Polish (Milestone 7):** reconnect button + ⌘⇧C/⌘⇧D/⌘⇧R
  shortcuts, metrics "collecting" loading state, fixed an explorer
  header overflow, custom app icon and product name, DMG packaging
  script, security review, user guide and manual test checklist.

Known limitations: single connection at a time (no tabs), no port
forwarding or remote editor (post-MVP candidates); distribution
builds are not Developer-ID notarized yet — see `docs/RELEASE.md`.
