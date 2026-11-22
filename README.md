# HeroTerm

A Flutter desktop SSH client for macOS, inspired by the practical workflow of MobaXterm, with a clean native-feeling interface.

## Product goals

- Save and organize SSH sessions in user-created folders.
- Connect using SSH password or private-key authentication.
- Provide an interactive terminal.
- Browse remote folders and files, with the sidebar reflecting the current remote working directory.
- Provide file context actions: Rename, Delete, Download.
- Drag files from macOS Finder and drop them into the current remote directory to upload.
- Show remote CPU, memory, and disk usage in the footer.
- Store secrets securely using macOS Keychain; never write passwords or private keys into ordinary config files.

## Start here

1. Read [`AGENT.md`](AGENT.md) before asking a coding agent to modify the project.
2. Read [`ROADMAP.md`](ROADMAP.md) for the implementation sequence.
3. Read [`docs/FEATURE_SPEC.md`](docs/FEATURE_SPEC.md) for user-visible behavior.
4. Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for boundaries and data flow.
5. Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for local setup and quality gates.

## Current status

Milestone 0 complete (2026-10-24): Flutter macOS project created
(Flutter 3.47.8 / Dart 3.13.7); app shell, theme, error model, domain
models, and the Keychain-backed credential-store abstraction are
implemented, and the app was verified running on a macOS machine.
Milestone 1 (SSH session manager) implemented 2026-10-24: full
session/folder management with local JSON persistence and Keychain
credential storage; macOS quit/reopen acceptance check pending (see
ROADMAP). Milestone 2 (SSH connection + interactive terminal)
implemented 2026-10-24 with dartssh2 + xterm and verified end-to-end
against a real SSH test server on the authoring VM; connecting from
the macOS app UI to a real server is the remaining acceptance check
(a macOS sandbox entitlement fix for outgoing connections,
ADR-007, was required and is included). Milestone 3 (SFTP Remote
Explorer with terminal working-directory tracking via OSC 7,
ADR-008) implemented and live-verified the same day; the user
confirmed Milestones 2–3 in the macOS app against a real server.
Milestone 4 (explorer file actions) and Milestone 5 (Finder
drag-and-drop upload) followed; the user verified Milestone 4 in
the app and confirmed drag-and-drop upload works on the Mac.
Milestone 6 (remote server metrics footer: CPU via two-sample
delta, memory via MemAvailable, disk for `/`, polled every 4 s
with stale/unavailable states) implemented and live-verified
against a real SSH test server the same day; macOS app acceptance
is pending. Milestone 7 (polish and release) implemented
2026-10-25: reconnect + keyboard shortcuts, a metrics
"collecting" state, a custom app icon and product name, DMG
packaging script with a Developer ID/notarization plan
(`docs/RELEASE.md`), security review, user guide, manual test
checklist, and 1.0.0 release notes (`CHANGELOG.md`). Outstanding
on the user's side: Milestone 6 footer acceptance on the Mac,
the Milestone 1 quit/reopen persistence check, and producing a
signed/notarized DMG (needs a paid Apple Developer certificate).
Do not claim a phase is complete until its acceptance
criteria pass.

## Initial platform scope

- First target: macOS desktop.
- Architecture should avoid unnecessary platform-specific coupling so Windows/Linux can be considered later.
- Initial language: Dart.
- UI framework: Flutter.
- State management: Riverpod (confirm compatible package versions before adding dependencies).
- Terminal UI candidate: `xterm` / `xterm2`; evaluate maintenance, license, and Flutter/macOS compatibility before choosing.
- SSH/SFTP candidate: `dartssh2`; verify interactive PTY, key algorithms, host-key handling, SFTP, and current package health before locking it in.
