# HeroTerm — Security review (Milestone 7)

Performed 2026-10-25 against the 1.0.0 codebase (audit by code
search + reading the flows; items cite the mechanism, not intent).

## Credentials

- Passwords and key passphrases are stored **only** in the macOS
  Keychain via `flutter_secure_storage` (legacy keychain,
  `usesDataProtectionKeychain: false`; no `keychain-access-groups`
  entitlement — see Milestone 0 notes). Sessions reference them by
  an opaque `credentialRef`.
- The session JSON (`heroterm-sessions.json`, Application Support)
  contains metadata only — verified: the repository never writes a
  password field; private keys are referenced by file path, key
  material is never copied into app storage.
- Deleting a session/folder removes credentials that are no longer
  referenced. Duplicating a session mints a fresh `credentialRef`.
- Passwords prompted at connect time (nothing stored) live only in
  memory for the duration of the attempt.
- **No logging of secrets:** `lib/` contains no `print`/`debugPrint`
  or logging calls at all (verified by search). `AppError`
  diagnostics carry the exception *type* only, never values.
  One documented exception (ADR-015): the **opt-in input log**
  (⌘⇧L, off by default, nothing recorded while off) writes the
  terminal's input/output event stream to
  `heroterm-input-log.txt` in Application Support for diagnosing
  typing corruption. It is user-initiated, the toggle and the
  file banner both warn that typed content is recorded and
  passwords must not be typed while it is on, and the file never
  leaves the machine unless the user sends it.

## Host keys

- First-use trust shows the full SHA-256 fingerprint and requires an
  explicit Trust decision; entries persist in
  `heroterm-known-hosts.json` (atomic writes; a corrupt file is
  treated as empty and re-prompts rather than silently trusting).
- A changed host key blocks the connection
  (`hostKeyChanged`) — verification is never disabled or bypassed.

## Multi-session isolation (ADR-011)

- Each terminal tab owns its connection, terminal buffer and
  prompts; no input, output, exec result or credential is shared
  or routed between sessions — routing is by the tab's stable
  runtime ID and its own connection object.
- Host-key verification runs for every new connection, in every
  tab, with the same trust store and changed-key blocking.
- Host-key/password prompts are serialized across tabs so a
  prompt is always answered for the connection that asked; a
  prompt belonging to a failed attempt or a closed tab is
  discarded, never answered against another session.
- Runtime tab state holds no credentials: secrets are read from
  the Keychain per connect via the profile's `credentialRef`,
  exactly as in the single-connection design.

## Profile import/export & duplicate (ADR-012)

- Export files contain connection configuration only: no
  passwords, passphrases, key material, and no Keychain
  reference IDs (a unit test scans exported JSON for all of
  these). The export dialog states this before writing.
- Import treats the file as untrusted: size/count limits,
  strict schema, type, enum and range validation; malformed
  files are rejected whole. Imported profiles carry no
  credential and are never auto-connected.
- Duplicating a profile shares its Keychain reference instead of
  copying the secret; secret edits copy-on-write and deletes
  are reference-counted, so no profile can observe, alter or
  destroy another profile's credential through sharing.
- Test Connection uses the same host-key verification as a real
  connection (no silent trust) and its result messages are the
  typed, secret-free `AppError` texts.
- Labels (ADR-013) are metadata only — names and colours in the
  same JSON library; exports carry label names (never internal
  IDs beyond the session's own icon/colour), and imports create
  or match labels by name under the same strict validation.

## Command execution & shell input

- Exec-channel commands are fixed, read-only constants with no
  user input interpolated: the metrics poll (`/proc/stat`,
  `/proc/meminfo`, `df -P /`) and, since the explorer table view
  (ADR-010), one account-database read per connection
  (`/etc/passwd` + `/etc/group`) used only to label numeric
  UID/GIDs; its output is parsed as data, never executed.
- File operations (list/rename/delete/upload/download) use SFTP
  calls exclusively — no shell strings are built from file names.
- The two places that write to the interactive shell are the OSC 7
  integration snippet (fixed constant) and the optional startup
  `cd`, which single-quotes the path with proper `'\''` escaping.
- Rename validates the new name (`RemotePath.validateNewName`):
  no separators, no `..`, length-capped.

## Sandbox & entitlements

- The app is sandboxed in both profiles. Release entitlements:
  `network.client` and `files.user-selected.read-write` only.
- Debug adds `network.server` + `allow-jit` (required by
  `flutter run` during development; absent from Release).
- Finder drag-and-drop reads files only through security-scoped
  bookmarks granted by the drop itself; scopes are released after
  the upload. Private keys are read only via the file-picker
  (Browse…) grant or a path the user typed (documented limitation).

## Destructive operations

- Remote delete requires a confirmation dialog naming the full
  path; directories are deleted recursively over SFTP only after
  that confirmation. Cancelled transfers delete their partial file
  (download: local, upload: remote) so a partial file never poses
  as a completed one.

## Residual risks / accepted trade-offs

- Known-hosts and session metadata are plain JSON in Application
  Support (fingerprints and connection metadata, no secrets) —
  acceptable for a single-user desktop app; tampering with
  known-hosts can at worst re-trigger a trust prompt or block a
  connection.
- The terminal renders remote output through the vendored `xterm`
  (ADR-009); escape-sequence handling is upstream code plus the
  committed-text patch.
- Distribution builds are not yet Developer-ID signed/notarized —
  see `docs/RELEASE.md` for the plan and its account prerequisite.

## File editing (ADR-016)

- **No content logging:** the editor never logs file contents;
  the ADR-015 input log remains the only opt-in exception and
  covers terminal input, not editor buffers.
- **Temp files:** external editing copies live in a per-document
  directory created under the system temp (or the configured
  Temp Directory) with `chmod 700`, because the files edited
  most are exactly the sensitive ones (`.env`, configs). A temp
  copy is deleted when its session closes clean; while it holds
  unsynced changes it is kept and the user decides — data safety
  wins over tidiness. Quitting the app can leave temp copies
  behind; they stay inside the user-only directory.
- **No silent overwrite:** saves re-stat the remote file and
  refuse to write when size or mtime moved since load, so an
  edit session cannot clobber a teammate's change unnoticed.
