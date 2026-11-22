# Threat model — HeroTerm (Milestone 0 baseline)

Scope: a macOS desktop SSH client holding credentials for, and
privileged access to, remote servers. This baseline is expanded per
milestone; the mandatory requirements live in `docs/SECURITY.md`.

## Assets
- Passwords, private keys, and key passphrases.
- Trusted host-key records.
- Session metadata (hostnames, usernames, paths) — sensitive metadata.
- Remote files in transit (upload/download).
- The user's local filesystem destinations for downloads.

## Adversaries and risks
- **Network attacker / impostor server:** mitigated by mandatory
  host-key verification with explicit first-use trust and blocking on
  changed keys. Never an always-accept default.
- **Malicious or compromised remote server:** remote output is
  untrusted — sanitize before showing as errors/diagnostics; file
  names/paths from the server are untrusted input and must never be
  interpolated into local or remote shell commands.
- **Local attacker / other local processes:** secrets only in the
  macOS Keychain; local metadata files hold opaque credential
  references only; restrict local file permissions where supported.
- **Accidental user action:** destructive remote operations (delete,
  overwrite) require explicit confirmation naming the target; partial
  transfers are never shown as successful.
- **Supply chain:** dependencies are evaluated before adoption
  (see `docs/DEPENDENCIES.md`); versions pinned in `pubspec.lock`.
- **Leakage via diagnostics:** logs and error messages redact
  credentials and auth payloads; diagnostic logging that could reveal
  hostnames/usernames/paths is opt-in.

## Out of scope (MVP)
- Multi-hop/bastion hosts, port forwarding, remote editing
  (FEATURE_SPEC section 10) — each would extend this model before
  being designed.
- Protection against a fully compromised local macOS account
  (Keychain access follows the user's login).
