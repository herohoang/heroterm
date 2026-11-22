#!/usr/bin/env bash
# Builds HeroTerm for macOS and packages it as a SHAREABLE .dmg:
# recipients open the .dmg, drag HeroTerm into Applications, and
# launch it — no source code or Flutter needed on their Mac.
#
# Run on the Mac (not CI):  ./scripts/package_macos.sh
#   --no-build   reuse the existing release build instead of
#                rebuilding (the bundle is still re-signed)
#
# Signing modes (see docs/RELEASE.md §2–§3):
#   1. Notarized — needs a paid Apple Developer account:
#        DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#        NOTARY_PROFILE="heroterm-notary"  (notarytool credentials)
#      Recipients just double-click; no Gatekeeper warning.
#      When DEVELOPER_ID is not exported, the first "Developer ID
#      Application" identity found in the keychain is used
#      automatically, for both the .app and the .dmg.
#   2. Ad-hoc (no Developer ID) — the .app is signed ad-hoc with
#      the release entitlements. Recipients get a Gatekeeper block
#      on first launch; the install guide bundled inside the .dmg
#      walks them through opening it anyway.
#
# Output: build/macos/HeroTerm-<version>.dmg plus a .sha256 file
# next to it, so recipients can verify the download.
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must run on macOS." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

DO_BUILD=1
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
APP="build/macos/Build/Products/Release/HeroTerm.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
DMG="build/macos/HeroTerm-${VERSION}.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

if [[ "$DO_BUILD" == "1" ]]; then
  BUILD_ID=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
  echo "==> flutter build macos --release (version $VERSION, build $BUILD_ID)"
  flutter build macos --release --dart-define=BUILD_ID="$BUILD_ID"
fi

if [[ ! -d "$APP" ]]; then
  echo "Build output not found at $APP — run without --no-build first." >&2
  exit 1
fi

ARCHS=$(lipo -archs "$APP/Contents/MacOS/HeroTerm" 2>/dev/null || echo "unknown")
echo "==> binary architectures: $ARCHS"

# --- Signing -------------------------------------------------------
DEVELOPER_ID="${DEVELOPER_ID:-}"
if [[ -z "$DEVELOPER_ID" ]]; then
  DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 "Developer ID Application" \
    | sed -E 's/.*"(.*)"/\1/' || true)
fi

NOTARIZED=0
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> codesign with Developer ID (hardened runtime): $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$DEVELOPER_ID" "$APP"
else
  echo "==> no Developer ID identity found: ad-hoc signing"
  echo "    Recipients must bypass Gatekeeper on first launch —"
  echo "    the guide bundled in the .dmg explains how."
  codesign --force --deep \
    --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# --- Recipient install guide (bundled inside the .dmg) -------------
GUIDE="$STAGE/Huong dan cai dat.txt"
{
  echo "HeroTerm $VERSION — Hướng dẫn cài đặt / Install guide"
  echo "======================================================"
  echo
  echo "1. Kéo biểu tượng HeroTerm vào thư mục Applications."
  echo "   Drag the HeroTerm icon onto the Applications folder."
  echo "2. Mở Launchpad hoặc thư mục Applications và chạy HeroTerm."
  echo "   Open HeroTerm from Launchpad or the Applications folder."
  if [[ -z "${DEVELOPER_ID:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
    echo "3. Nếu macOS chặn lần mở đầu tiên (Gatekeeper):"
    echo "   If macOS blocks the first launch (Gatekeeper):"
    echo "   - Mở Cài đặt hệ thống → Quyền riêng tư & Bảo mật, kéo xuống"
    echo "     mục Bảo mật và bấm 'Vẫn mở' / 'Open Anyway' cạnh dòng"
    echo "     nhắc tới HeroTerm, rồi mở lại app."
    echo "     Open System Settings → Privacy & Security, scroll to"
    echo "     Security and click 'Open Anyway' next to HeroTerm, then"
    echo "     launch the app again."
    echo "   - Nếu báo 'HeroTerm is damaged': mở ứng dụng Terminal,"
    echo "     chạy lệnh sau rồi mở lại app:"
    echo "     If it says 'HeroTerm is damaged': open Terminal, run"
    echo "     this command, then launch the app again:"
    echo "       xattr -dr com.apple.quarantine /Applications/HeroTerm.app"
  fi
  echo
  echo "Yêu cầu: macOS 11 trở lên, Apple Silicon hoặc Intel."
  echo "Requires macOS 11 or later, Apple Silicon or Intel."
} > "$GUIDE"

# --- Stage + build the .dmg ----------------------------------------
echo "==> staging .dmg contents"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> creating $DMG"
rm -f "$DMG"
hdiutil create -volname "HeroTerm" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --sign "$DEVELOPER_ID" "$DMG"
fi

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  NOTARIZED=1
  echo "==> notarization stapled"
fi

# --- Checksum so recipients can verify the file --------------------
( cd "$(dirname "$DMG")" \
  && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

SIZE=$(du -h "$DMG" | awk '{print $1}')
SHA=$(awk '{print $1}' "$DMG.sha256")

echo
echo "=================================================================="
echo "Shareable installer ready:"
echo "  File:     $PWD/$DMG ($SIZE)"
echo "  SHA-256:  $SHA"
echo "            (also saved in $DMG.sha256)"
echo "  Binary:   $ARCHS — runs on Apple Silicon and Intel Macs"
if [[ "$NOTARIZED" == "1" ]]; then
  echo "  Signing:  Developer ID + notarized — recipients just open it."
elif [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "  Signing:  Developer ID, NOT notarized — recipients must click"
  echo "            'Open Anyway' once (guide inside the .dmg explains)."
  echo "            Set NOTARY_PROFILE to notarize next time (§3)."
else
  echo "  Signing:  ad-hoc, NOT notarized — recipients must bypass"
  echo "            Gatekeeper once (guide inside the .dmg explains)."
fi
echo "Send the .dmg file (AirDrop, Google Drive, Zalo...) — recipients"
echo "need nothing else."
echo "=================================================================="
