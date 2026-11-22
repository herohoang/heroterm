# Security Requirements

SSH clients handle privileged remote access. Security requirements are mandatory, not optional polish.

## Credentials

- Store passwords, passphrases, and imported private-key material in macOS Keychain when feasible.
- Ordinary app database/config files may contain only opaque credential references.
- Do not commit secrets, sample private keys, production hosts, or real credentials.
- Do not print secrets in logs, exceptions, analytics, test snapshots, or bug reports.
- If a private key remains at a user-selected path instead of being imported, document that behavior and never silently copy it.

## Host-key verification

- Verify SSH host keys.
- On first connection, display a fingerprint and ask the user to trust it.
- Persist known host keys securely in local app data.
- If a previously trusted host key changes, block the connection and display a warning.
- Never implement an always-accept host-key callback as a production default.
- Make trust replacement an explicit user action.

## Remote commands and paths

- Prefer SFTP operations for file management.
- Never concatenate untrusted filenames or paths into shell command strings.
- Any required remote command must use fixed command templates, strict argument handling, a timeout, and read-only behavior where possible.
- Metrics commands must not mutate server state.
- Avoid recursive delete in MVP.

## File transfers

- Show the exact destination before upload.
- Confirm overwrite conflicts.
- Do not mark partial transfers as successful.
- Ensure disconnect cancels or marks in-progress transfers accurately.
- Avoid writing downloaded data to an unexpected location.

## Logging and errors

- Redact credentials and authentication payloads.
- Do not include full private key material in diagnostics.
- Sanitize remote output before presenting it as an error.
- Keep diagnostic logging opt-in if it may reveal hostnames, paths, or usernames.

## Local storage

- Restrict permissions on local data where supported.
- Keep secrets out of exports and backups.
- Document where session metadata and known-host records live.
- Provide a way to delete a stored credential when a session is removed, with clear behavior if credentials are shared.

## Security acceptance checklist

- [ ] Unknown host key requires explicit trust.
- [ ] Changed host key blocks connection by default.
- [ ] No password/private-key data in SQLite or JSON/YAML config.
- [ ] No secrets in logs.
- [ ] Delete file requires confirmation.
- [ ] Filename/path handling does not permit command injection.
- [ ] Overwrite is confirmed.
- [ ] Transfer failure is never displayed as success.
