# Development Guide

## Prerequisites

- macOS supported by the installed Flutter stable version.
- Flutter SDK and Dart SDK installed through Flutter.
- Xcode and command-line tools installed for macOS builds.
- Git.
- A disposable Linux SSH test host is recommended. Do not test destructive operations on production servers.

Verify tools:

```bash
flutter --version
dart --version
flutter doctor -v
```

## Create the app if the repository is empty

Run from the repository root only if no Flutter project exists yet:

```bash
flutter create --platforms=macos .
```

If a project already exists, inspect it first and do not overwrite existing configuration.

## Dependency selection

Do not blindly add packages from this document. Evaluate package APIs, maintenance, licenses, and macOS compatibility first. Candidate categories:
- State management: Riverpod.
- Terminal emulator: xterm or xterm2.
- SSH and SFTP: dartssh2 or a vetted alternative.
- Secure storage: flutter_secure_storage / Keychain-backed implementation.
- Local metadata persistence: SQLite-backed package if needed.
- File drag-and-drop: a maintained Flutter desktop package compatible with macOS.

Verify terminal and SSH packages can be wired together with an interactive PTY before committing to the stack.

## Common quality commands

```bash
dart format .
flutter analyze
flutter test
flutter run -d macos
```

For a formatting check without modifying files:

```bash
dart format --output=none --set-exit-if-changed .
```

## Suggested local test server

Use a disposable Ubuntu VM/container or a dedicated non-production server. Create a non-root test account and test:
- Password authentication.
- Public-key authentication.
- Host-key trust and changed-key behavior.
- Directory/file listing including hidden files and Unicode/spaces.
- Rename, download, upload, collision, permission-denied, and disconnect cases.
- Metrics on Linux.

Never put real passwords or private keys in this repository.

## Manual smoke test

1. Launch the app.
2. Create a session and a folder; move the session into that folder.
3. Restart and confirm metadata persists.
4. Connect to the test server and verify host fingerprint prompt.
5. Type commands and resize the terminal.
6. Change directories in terminal and confirm Explorer sync behavior.
7. Navigate with folder clicks and breadcrumbs.
8. Right-click a file and test Rename, Delete confirmation, and Download.
9. Drag one and multiple files from Finder to the current remote directory.
10. Test collisions, permissions, disconnects, and failed transfers.
11. Verify CPU/RAM/disk refer to the remote server and stop updating after disconnect.
12. Check logs and local storage for accidental secrets.

## Pull request / task completion template

- Scope:
- Files changed:
- Acceptance criteria:
- Tests run and results:
- Security considerations:
- Known limitations:
- Docs updated:
