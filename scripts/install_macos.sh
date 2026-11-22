#!/usr/bin/env bash
# Builds HeroTerm in release (production) mode and installs it
# into /Applications on THIS Mac, replacing any previous copy.
#
# Usage (run on the Mac, from the repo root):
#   ./scripts/install_macos.sh            # build + install
#   ./scripts/install_macos.sh --open     # build + install + launch
#   ./scripts/install_macos.sh --no-build # install the existing build
#
# Signing: the script uses the first usable code-signing identity
# found in your keychain (Developer ID / Apple Development /
# self-signed). A STABLE identity matters: macOS ties Keychain
# access to the app's signature, so an app re-signed with the same
# identity keeps access to stored passwords across reinstalls.
# When no identity exists the app is ad-hoc signed ("-") and macOS
# may ask again for Keychain access after each reinstall; create a
# self-signed "Code Signing" certificate in Keychain Access to
# avoid that. Override the choice with:
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"
set -euo pipefail

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must run on macOS." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

DO_BUILD=1
DO_OPEN=0
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    --open) DO_OPEN=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d'+' -f1)
APP="build/macos/Build/Products/Release/HeroTerm.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
DEST="/Applications/HeroTerm.app"

if [[ "$DO_BUILD" == "1" ]]; then
  BUILD_ID=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
  echo "==> flutter build macos --release (version $VERSION, build $BUILD_ID)"
  flutter build macos --release --dart-define=BUILD_ID="$BUILD_ID"
fi

if [[ ! -d "$APP" ]]; then
  echo "Build output not found at $APP — run without --no-build first." >&2
  exit 1
fi

# --- Pick a signing identity -------------------------------------
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  # First valid identity listed by the keychain (hash in column 2).
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 '"' | sed -E 's/^ *[0-9]+\) ([0-9A-F]+) .*/\1/' || true)
fi
if [[ -n "${IDENTITY:-}" ]]; then
  echo "==> codesign with identity: $IDENTITY"
  codesign --force --deep \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"
else
  echo "==> no signing identity found: ad-hoc signing"
  echo "    (macOS may re-ask for Keychain access after reinstalls;"
  echo "     a self-signed Code Signing certificate avoids that)"
  codesign --force --deep \
    --entitlements "$ENTITLEMENTS" \
    --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# --- Quit a running instance so the bundle can be replaced -------
if pgrep -x HeroTerm >/dev/null 2>&1; then
  echo "==> quitting the running HeroTerm"
  osascript -e 'quit app "HeroTerm"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x HeroTerm >/dev/null 2>&1 || break
    sleep 0.5
  done
  pkill -x HeroTerm >/dev/null 2>&1 || true
fi

# --- Install ------------------------------------------------------
echo "==> installing to $DEST"
if [[ ! -w /Applications ]]; then
  mkdir -p "$HOME/Applications"
  DEST="$HOME/Applications/HeroTerm.app"
  echo "    /Applications is not writable; using $DEST instead"
fi
rm -rf "$DEST"
ditto "$APP" "$DEST"
# Locally built apps are not quarantined, but clear the flag in
# case the bundle ever arrived through a download.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

INSTALLED_VERSION=$(defaults read "$DEST/Contents/Info.plist" \
  CFBundleShortVersionString 2>/dev/null || echo "$VERSION")
echo "Installed HeroTerm $INSTALLED_VERSION at $DEST"

if [[ "$DO_OPEN" == "1" ]]; then
  echo "==> launching HeroTerm"
  open "$DEST"
fi
