# Architecture

## Goals

- Keep UI independent from SSH/SFTP implementation.
- Make remote operations testable using fakes.
- Avoid leaking secrets into persistence/logging.
- Support macOS first without making all domain code macOS-specific.
- Keep terminal transport separate from terminal rendering.

## Proposed feature-first structure

```text
lib/
  main.dart
  app/
    app.dart
    router.dart
    theme/
  core/
    errors/
    logging/
    platform/
    security/
    storage/
  features/
    sessions/
      data/
      domain/
      presentation/
    connection/
      data/
      domain/
      presentation/
    terminal/
      data/
      domain/
      presentation/
    remote_explorer/
      data/
      domain/
      presentation/
    transfers/
      data/
      domain/
      presentation/
    server_monitor/
      data/
      domain/
      presentation/
```

Adjust folder depth to actual project size. Avoid creating empty abstractions without a concrete use case.

## Boundaries

### UI / presentation
- Renders state and sends user intent to providers/controllers.
- Does not instantiate SSH clients directly.
- Does not build shell commands from arbitrary user-controlled paths.

### Session repository
- Persists profile metadata and grouping hierarchy.
- Stores only Keychain references for secrets.
- Provides CRUD and search operations.

### Credential store
- Wraps macOS Keychain integration behind a Dart interface.
- Provides read/write/delete operations by opaque credential ID.
- Never exposes secret values to UI state longer than necessary.

### SSH connection service
- Owns connection lifecycle and host-key verification.
- Exposes connection status and terminal byte streams.
- Opens interactive PTY sessions and handles resize/input/output.
- Uses bounded timeouts and deterministic cleanup.

### Terminal view model
- Bridges SSH byte streams to terminal emulator input/output.
- Sends terminal output to the emulator and emulator input to the PTY.
- Does not assume terminal emulator is an SSH client.

### Remote file service
- Lists files/directories and performs rename/delete/download/upload using SFTP.
- Returns typed errors and progress events.
- Treats paths as remote POSIX paths, not local macOS paths.
- Handles stale listing and permissions.

### Shell integration
- Tracks shell working directory using a documented protocol.
- Must not overwrite user shell startup files without consent.
- If unavailable, show sync status and allow manual Explorer navigation.

### Metrics service
- Samples remote host metrics at a modest interval.
- Calculates CPU percentage from successive samples.
- Cancels/ignores stale requests and never overlaps polls.
- Stops when connection is disposed.

## State model

Recommended connection states:
- `disconnected`
- `connecting`
- `connected`
- `reconnecting` (optional)
- `disconnecting`
- `failed`

Recommended operation states:
- `idle`
- `running`
- `succeeded`
- `failed`
- `cancelled`

Use immutable state where practical. Each remote operation should be associated with the connection/session that initiated it so late responses from an old connection cannot update the new session UI.

## Data model sketch

`SshSession`
- id, name, host, port, username
- authMethod
- credentialRef (nullable depending on auth)
- groupId (nullable)
- connectionTimeout
- startupDirectory (optional)
- timestamps

`SessionFolder`
- id, name, parentId (nullable), sortOrder
- timestamps

`RemoteEntry`
- name, absolutePath, kind (file/directory/symlink/other)
- size (optional), modifiedAt (optional), permissions (optional)

`TransferTask`
- id, direction, localPath, remotePath
- totalBytes (optional), transferredBytes
- status, error (sanitized)

`ServerMetrics`
- cpuPercent (nullable)
- memoryUsedBytes, memoryTotalBytes (nullable)
- diskUsedPercent (nullable)
- sampledAt
- status (available/stale/unavailable)

## Dependency evaluation checklist

Before selecting packages, verify:
- Current release and maintenance activity.
- License compatibility for commercial distribution.
- macOS support and minimum deployment target.
- SSH password and private-key auth support.
- Host-key fingerprint and changed-key behavior.
- Interactive shell and PTY support.
- Terminal resize and control-character handling.
- SFTP list/rename/delete/download/upload support.
- Transfer progress/cancellation.
- Key formats and passphrase handling.
- Compatibility with current Flutter stable and Dart SDK.

## Testing strategy

- Unit tests for domain models, validation, CPU percentage calculation, path handling, and state transitions.
- Repository tests with in-memory/fake storage.
- Service tests using fake SSH/SFTP interfaces.
- Widget tests for session list, context menu, dialogs, breadcrumb, and drop target.
- Integration/manual tests against a disposable Linux SSH server.
- Security checks for host-key change, secret redaction, and delete confirmation.
