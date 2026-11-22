# HeroTerm — Release guide (macOS + Windows)

Versioning lives in `pubspec.yaml` (`version: 1.0.0+1` = marketing
version + build number). The app name shown by macOS comes from
`macos/Runner/Configs/AppInfo.xcconfig` (`PRODUCT_NAME = HeroTerm`),
and the icon set in `macos/Runner/Assets.xcassets/AppIcon.appiconset`
(regenerate with `python3 scripts/generate_app_icon.py`, needs
Pillow).

## 1. Build and package (shareable installer)

On the Mac, from the repo root, one command:

```sh
./scripts/package_macos.sh
```

The script builds the release app, signs it (mode below), and
produces in `build/macos/`:

- `HeroTerm-<version>.dmg` — the file you share (AirDrop, Drive,
  Zalo...). Recipients need nothing else: the .dmg contains the
  `.app`, an `/Applications` shortcut for drag-install, and a
  bilingual install guide (`Huong dan cai dat.txt`) covering the
  first-launch Gatekeeper steps for non-notarized builds.
- `HeroTerm-<version>.dmg.sha256` — checksum recipients can verify
  with `shasum -a 256 -c`.

`--no-build` reuses the existing release build (the bundle is
still re-signed). The Flutter macOS build is a universal binary
(Apple Silicon + Intel); the script prints the architectures it
detected in the summary at the end.

## 1b. Install a production build on this Mac

For day-to-day use on your own MacBook (no .dmg, no distribution):

```bash
./scripts/install_macos.sh --open
```

This builds the release app, signs it, quits any running copy,
installs it into `/Applications` (replacing the old one) and
launches it. `--no-build` reinstalls the existing build output.

Signing notes: the script prefers a real code-signing identity
from your keychain (any Developer ID / Apple Development /
self-signed "Code Signing" certificate) because macOS ties
Keychain access to the app's signature — a stable identity keeps
stored session passwords accessible across reinstalls. With no
identity it falls back to ad-hoc signing; the app runs fine, but
macOS may re-ask for Keychain access after each reinstall.
Override the identity with `SIGN_IDENTITY="..."`. This is a
local install only; distribution still uses §1–§3 (Developer ID
+ notarization), which requires a paid Apple Developer account.

## 2. Signing

What recipients experience depends on the signing mode — the
packaging script prints which one it produced:

- **Ad-hoc (current state, no paid account):** the script re-signs
  the app ad-hoc with the release entitlements. The .dmg works on
  any Mac, but Gatekeeper blocks the first launch. Recipients
  follow the guide bundled in the .dmg: on macOS 15+ that means
  System Settings → Privacy & Security → **Open Anyway** (the old
  right-click → Open bypass no longer overrides Gatekeeper);
  if macOS instead claims the app "is damaged", they clear the
  quarantine flag once:
  `xattr -dr com.apple.quarantine /Applications/HeroTerm.app`.
- **Developer ID, not notarized:** the script auto-detects the
  first *Developer ID Application* identity in the keychain (or
  takes `DEVELOPER_ID` from the environment) and re-signs the
  `.app` — hardened runtime, secure timestamp — and the `.dmg`.
  Gatekeeper still asks recipients for the one-time **Open
  Anyway** step because the build is not notarized.
- **Developer ID + notarized:** with `NOTARY_PROFILE` also set,
  the script notarizes and staples the .dmg (§3) and recipients
  just double-click. This is the only mode with zero warnings.

## 3. Notarization plan (for distribution builds)

1. Store credentials once:
   `xcrun notarytool store-credentials "heroterm-notary" --apple-id <id> --team-id <TEAMID>`
   (uses an app-specific password).
2. Run the packaging script with `NOTARY_PROFILE=heroterm-notary`
   set (the Developer ID identity is auto-detected from the
   keychain, or set `DEVELOPER_ID` explicitly). It submits the `.dmg` to
   Apple's notary service, waits for the verdict, and staples the
   ticket so first launch works offline.
3. Verify: `xcrun stapler validate build/macos/HeroTerm-<version>.dmg`
   and `spctl --assess --type open --context context:primary-signature -v <dmg>`.

Until a Developer ID certificate exists, notarization is not
possible — this is an account prerequisite, not a code blocker.

## 4. Pre-release checklist

- [ ] `dart format --set-exit-if-changed .`, `flutter analyze`,
      `flutter test` all pass.
- [ ] `docs/MANUAL_TEST_CHECKLIST.md` run through on a real Mac
      against a real server.
- [ ] Version bumped in `pubspec.yaml`; `CHANGELOG.md` updated.
- [ ] `.dmg` opens, app installs into `/Applications`, first
      launch + connect verified from the installed copy.

## 5. Windows build

Windows compilation requires a Windows host (the Flutter tool
refuses elsewhere) with Flutter and Visual Studio 2022 including
the "Desktop development with C++" workload.

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package_windows.ps1
```

The script builds the release with the git build stamp
(ADR-019), then packages `build\windows\x64\runner\Release`
into `build\windows\HeroTerm-<version>-windows-x64.zip` (plus
`.sha256`) with a bilingual install note. Users extract the zip
and run `HeroTerm.exe` in place — the exe must stay next to its
DLLs. The build is unsigned, so SmartScreen warns on first run
("More info" → "Run anyway"); a code-signing certificate
removes that, mirroring the macOS notarization story in §3.
Per-user data lands in `%APPDATA%\HeroTerm`; passwords go to
Windows Credential Manager via DPAPI (flutter_secure_storage).

**Installer (ADR-022).** For a proper setup program instead of
the portable zip, install Inno Setup 6
(`winget install JRSoftware.InnoSetup`) and run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\package_windows_installer.ps1
```

This builds the release the same way, then compiles
`installer\HeroTerm.iss` into
`build\windows\HeroTerm-<version>-setup.exe` (plus `.sha256`).
The installer is per-user — it installs into
`%LOCALAPPDATA%\Programs\HeroTerm` with no admin prompt,
creates Start Menu (and optional desktop) shortcuts, offers to
launch the app at the end, and registers a standard
uninstaller. Uninstalling keeps `%APPDATA%\HeroTerm` (sessions
and settings survive a reinstall). Same unsigned/SmartScreen
caveat as the zip.

Windows port notes (ADR-021): the external-editor flow launches
the configured executable directly (detected: VS Code, Cursor,
Sublime Text, Notepad++, Zed, Notepad) or the OS default handler
when none is configured; the file watcher accepts both path
separators. First Windows run should re-run the manual test
checklist (typing incl. Vietnamese IME, completion + backspace,
external edit + auto sync) against a real server.
