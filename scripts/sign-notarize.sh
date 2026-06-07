#!/usr/bin/env bash
#
# sign-notarize.sh — sign, notarize, and staple build/Haunts.app for Gatekeeper-
# clean distribution on other Macs. Runs AFTER scripts/build-app.sh has produced
# build/Haunts.app.
#
# This is a LOCAL release step, not a CI job: it needs the Developer ID signing
# identity in the login keychain + the notarytool app-specific password + network
# access to Apple's notary service. The GitHub CI runner has none of these, so CI
# stays build+test only and never runs this script.
#
# Credentials are REUSED from the existing lpx-explorer Developer ID setup (same
# Apple account / Team ID) — see ../lpx-explorer/scripts/build-release.sh. They
# live in the login keychain under account=lpx-explorer and are read into shell
# vars at runtime; they are NEVER printed.
#
# Usage:
#   scripts/build-app.sh           # produce build/Haunts.app first
#   scripts/sign-notarize.sh       # sign + notarize + staple it
#   scripts/sign-notarize.sh --sign-only   # sign + verify, skip notarization
#
# Refs: bead z-for-finder-4fd
set -euo pipefail

# --- locations -------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$REPO_ROOT/build/Haunts.app"
# app/Entitlements.plist — Developer-ID (NON-sandboxed) hardened-runtime
# entitlements. It carries exactly ONE key:
# com.apple.security.automation.apple-events=true, which the hardened runtime
# requires for the app to send Apple Events to Finder (FinderTracker reads the
# `target of front Finder window`); it pairs with NSAppleEventsUsageDescription
# in Info.plist. Deliberately NO com.apple.security.app-sandbox (this is Developer
# ID distribution, and a sandbox would block the editor/shell warm-seed reads).
# The file is kept COMMENT-FREE: codesign's AMFI plist parser rejects XML comments.
ENTITLEMENTS="$REPO_ROOT/app/Entitlements.plist"

# Reused Developer ID identity + Apple Team (same account as lpx-explorer).
SIGNING_IDENTITY="Developer ID Application: RHYDIAN GWYN LEWIS (87A97X8DAG)"
TEAM_ID="87A97X8DAG"
KEYCHAIN_ACCOUNT="lpx-explorer"

SIGN_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --sign-only) SIGN_ONLY=1 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\033[1;38;5;208m▸\033[0m %s\n' "$1"; }   # ember-ish arrow
die()  { echo "✗ $1" >&2; exit 1; }

# --- 0. preconditions ------------------------------------------------------
[ -d "$APP" ]          || die "no $APP — run scripts/build-app.sh first"
[ -f "$ENTITLEMENTS" ] || die "no $ENTITLEMENTS"

# Signing identity must be present in the keychain. The display name can be
# AMBIGUOUS — this Mac carries two Developer ID certs with the identical name
# (a duplicate import; same Team, same expiry), which makes codesign refuse a
# by-name --sign. Resolve to the first matching SHA-1 hash and sign by that so
# the choice is unambiguous and deterministic.
SIGNING_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "$SIGNING_IDENTITY" | head -1 | awk '{print $2}')"
[ -n "$SIGNING_HASH" ] || die "signing identity not found: $SIGNING_IDENTITY"
echo "  ✓ signing identity: $SIGNING_IDENTITY ($SIGNING_HASH)"

# --- 1a. sign Sparkle.framework INSIDE-OUT (bead 7hr) ----------------------
# The outer codesign does NOT recurse into nested frameworks, so Sparkle's own
# helper bundles must be signed FIRST (each with hardened runtime + timestamp)
# so the framework seal covers them and the outer app seal covers the framework.
# Order is inside-out: XPC services + Updater.app + Autoupdate, THEN the
# framework itself. Per ../lpx-explorer/scripts/build-release.sh.
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    step "codesign Sparkle.framework (nested helpers first, inside-out)"
    codesign --force --options runtime --timestamp --sign "$SIGNING_HASH" \
        "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
        "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" \
        "$SPARKLE_FW/Versions/B/Updater.app" \
        "$SPARKLE_FW/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp --sign "$SIGNING_HASH" \
        "$SPARKLE_FW"
    echo "  ✓ Sparkle.framework + nested helpers signed"
else
    echo "  • no Sparkle.framework embedded — skipping nested signing"
fi

# --- 1b. sign the app: deep, hardened runtime + secure timestamp -----------
step "codesign (Developer ID, hardened runtime, timestamp, entitlements)"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_HASH" \
    "$APP"

# --- 2. verify the signature ----------------------------------------------
step "codesign --verify --strict --deep"
codesign --verify --strict --deep --verbose=2 "$APP"
# Confirm hardened runtime (CodeDirectory flag 0x10000 = runtime) + the entitlement.
# Capture first, then grep: `... | grep -q` under `set -o pipefail` reports failure
# when grep's early exit SIGPIPEs codesign, even on a match.
SIG_INFO="$(codesign -d --verbose=2 "$APP" 2>&1)"
echo "$SIG_INFO" | grep -q 'flags=.*runtime' \
    || die "hardened runtime flag not set on the signature"
SIG_ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
echo "$SIG_ENT" | grep -q 'com.apple.security.automation.apple-events' \
    || die "apple-events entitlement missing from the signature"
echo "  ✓ signed, hardened runtime, apple-events entitlement present"

if [ "$SIGN_ONLY" -eq 1 ]; then
    step "sign-only: skipping notarization"
    exit 0
fi

# --- 3. load notary credentials (NEVER printed) ----------------------------
step "loading notary credentials from keychain (account=$KEYCHAIN_ACCOUNT)"
APPLE_ID="$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s APPLE_ID -w 2>/dev/null || true)"
APPLE_PASSWORD="$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s APPLE_PASSWORD -w 2>/dev/null || true)"
[ -n "$APPLE_ID" ]       || die "keychain APPLE_ID missing (account=$KEYCHAIN_ACCOUNT)"
[ -n "$APPLE_PASSWORD" ] || die "keychain APPLE_PASSWORD missing (account=$KEYCHAIN_ACCOUNT)"
echo "  ✓ APPLE_ID + APPLE_PASSWORD loaded (not shown)"

# --- 4. notarize: zip the signed .app, submit, wait ------------------------
# Notarization needs a container — ditto a zip preserving the bundle's symlinks
# and code signature, submit it, and block until Apple returns a verdict.
ZIP="$REPO_ROOT/build/Haunts.zip"
rm -f "$ZIP"
step "zipping signed bundle for notary submission"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

step "xcrun notarytool submit --wait (hits Apple's notary service, ~1–5 min)"
set +e
NOTARY_OUT="$(xcrun notarytool submit "$ZIP" \
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
rm -f "$ZIP"

# --- 5. staple the ticket --------------------------------------------------
step "xcrun stapler staple"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- 6. final Gatekeeper assessment ---------------------------------------
step "final verification"
codesign --verify --strict --deep --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo ""
step "DONE → $APP is signed, notarized (Accepted), and stapled."
echo "    spctl --assess --type execute '$APP'  # → accepted"
