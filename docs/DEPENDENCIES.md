# Dependency evaluation — HeroTerm

Evaluated during Milestone 0 (2026-10-24) against the checklist in
`docs/ARCHITECTURE.md`. Versions are pinned by `pubspec.lock` after
`flutter pub add`; this file records *why* each package is in (or not
yet in) the project.

## Adopted in Milestone 0

### flutter_riverpod — state management
- Resolved version: 3.4.3 (`pubspec.lock`, 2026-10-24, with
  Flutter 3.47.8 / Dart 3.13.7).
- Specified in the product docs (README/ARCHITECTURE) as the intended
  state-management approach.
- Actively maintained, MIT-licensed, pure Dart/Flutter (no platform
  channels), so it carries no macOS deployment risk.
- Milestone 0 usage is intentionally minimal: a `ProviderScope` at the
  root and a `Provider<CredentialStore>`. Deeper patterns are adopted
  per feature, avoiding premature abstraction.

### flutter_secure_storage — credentials in macOS Keychain
- Backs the `CredentialStore` abstraction on macOS with the Keychain.
- Resolved version: 11.2.0 (`pubspec.lock`, 2026-10-24).
- macOS configuration decision: do **not** add the Keychain Sharing
  entitlement (`keychain-access-groups`). Per the package docs, that
  entitlement requires a provisioning profile, which on a free Apple
  Developer account makes the built app launch only on the Mac that
  built it. HeroTerm does not share keychain items with other apps, so
  the macOS implementation uses
  `MacOsOptions(usesDataProtectionKeychain: false)` (legacy keychain).
  Revisit if App Groups / sharing are ever introduced (Milestone 7
  signing/notarization review).

## Resolved in the Milestone 2 spike (2026-10-24)

### dartssh2 — SSH/SFTP transport (adopted)
- Resolved version: **4.1.0** (`pubspec.lock`). MIT license, pure
  Dart. Changelog shows active 2026 maintenance, including
  security-focused fixes (host-key change on rekey now terminates,
  constant-time MAC comparison, KEX public-value validation).
- 4.0 removed legacy algorithms from the default proposals (SHA-1
  KEX, `ssh-rsa`, CBC ciphers), matching current OpenSSH defaults.
  Servers offering only legacy algorithms will fail to negotiate
  rather than connect weakly; `SSHAlgorithms` can opt back in per
  need, which HeroTerm does not do by default.
- API surface used: `SSHSocket.connect`, `SSHClient` with
  `onVerifyHostKey` (presents the OpenSSH `SHA256:` fingerprint) and
  `onPasswordRequest`, `SSHKeyPair.fromPem` (OpenSSH/PEM keys,
  passphrase decryption with a typed `SSHKeyDecryptError`),
  `client.shell()` with `SSHPtyConfig`, and
  `SSHSession.resizeTerminal`.

### xterm — terminal emulator (adopted, vendored with patch)
- Resolved version: **4.0.0**, vendored at `third_party/xterm`
  with a local IME input patch (ADR-009,
  `third_party/xterm/VENDORED.md`). The 4.x line is
  current and supersedes the stale 2.x-era releases noted during
  Milestone 0, so no fork is needed. `Terminal` + `TerminalView`
  bridge to dartssh2 via `onOutput`/`onResize` callbacks and
  `Terminal.write()` for decoded output.
- The terminal stays behind the transport/rendering boundary
  (ADR-002): the connection controller talks to a `RemoteShell`
  interface, not to dartssh2 types, so the choice stays reversible.

## Deferred beyond Milestone 0
- Local metadata persistence (SQLite-backed package): Milestone 1,
  when session persistence is implemented. Metadata only — secrets
  stay in the Keychain.
- Drag-and-drop package: Milestone 5, evaluated then for maintained
  macOS desktop support.

### path_provider — application support directory (Milestone 1)
- Locates the macOS application support directory where the session
  library JSON lives (ADR-006). First-party (Flutter team) plugin
  with macOS support.

### uuid — identifiers (Milestone 1)
- Generates session, folder, and credential-reference ids (v4).
