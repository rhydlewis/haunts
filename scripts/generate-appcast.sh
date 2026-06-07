#!/usr/bin/env bash
#
# generate-appcast.sh — emit a Sparkle appcast.xml for a built Haunts DMG.
#
# Reads the DMG, runs Sparkle's sign_update (EdDSA, Sparkle's DEFAULT keychain
# account = the SHARED key whose public half is SUPublicEDKey in Info.plist) to
# produce the signature + length, and writes a single-item appcast referencing
# the GitHub Release download URL. Version comes from the bundle Info.plist
# (the single source of truth the release pipeline, bead ge2, bumps).
#
# Modelled on ../lpx-explorer/scripts/generate-appcast.sh.
#
# Usage:
#   scripts/generate-appcast.sh path/to/Haunts.dmg
#   DMG_PATH=path/to/Haunts.dmg scripts/generate-appcast.sh
#
# Env overrides (all optional):
#   VERSION                   — semver; default = CFBundleShortVersionString
#   RELEASE_NOTES             — plain text for <description>
#   APPCAST_DOWNLOAD_BASE_URL — base for the <enclosure url>; default points at
#                               the GitHub release. The LOCAL self-update test
#                               sets this to its http://localhost:PORT server.
#   APPCAST_OUT               — output path; default = <dmg dir>/appcast.xml
#   SPARKLE_ACCOUNT           — keychain account for the signing key. DEFAULT IS
#                               EMPTY = Sparkle's default account, the SHARED key
#                               (flowcus-v2 + lpx-explorer) whose PUBLIC half is
#                               SUPublicEDKey in packaging/Info.plist. DO NOT set
#                               this to "haunts": that abandoned key does NOT match
#                               the shipped SUPublicEDKey, so updates signed with it
#                               fail signature verification on every user's Mac.
#
# Refs: bead z-for-finder-7hr
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PKG="$REPO_ROOT/app"
INFO_PLIST="$REPO_ROOT/packaging/Info.plist"

step() { printf '\033[1;38;5;208m▸\033[0m %s\n' "$1"; }
die()  { echo "✗ $1" >&2; exit 1; }

# --- inputs ----------------------------------------------------------------
DMG_PATH="${1:-${DMG_PATH:-}}"
[ -n "$DMG_PATH" ] || die "usage: generate-appcast.sh <path-to-dmg>  (or set DMG_PATH)"
[ -f "$DMG_PATH" ] || die "DMG not found: $DMG_PATH"

VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")}"
BUILD="$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"
RELEASE_NOTES="${RELEASE_NOTES:-Bug fixes and improvements.}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-}"   # empty = Sparkle's default keychain key (shared with flowcus/lpx)
MIN_SYSTEM_VERSION="14.0"

DMG_FILENAME="$(basename "$DMG_PATH")"
# GitHub Releases turns spaces in asset names into dots on upload; mirror that.
URL_FILENAME="${DMG_FILENAME// /.}"
DEFAULT_BASE="https://github.com/rhydlewis/haunts/releases/download/v${VERSION}"
APPCAST_DOWNLOAD_BASE_URL="${APPCAST_DOWNLOAD_BASE_URL:-$DEFAULT_BASE}"
DOWNLOAD_URL="${APPCAST_DOWNLOAD_BASE_URL%/}/${URL_FILENAME}"
OUTPUT_PATH="${APPCAST_OUT:-$(dirname "$DMG_PATH")/appcast.xml}"

# RFC-822 pubDate. (No fixed date input — release pipeline stamps at build time.)
PUB_DATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"

# --- locate sign_update from the Sparkle SPM artifact ----------------------
# `swift build` (run by build-app.sh) extracts the Sparkle artifact, which ships
# the signing tools. Resolve the path rather than depending on a sibling repo.
SIGN_UPDATE="$(find "$APP_PKG/.build/artifacts" -path '*/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1)"
[ -x "${SIGN_UPDATE:-}" ] || die "sign_update not found under $APP_PKG/.build/artifacts — run scripts/build-app.sh first"

# --- sign ------------------------------------------------------------------
step "sign_update (EdDSA, keychain account=$SPARKLE_ACCOUNT) on $DMG_FILENAME"
# Prints e.g.  sparkle:edSignature="…" length="…"  — inlined into the enclosure.
SIGN_OUTPUT="$("$SIGN_UPDATE" ${SPARKLE_ACCOUNT:+--account "$SPARKLE_ACCOUNT"} "$DMG_PATH")"
echo "  $SIGN_OUTPUT"
echo "$SIGN_OUTPUT" | grep -q 'sparkle:edSignature=' || die "sign_update did not emit an EdDSA signature"

# --- emit appcast ----------------------------------------------------------
step "writing $OUTPUT_PATH"
cat > "$OUTPUT_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Haunts Updates</title>
        <link>https://gethaunts.app/appcast.xml</link>
        <description>Updates for Haunts — a fast keyboard launcher for your Finder folders.</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
            <description><![CDATA[${RELEASE_NOTES}]]></description>
            <enclosure url="${DOWNLOAD_URL}" type="application/octet-stream" ${SIGN_OUTPUT} />
        </item>
    </channel>
</rss>
EOF

# Validate the XML we just wrote.
xmllint --noout "$OUTPUT_PATH" 2>/dev/null || die "emitted appcast is not well-formed XML"

step "OK → $OUTPUT_PATH  (v$VERSION build $BUILD)"
echo ""
cat "$OUTPUT_PATH"
