#!/usr/bin/env bash
#
# build-app.sh — assemble Haunts.app from the SwiftPM release build.
#
# SwiftPM stays the source of truth (the executable target builds the binary);
# this script wraps it in a real .app bundle so Launch Services treats Haunts as
# a proper agent app: menu-bar item, no Dock icon, app icon, ember accent, and
# a bundle identity that SMAppService (launch-at-login) and TCC can attribute to.
#
# It is also the scriptable seam for the release pipeline (bead ge2) and for
# signing/notarization (bead 4fd) and Sparkle (bead 7hr) layered on top later.
#
# Usage:
#   scripts/build-app.sh            # release build → build/Haunts.app, then verify
#   scripts/build-app.sh --debug    # use the debug binary (faster, for iterating)
#   scripts/build-app.sh --open     # build, verify, then `open` the bundle
#
set -euo pipefail

# --- locations -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PKG="$REPO_ROOT/app"
PACKAGING="$REPO_ROOT/packaging"
OUT_DIR="$REPO_ROOT/build"
APP="$OUT_DIR/Haunts.app"
ICON_SRC="$REPO_ROOT/app-icon.png"

CONFIG="release"
DO_OPEN=0
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --open)  DO_OPEN=1 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\033[1;38;5;208m▸\033[0m %s\n' "$1"; }   # ember-ish arrow

# --- 1. build the binary ---------------------------------------------------
step "swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$APP_PKG"
BIN="$(swift build -c "$CONFIG" --package-path "$APP_PKG" --show-bin-path)/zforfinder"
[ -x "$BIN" ] || { echo "binary not found at $BIN" >&2; exit 1; }

# --- 2. lay out the bundle skeleton ----------------------------------------
step "assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Haunts"      # CFBundleExecutable = Haunts
cp "$PACKAGING/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# --- 3. app icon: app-icon.png → Haunts.icns -------------------------------
step "rendering Haunts.icns from app-icon.png"
[ -f "$ICON_SRC" ] || { echo "missing $ICON_SRC" >&2; exit 1; }
ICONSET="$(mktemp -d)/Haunts.iconset"
mkdir -p "$ICONSET"
# Standard macOS icon ladder: 16…512 at @1x and @2x.
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" "$ICON_SRC" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Haunts.icns"
rm -rf "$(dirname "$ICONSET")"

# --- 4. ember accent: Assets.xcassets → Assets.car -------------------------
# Compiles the AccentColor colorset (#E8732C) into the bundle. Combined with
# NSAccentColorName=AccentColor in Info.plist, this is what tints the Preferences
# selected-tab pill ember instead of macOS system blue (bead qvg) — the one
# control SwiftUI .tint() can't reach.
step "compiling Assets.car (AccentColor = #E8732C) with actool"
actool "$PACKAGING/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon Haunts 2>/dev/null \
    --output-partial-info-plist "$(mktemp)" \
    --output-format human-readable-text >/dev/null 2>&1 || \
actool "$PACKAGING/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$(mktemp)" \
    --output-format human-readable-text >/dev/null
[ -f "$APP/Contents/Resources/Assets.car" ] || { echo "actool did not emit Assets.car" >&2; exit 1; }

# Touch the bundle so Launch Services re-reads Info.plist (icon/identity).
touch "$APP"

# --- 5. verify the assembled bundle ----------------------------------------
step "verifying bundle"
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1" >&2; fail=1; fi; }

PL="$APP/Contents/Info.plist"
check "Info.plist is valid"            "plutil -lint '$PL' >/dev/null"
check "executable present & runnable"  "[ -x '$APP/Contents/MacOS/Haunts' ]"
check "Haunts.icns present"            "[ -f '$APP/Contents/Resources/Haunts.icns' ]"
check "Assets.car present"             "[ -f '$APP/Contents/Resources/Assets.car' ]"
check "bundle id = app.gethaunts.Haunts" \
      "[ \"\$(plutil -extract CFBundleIdentifier raw -o - '$PL')\" = 'app.gethaunts.Haunts' ]"
check "LSUIElement = true (agent app)" \
      "[ \"\$(plutil -extract LSUIElement raw -o - '$PL')\" = 'true' ]"
check "NSAccentColorName = AccentColor" \
      "[ \"\$(plutil -extract NSAccentColorName raw -o - '$PL')\" = 'AccentColor' ]"
check "CFBundleIconFile = Haunts"      \
      "[ \"\$(plutil -extract CFBundleIconFile raw -o - '$PL')\" = 'Haunts' ]"
VER="$(plutil -extract CFBundleShortVersionString raw -o - "$PL")"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$PL")"
echo "  • version $VER ($BUILD)"

if [ "$fail" -ne 0 ]; then echo "VERIFY FAILED" >&2; exit 1; fi
step "OK → $APP"
echo "    open '$APP'   # or: open -a Haunts"

[ "$DO_OPEN" -eq 1 ] && { pkill -9 -x Haunts 2>/dev/null || true; sleep 0.3; open "$APP"; }
exit 0
