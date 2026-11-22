# HeroTerm

A Flutter desktop SSH client for **macOS and Windows**, inspired by the
practical workflow of MobaXterm: save your servers once, then connect,
run commands, and manage remote files from one window.

- **Version:** 1.0.0 (first MVP release, 2026-10-25) — everything after
  that is collected under *Unreleased* in [`CHANGELOG.md`](CHANGELOG.md)
  until the next version is cut.
- **Platforms:** macOS (primary) and Windows. Linux is not built yet.
- **Stack:** Flutter 3.47.8 / Dart 3.13.7, Riverpod, dartssh2, and a
  vendored xterm 4.0.0 (see *Terminal* below).
- **Repositories:** GitLab (primary) —
  <https://gitlab.com/hunghs2204/heroterm> · GitHub (public mirror) —
  <https://github.com/herohoang/heroterm>

## Features

### Sessions & profiles

- SSH profiles organised in user-created **folders** (Project / Client /
  Custom types, collapsible), with search across name, host, description
  and labels.
- **Labels** — named, coloured, several per session — with filter chips;
  sessions and folders can also carry a custom icon and colour
  (ADR-013).
- Password or private-key authentication; connection timeout 1–120 s
  (default 15 s); optional startup directory per profile.
- **Test Connection** from the profile form and the session menu.
- **Duplicate** profiles share the original's stored secret (no copy)
  with copy-on-write when the secret is edited.
- **Import / Export** as versioned JSON — strictly validated, with a
  duplicate preview (Skip / Import as Copy / Update Existing). Export
  files never contain passwords, passphrases, or Keychain references.
- Per-field validation in the editor, a discard-changes guard, and a
  warning (not a block) when a referenced key file is missing.

### Terminal

- Interactive PTY over SSH (dartssh2 + xterm), `xterm-256color`,
  10,000-line scrollback, reconnect button and shortcuts
  (⌘⇧C connect, ⌘⇧D disconnect, ⌘⇧R reconnect on macOS; Ctrl equivalents
  on Windows).
- **Multi-session tabs** (ADR-011): up to 12 concurrent sessions, each
  with its own connection, terminal buffer and working-directory
  tracking; a session picker (⌘T / Ctrl+T) with search and folder
  groups; host-key and password prompts are serialised across tabs;
  keyboard navigation (⌘1–9, Ctrl+Tab, ⌘⇧W closes a tab).
- **Host-key safety:** first-use trust dialog with the SHA-256
  fingerprint; a changed host key blocks the connection.
- **Vietnamese IME support** on macOS (Telex composition) via the
  vendored xterm input patches; terminal input runs on the platform
  **delta model** (ADR-020) after a long investigation into typing
  corruption (ADR-014…019). On Windows, input uses hardware keyboard
  events instead (ADR-023), and Vietnamese works through Unikey/EVKey.
- **MobaXterm-style syntax highlighting** (ADR-024): plain shell output
  is coloured at paint time — links underlined, IPv4 addresses pink,
  percentages/sizes amber, numbers pale yellow, error / warning /
  success / info keywords in level colours. Colours a program sets
  itself (ANSI) are never overridden, full-screen apps (vim, htop) are
  untouched, and the feature can be toggled in
  Settings → Terminal → Syntax highlighting.
- Opt-in input diagnostics log (⌘⇧L / Ctrl+⇧L) for troubleshooting
  typing issues; off by default. Release builds stamp the header with
  `build <git hash>` (ADR-019) so screenshots identify their build.

### Remote Explorer (SFTP)

- Sidebar file browser that **follows the terminal's working
  directory** (OSC 7 shell integration, ADR-008; can be paused), with
  breadcrumb navigation, an editable path bar with recent-folder
  history, a `..` parent row, hidden-file toggle and refresh.
- **Table view** (ADR-010): Name / Size / Last modified / Owner /
  Group / Permission columns; header-click sorting (folders first),
  drag-resizable columns with double-click auto-fit, a drag-resizable
  sidebar (260–720 px), and layout persisted across launches.
  Owner/Group show account names resolved from the server's
  `/etc/passwd` + `/etc/group` when available, numeric IDs otherwise.
- **File actions:** Rename, Delete (recursive for folders, with
  confirmation), Download with progress and cancel, New Folder,
  Edit / Open With… (below).
- **Drag-and-drop upload** from Finder/Explorer (files and folders)
  with collision handling (Overwrite / Rename / Skip), plus an Upload
  button fallback.
- Failed navigation or operations keep the previous path and listing
  on screen and surface the error with Retry — the explorer never
  blanks or pretends a path changed.

### Edit remote files (ADR-016)

- **Edit** opens a built-in editor in tabs beside the terminal tabs:
  syntax highlighting, line numbers, find & replace, undo/redo,
  ⌘S / ⌘F / ⌘W. Files up to 2 MB; strict UTF-8 with BOM round-trip;
  binary files are refused.
- **Open With…** opens the file in an external app (VS Code, Cursor,
  Sublime Text, Notepad++, Zed, Notepad, or the OS default handler)
  from a private temp workspace, with watched **Auto Sync** back to
  the server on save.
- Saves are **conflict-checked** (size + mtime) — Overwrite / Reload /
  Cancel, never a silent overwrite. Closing a dirty file asks
  Save / Don't Save / Cancel.
- **Save Confirmation** (on by default) with Smart Save: after 3
  saves of the same file you can choose "Don't ask again for this
  file". Editor preferences live in Settings (header gear icon).

### Server metrics footer

- Remote **CPU** (two-sample delta), **memory** (MemAvailable basis)
  and **disk** usage for `/`, polled every 4 s over a read-only exec
  channel, with explicit stale / unavailable / collecting states —
  values are never fabricated (ADR-005).

### Security model

- Session metadata lives in one JSON file in the app's support
  directory (atomic writes). **Passwords and key passphrases are
  never written to that file** — they go to the macOS Keychain /
  Windows Credential Manager (DPAPI) via flutter_secure_storage,
  referenced by an opaque id. Private keys are referenced by path
  only, chosen through the OS file picker.
- All file operations are pure SFTP — no shell string interpolation.
  See [`docs/SECURITY.md`](docs/SECURITY.md) and
  [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md).

## Installation

Builds are currently **unsigned** (no paid Apple Developer / Windows
code-signing certificate yet), so first launch shows the platform's
"unidentified developer" flow. Details and the notarization plan are
in [`docs/RELEASE.md`](docs/RELEASE.md).

### macOS

- **Shareable DMG:** `./scripts/package_macos.sh` produces
  `build/macos/HeroTerm-<version>.dmg` (universal binary) plus a
  `.sha256` checksum and a bilingual install guide inside the DMG.
  On macOS 15+, open a blocked app via System Settings →
  Privacy & Security → "Open Anyway", or run
  `xattr -dr com.apple.quarantine /Applications/HeroTerm.app`.
- **Install on your own Mac:** `./scripts/install_macos.sh --open`
  builds the release app, signs it (a stable keychain identity when
  available, ad-hoc otherwise), installs it into `/Applications`
  and launches it.

### Windows

Windows builds require a Windows host with Flutter and Visual
Studio 2022 ("Desktop development with C++" workload).

- **Installer (recommended):** install Inno Setup 6
  (`winget install JRSoftware.InnoSetup`), then run
  `powershell -ExecutionPolicy Bypass -File scripts\package_windows_installer.ps1`
  → `build\windows\HeroTerm-<version>-setup.exe` (+ `.sha256`).
  Per-user install into `%LOCALAPPDATA%\Programs\HeroTerm` (no admin
  prompt), Start Menu shortcut, optional desktop shortcut,
  launch-after-install, and a standard uninstaller that keeps
  `%APPDATA%\HeroTerm` (sessions and settings survive).
- **Portable zip:** `scripts\package_windows.ps1` →
  `build\windows\HeroTerm-<version>-windows-x64.zip` (+ `.sha256`).
  Extract and run `HeroTerm.exe` in place, next to its DLLs.
- SmartScreen warns on first run for both ("More info" →
  "Run anyway") until a code-signing certificate is available.

## Build from source

```sh
flutter pub get
flutter run -d macos      # or: flutter run -d windows
flutter build macos --release
flutter build windows --release
```

Quality gates (all must pass before a change lands):

```sh
dart format .
flutter analyze
flutter test              # 196 tests
```

## Repository layout

```
lib/            App code, organised by feature
                (sessions, connection, remote_explorer,
                file_editor, plus app/ shell, theme and
                preferences, and core/ errors + security)
test/           Unit and widget tests (26 files)
third_party/    Vendored xterm 4.0.0 with local patches —
                read third_party/xterm/VENDORED.md before touching
docs/           Specs, architecture, ADRs, guides (index below)
scripts/        Packaging: package_macos.sh, install_macos.sh,
                package_windows.ps1, package_windows_installer.ps1
installer/      Inno Setup script (HeroTerm.iss)
macos/ windows/ Platform runners
```

## Documentation

Start with [`AGENT.md`](AGENT.md) before asking a coding agent to
modify this project, then:

| Document | Contents |
| --- | --- |
| [`ROADMAP.md`](ROADMAP.md) | Milestones M0–M7 and post-MVP enhancements, with status |
| [`docs/FEATURE_SPEC.md`](docs/FEATURE_SPEC.md) | User-visible behaviour |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Boundaries and data flow |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | ADR-001…ADR-024, the technical decision log |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Local setup and quality gates |
| [`docs/RELEASE.md`](docs/RELEASE.md) | Packaging, signing, notarization plan, Windows build |
| [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) | End-user guide |
| [`docs/MANUAL_TEST_CHECKLIST.md`](docs/MANUAL_TEST_CHECKLIST.md) | Manual acceptance checklist |
| [`docs/SECURITY.md`](docs/SECURITY.md) / [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) | Security model and threats |
| [`CHANGELOG.md`](CHANGELOG.md) | Full changelog (canonical) |

Feature specs that drove the larger post-MVP work live alongside the
docs: `docs/REMOTE_FILE_EXPLORER_TABLE_VIEW.md`,
`docs/MULTI_SESSION_TERMINAL_TABS.md`,
`docs/SSH_PROFILE_MANAGEMENT.md`, `docs/EDIT_FILE_ENHANCEMENT.md`.

## Changelog

Canonical, detailed notes are in [`CHANGELOG.md`](CHANGELOG.md).
Summary by version:

### Unreleased (after 1.0.0)

- **Remote Explorer table view** (2026-10-25, ADR-010) — 6-column
  sortable/resizable table, persisted layout, owner/group name
  resolution; also mounted the previously dead drag-and-drop target
  and fixed an explorer attach race.
- **Multi-session terminal tabs** (2026-10-25, ADR-011) — see
  *Terminal* above.
- **SSH profile management** (2026-10-25, ADR-012) — Test Connection,
  strict Import/Export, shared-secret duplicates, folder types,
  last-attempt status.
- **Labels & appearance** (2026-10-25, ADR-013) — Labels replace the
  earlier environment + tags model (existing data migrates
  automatically); custom icons/colours for sessions and folders.
- **Terminal typing fixes** (2026-10-26 → 2026-11-08, ADR-014…020) —
  the macOS typing-corruption saga (dropped characters, cursor
  jumping to line start) closed by moving the input adapter to the
  delta model, anchoring the cursor across resize reflows, adding
  the ⌘⇧L diagnostics log and the `build <git hash>` stamp.
- **One-command macOS install** (2026-10-26) —
  `scripts/install_macos.sh`.
- **Shareable DMG** (2026-10-31) — recipient-ready installer image
  with bilingual guide and SHA-256 checksum.
- **Edit File** (2026-11-01, ADR-016) — built-in editor + external
  editor with Auto Sync, conflict-checked saves, Save Confirmation
  on by default with Smart Save.
- **Windows build target** (2026-11-16, ADR-021) — branded
  `HeroTerm.exe` runner and icon, external-editor flow ported,
  portable-zip packaging script.
- **Windows installer** (2026-11-20, ADR-022) — Inno Setup 6
  per-user setup program (see *Installation*).
- **Windows typing & paste fix** (2026-11-20, ADR-023) — hardware
  keyboard input on Windows; shell-integration writes are
  quiescence-gated so they can no longer interleave with a fast
  paste and garble the input line.
- **MobaXterm-style syntax highlighting** (2026-11-20, ADR-024) —
  see *Terminal* above.
- **Fixed: folder created on an empty library never appeared**
  (2026-11-20) — the sidebar empty state keyed on sessions alone
  and hid a new folder until the first session existed.
- **Fixed: an empty folder hid the ".." parent row** (2026-11-22) —
  the explorer's empty notice replaced the whole table and
  swallowed the parent row; it is now an item of the same list.

### 1.0.0 — 2026-10-25

First MVP release (macOS), milestones M0–M7:

- **Sessions:** SSH profiles in folders with search and strict
  per-field validation; metadata in local JSON, secrets in the
  macOS Keychain only; private keys by path via a sandboxed picker.
- **Terminal:** interactive PTY (dartssh2 + vendored xterm with the
  Vietnamese Telex IME fix); host-key first-use trust with SHA-256
  fingerprint, changed keys blocked.
- **Remote Explorer:** SFTP sidebar following the terminal's
  working directory (OSC 7); breadcrumbs + editable path bar with
  history; rename / download / delete with confirmation and
  cancellable progress; Finder drag-and-drop upload (including
  folders) with collision handling.
- **Server metrics footer:** CPU / memory / disk for `/`, polled
  every 4 s with stale/unavailable states.
- **Polish:** reconnect + shortcuts, metrics "collecting" state,
  custom app icon and product name, DMG packaging script, security
  review, user guide, manual test checklist.

Known limitations at 1.0.0 (since addressed above where noted):
single connection at a time, no remote editor, no port forwarding;
distribution builds not Developer-ID notarized.

## Roadmap & known limitations

Done after the MVP: explorer table view, multi-session tabs, profile
management, Labels, Edit File, Windows target + installer, syntax
highlighting. Still open / deferred:

- Signed + notarized macOS distribution (needs a paid Apple
  Developer certificate) and signed Windows builds.
- Quit-while-editing guard: closing the app with unsaved editor
  documents is not yet guarded (per-document close is).
- A small number of manual acceptance items in
  `docs/MANUAL_TEST_CHECKLIST.md` (e.g. metrics footer against a
  real server, quit/reopen persistence on macOS).
- Deferred candidates: snippets, port forwarding, Linux build,
  user-defined highlight rules.

## License

No license file yet — until one is added, the code is published for
viewing and all rights are reserved by the author.
