# Test Plan

## Unit tests

- Session profile validation: hostname, port range, username, auth method.
- Folder hierarchy and moving sessions.
- Remote POSIX path normalization and breadcrumb ancestors.
- Rename validation, including empty names, `.`, `..`, separators, and collision.
- CPU percentage calculation from two `/proc/stat` samples.
- Memory-used calculation using total and `MemAvailable`.
- Metrics state transitions: available, stale, unavailable.
- Transfer progress, cancellation, failure, and completion state.
- Error sanitization and secret redaction.

## Widget tests

- Disconnected sidebar shows session groups.
- Connected sidebar shows Remote Explorer.
- Folder click navigates and breadcrumb navigates to ancestors.
- Right-click context menu offers Rename, Delete, Download.
- Delete confirmation displays target path and can be cancelled.
- Upload drop target indicates destination and handles disconnected state.
- Metrics footer distinguishes unavailable/stale from valid zero values.

## Integration tests

Use a disposable Linux SSH server:
- Password login and private-key login.
- Unknown host key and changed host key.
- Interactive PTY and terminal resize.
- SFTP list, rename, delete, download, upload.
- File names with spaces, Unicode, dotfiles, symbolic links, and permission restrictions.
- Interrupted transfer and connection loss.
- Metrics on Linux and graceful fallback when commands/files are unavailable.

## Release gates

- Formatting passes.
- Static analysis passes.
- Unit/widget tests pass.
- Critical integration smoke tests pass.
- Security checklist in `docs/SECURITY.md` is reviewed.
- No secrets or production connection details are committed.
