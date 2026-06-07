#!/usr/bin/env bash
#
# make-dmg.sh — package the signed build/Haunts.app into a distributable DMG,
# then sign + notarize + staple the DMG itself so it is Gatekeeper-clean offline
# on any Mac. Runs AFTER scripts/build-app.sh and scripts/sign-notarize.sh.
#
# Haunts is a pure SwiftPM app, so (unlike the Tauri apps lpx-explorer/flowcus)
# nothing produces a DMG for us — this script is that missing step (bead ge2).
#
# Like sign-notarize.sh this is a LOCAL release step: it needs the Developer ID
# identity + the notarytool app-specific password (login keychain, account
# 'lpx-explorer') + network. Credentials are read at runtime and NEVER printed.
#
# Usage:
#   scripts/make-dmg.sh                       # → build/Haunts_<ver>_universal.dmg
#   scripts/make-dmg.sh --no-notarize         # build + sign the DMG, skip notary
#   DMG_OUT=path/to.dmg scripts/make-dmg.sh   # override output path
#
# Refs: bead z-for-finder-ge2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$REPO_ROOT/build/Haunts.app"
INFO_PLIST="$REPO_ROOT/packaging/Info.plist"

SIGNING_IDENTITY="Developer ID Application: RHYDIAN GWYN LEWIS (87A97X8DAG)"
TEAM_ID="87A97X8DAG"
KEYCHAIN_ACCOUNT="lpx-explorer"

DO_NOTARIZE=1
for arg in "$@"; do
    case "$arg" in
        --no-notarize) DO_NOTARIZE=0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\033[1;38;5;208m▸\033[0m %s\n' "$1"; }
die()  { echo "✗ $1" >&2; exit 1; }

# --- 0. preconditions ------------------------------------------------------
[ -d "$APP" ] || die "no $APP — run scripts/build-app.sh && scripts/sign-notarize.sh first"
# The app must already be signed (and ideally notarized+stapled) before we wrap
# it: a DMG only carries whatever is inside it.
codesign --verify --strict --deep "$APP" 2>/dev/null \
    || die "$APP is not validly signed — run scripts/sign-notarize.sh first"

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
DMG_OUT="${DMG_OUT:-$REPO_ROOT/build/Haunts_${VERSION}_universal.dmg}"

# Resolve the signing identity to an unambiguous SHA-1 (this Mac has a duplicate
# Developer ID cert with the same display name — by-name signing is refused).
SIGNING_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "$SIGNING_IDENTITY" | head -1 | awk '{print $2}')"
[ -n "$SIGNING_HASH" ] || die "signing identity not found: $SIGNING_IDENTITY"
echo "  ✓ signing identity: $SIGNING_IDENTITY ($SIGNING_HASH)"

# --- 1. stage the DMG contents (app + drag-to-/Applications) ---------------
step "staging DMG payload (Haunts.app + Applications symlink)"
STAGE="$(mktemp -d)"
/usr/bin/ditto "$APP" "$STAGE/Haunts.app"
ln -s /Applications "$STAGE/Applications"

# --- 2. build the compressed, read-only DMG --------------------------------
step "hdiutil create → $(basename "$DMG_OUT")"
rm -f "$DMG_OUT"
hdiutil create \
    -volname "Haunts" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_OUT" >/dev/null
rm -rf "$STAGE"

# --- 3. sign the DMG itself ------------------------------------------------
step "codesign the DMG (Developer ID, timestamp)"
codesign --force --timestamp --sign "$SIGNING_HASH" "$DMG_OUT"
codesign --verify --strict --verbose=2 "$DMG_OUT"

if [ "$DO_NOTARIZE" -eq 0 ]; then
    step "--no-notarize: DMG built + signed, skipping notary → $DMG_OUT"
    exit 0
fi

# --- 4. load notary credentials (NEVER printed) ----------------------------
step "loading notary credentials from keychain (account=$KEYCHAIN_ACCOUNT)"
APPLE_ID="$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s APPLE_ID -w 2>/dev/null || true)"
APPLE_PASSWORD="$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s APPLE_PASSWORD -w 2>/dev/null || true)"
[ -n "$APPLE_ID" ]       || die "keychain APPLE_ID missing (account=$KEYCHAIN_ACCOUNT)"
[ -n "$APPLE_PASSWORD" ] || die "keychain APPLE_PASSWORD missing (account=$KEYCHAIN_ACCOUNT)"
echo "  ✓ APPLE_ID + APPLE_PASSWORD loaded (not shown)"

# --- 5. notarize the DMG directly ------------------------------------------
step "xcrun notarytool submit --wait (Apple notary, ~1–5 min)"
set +e
NOTARY_OUT="$(xcrun notarytool submit "$DMG_OUT" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait 2>&1)"
NOTARY_RC=$?
set -e
echo "$NOTARY_OUT"

if [ "$NOTARY_RC" -ne 0 ] || ! echo "$NOTARY_OUT" | grep -q 'status: Accepted'; then
    SUBMISSION_ID="$(echo "$NOTARY_OUT" | awk '/id:/ {print $2; exit}')"
    echo "✗ notarization did NOT return Accepted." >&2
    if [ -n "${SUBMISSION_ID:-}" ]; then
        echo "  fetching notary log for $SUBMISSION_ID ..." >&2
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$TEAM_ID" >&2 || true
    fi
    exit 1
fi

# --- 6. staple + final Gatekeeper assessment -------------------------------
step "xcrun stapler staple"
xcrun stapler staple "$DMG_OUT"
xcrun stapler validate "$DMG_OUT"

step "spctl assessment (Gatekeeper, offline)"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_OUT"

echo ""
step "DONE → $DMG_OUT is signed, notarized (Accepted), and stapled."
