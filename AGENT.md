# AGENT.md — Coding Agent Instructions

## Mission

Build **HeroTerm**, a reliable Flutter desktop SSH client for macOS. It manages SSH profiles, provides an interactive remote terminal, browses remote files, transfers files over SFTP, and displays remote server metrics.

## Read before coding

Always read these files before making architectural or feature changes:

1. `README.md`
2. `ROADMAP.md`
3. `docs/FEATURE_SPEC.md`
4. `docs/ARCHITECTURE.md`
5. `docs/SECURITY.md`
6. `docs/DEVELOPMENT.md`

If instructions conflict, prioritize in this order: explicit user request in the current task, `docs/SECURITY.md`, `docs/FEATURE_SPEC.md`, `docs/ARCHITECTURE.md`, `ROADMAP.md`, then implementation convenience. Update the docs when a decision changes.

## Product principles

- macOS-first, Flutter/Dart.
- Prioritize a working, secure MVP over premature abstractions.
- Keep UI, SSH transport, SFTP file operations, persistence, credentials, and metrics behind separate interfaces.
- Build small, reviewable increments. Do not implement the entire roadmap in one change.
- Do not claim functionality is complete without tests or a reproducible manual verification path.
- Prefer accessible, keyboard-friendly UI and clear loading/empty/error states.
- Do not introduce unrelated features without asking.

## Required workflow for each task

1. Inspect the existing code and current git status before editing.
2. Identify the relevant roadmap phase and acceptance criteria.
3. Propose a short plan for non-trivial changes.
4. Implement only the requested scope.
5. Add/update tests for behavior and edge cases.
6. Run `dart format`, `flutter analyze`, and relevant tests. If a command cannot run, state why.
7. Update docs and checkboxes only for work that is actually verified.
8. Summarize changed files, behavior, test commands/results, and known limitations.

## Architecture rules

- Use feature-first organization under `lib/features/`.
- Keep platform-neutral interfaces in Dart where practical.
- UI widgets must not create SSH clients or execute remote commands directly.
- All remote operations go through services/repositories with typed results and errors.
- Use Riverpod for shared application state if adopted; avoid global mutable singletons.
- Do not store secrets in SQLite, JSON, YAML, logs, crash reports, or source control.
- Never disable SSH host-key verification by default. First connection must show the host fingerprint and ask the user to trust it; changed keys must produce a clear security warning and block connection until explicitly resolved.
- Do not execute user-controlled filenames or paths by interpolating them into shell commands. Prefer SFTP protocol operations for file actions.
- Never run destructive remote operations without explicit user confirmation.
- Avoid shell command parsing as the only mechanism for tracking current working directory. Prefer an explicit shell integration protocol; document fallback behavior for unsupported shells.
- Metrics commands must be read-only, bounded in execution time, and run at a modest polling interval. Stop polling on disconnect/background when appropriate.
- Do not log passwords, private-key contents, authentication payloads, or raw secrets.

## UI and interaction rules

- When disconnected, the sidebar shows SSH sessions and user-defined grouping folders.
- When connected, the sidebar/remote explorer shows the remote directory tree and current directory.
- Clicking a folder navigates into it; breadcrumb navigation moves to ancestors.
- Right-clicking a remote file opens a context menu with Rename, Delete, Download.
- Delete requires a confirmation dialog identifying the target.
- Dragging files from macOS Finder into the current remote directory uploads them via SFTP.
- Upload/download operations show progress, handle cancellation if supported, and surface errors.
- The footer reports metrics for the connected remote server, never the local Mac.
- UI must distinguish disconnected, connecting, connected, reconnecting, and error states.
- Do not display fake live metrics in production UI. Fixtures may be used in tests/previews only and must be clearly labeled.

## Dependencies

Before adding or upgrading a dependency:
- Check current package API, supported platforms, maintenance/activity, license, and transitive dependencies.
- Verify macOS support and required capabilities (PTY, terminal resize, key formats, SFTP, drag-and-drop).
- Keep dependency versions compatible and update `pubspec.lock` where appropriate.
- Do not assume a terminal emulator widget provides SSH transport.

## Definition of done

A task is done only when:
- Scope and acceptance criteria are met.
- Formatting and static analysis pass, or blockers are reported.
- Tests cover key success and failure cases.
- No secrets are committed or logged.
- Relevant docs reflect actual behavior.
- The final response lists what changed, validation performed, and remaining risks.
