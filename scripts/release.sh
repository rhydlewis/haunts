#!/usr/bin/env bash
#
# release.sh — one-command Haunts release pipeline (bead ge2). Runs LOCALLY
# (needs the Developer ID identity + notarytool creds + the Sparkle EdDSA key);
# there is no CI release job.
#
# It chains the existing scripts and then stages the result into the gethaunts.app
# SITE repo, where the DMG is HOSTED (committed under src/assets/dmg/, served by
# Netlify) — NOT on GitHub Releases. The app repo only gets a git TAG.
#
#   bump → build-app → sign-notarize(app) → make-dmg → generate-appcast
#        → update-site(SITE repo working tree) → [--publish: push both repos + tag]
#
# Usage:
#   scripts/release.sh                              # DRY-RUN, no version bump
#   scripts/release.sh --bump patch                # DRY-RUN, bump patch
#   scripts/release.sh --notes "- fix: Foo"        # supply changelog notes
#   scripts/release.sh --publish                   # GO LIVE (push + deploy + tag)
#   scripts/release.sh --bump minor --publish --notes "- feat: Bar"
#
# Flags:
#   --bump patch|minor|major   bump version+build in packaging/Info.plist
#   --notes "<lines>"          changelog lines ("- type: description"); also the
#                              appcast <description>
#   --title "<title>"          changelog entry title (default: derived from notes)
#   --publish                  push app (main + tag) and site (Netlify deploy);
#                              WITHOUT it nothing is pushed (dry-run)
#   --site-path <dir>          gethaunts.app repo (default: ../gethaunts-dot-app)
#
# Refs: bead z-for-finder-ge2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST="$REPO_ROOT/packaging/Info.plist"
PB=/usr/libexec/PlistBuddy

BUMP=""
NOTES=""
TITLE=""
PUBLISH=0
SITE_PATH="${SITE_PATH:-$REPO_ROOT/../gethaunts-dot-app}"

while [ $# -gt 0 ]; do
    case "$1" in
        --bump)      BUMP="${2:?--bump needs patch|minor|major}"; shift 2 ;;
        --notes)     NOTES="${2:-}"; shift 2 ;;
        --title)     TITLE="${2:-}"; shift 2 ;;
        --publish)   PUBLISH=1; shift ;;
        --site-path) SITE_PATH="${2:?}"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

step() { printf '\033[1;38;5;208m▸\033[0m %s\n' "$1"; }
die()  { echo "✗ $1" >&2; exit 1; }

[ -f "$INFO_PLIST" ] || die "no $INFO_PLIST"
SITE_PATH="$(cd "$SITE_PATH" && pwd)" || die "site repo not found: $SITE_PATH"
[ -d "$SITE_PATH/src" ] || die "site repo has no src/: $SITE_PATH"

if [ "$PUBLISH" -eq 1 ]; then
    echo "🚀 PUBLISH MODE — will push app (main + tag) and site (Netlify deploy)"
else
    echo "🧪 DRY-RUN — build + stage site files locally; push NOTHING"
fi
echo ""

# --- 1. version (optional bump) --------------------------------------------
CUR_VERSION="$($PB -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
CUR_BUILD="$($PB -c 'Print :CFBundleVersion' "$INFO_PLIST")"

if [ -n "$BUMP" ]; then
    IFS='.' read -r MA MI PA <<< "$CUR_VERSION"
    case "$BUMP" in
        patch) PA=$((PA+1)) ;;
        minor) MI=$((MI+1)); PA=0 ;;
        major) MA=$((MA+1)); MI=0; PA=0 ;;
        *) die "invalid --bump: $BUMP (patch|minor|major)" ;;
    esac
    VERSION="$MA.$MI.$PA"
    BUILD=$((CUR_BUILD+1))
    step "version bump ($BUMP): $CUR_VERSION ($CUR_BUILD) → $VERSION ($BUILD)"
    $PB -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
    $PB -c "Set :CFBundleVersion $BUILD" "$INFO_PLIST"
    plutil -lint "$INFO_PLIST" >/dev/null || die "Info.plist invalid after bump"
else
    VERSION="$CUR_VERSION"
    BUILD="$CUR_BUILD"
    step "version (no bump): $VERSION ($BUILD)"
fi
TAG="v$VERSION"
DMG="$REPO_ROOT/build/Haunts_${VERSION}_universal.dmg"
APPCAST="$REPO_ROOT/build/appcast.xml"

# --- 2. build + sign the app -----------------------------------------------
step "build-app.sh"
"$SCRIPT_DIR/build-app.sh"
step "sign-notarize.sh (app)"
"$SCRIPT_DIR/sign-notarize.sh"

# --- 3. make + notarize + staple the DMG -----------------------------------
step "make-dmg.sh"
DMG_OUT="$DMG" "$SCRIPT_DIR/make-dmg.sh"
[ -f "$DMG" ] || die "expected DMG not produced: $DMG"

# --- 4. appcast (EdDSA, default Sparkle key, gethaunts.app enclosure) -------
step "generate-appcast.sh"
APPCAST_RELEASE_NOTES="${NOTES:+$NOTES}"
[ -z "$APPCAST_RELEASE_NOTES" ] && \
    APPCAST_RELEASE_NOTES="Haunts $VERSION — see https://gethaunts.app/changelog/ for details."
APPCAST_DOWNLOAD_BASE_URL="https://gethaunts.app/assets/dmg" \
APPCAST_OUT="$APPCAST" \
RELEASE_NOTES="$APPCAST_RELEASE_NOTES" \
    "$SCRIPT_DIR/generate-appcast.sh" "$DMG"
[ -f "$APPCAST" ] || die "appcast not produced: $APPCAST"

# --- 5. stage into the SITE repo working tree ------------------------------
step "update-site.mjs → $SITE_PATH"
VERSION="$VERSION" BUILD="$BUILD" DMG_PATH="$DMG" APPCAST_PATH="$APPCAST" \
SITE_PATH="$SITE_PATH" NOTES="$NOTES" TITLE="$TITLE" \
    node "$SCRIPT_DIR/update-site.mjs"

# --- 6. publish or print dry-run plan --------------------------------------
echo ""
if [ "$PUBLISH" -eq 1 ]; then
    # PRECONDITION: the SITE's release.js must ALREADY derive the download URL
    # from gethaunts.app AND be committed. This script only commits the per-release
    # artifacts (dmg/appcast/latest.json/changes.json) — it deliberately does NOT
    # commit source files like release.js/llms.njk (which can be entangled with
    # unrelated site WIP). If the repoint is missing or uncommitted, the deployed
    # site would still build the old GitHub-Releases URL and the download 404s.
    REL_JS="$SITE_PATH/src/_data/release.js"
    grep -q 'gethaunts\.app/assets/dmg' "$REL_JS" \
        || die "site release.js does not point at gethaunts.app/assets/dmg — repoint it first ($REL_JS)"
    git -C "$SITE_PATH" diff --quiet -- src/_data/release.js src/llms.njk \
        || die "site repoint (release.js/llms.njk) is uncommitted — commit it before publishing so the live site serves the right download URL"

    step "PUBLISH: app repo ($REPO_ROOT)"
    cd "$REPO_ROOT"
    if [ -n "$BUMP" ]; then
        git add "$INFO_PLIST"
        git commit -m "Release $TAG — bump to $VERSION ($BUILD)

Co-Authored-By: Claude <noreply@anthropic.com>"
    fi
    git tag -a "$TAG" -m "Haunts $VERSION" 2>/dev/null || die "tag $TAG already exists"
    git push origin HEAD
    git push origin "$TAG"

    step "PUBLISH: site repo ($SITE_PATH) → Netlify"
    cd "$SITE_PATH"
    git add src/assets/dmg/"$(basename "$DMG")" src/appcast.xml src/latest.json src/_data/changes.json
    git commit -m "Release Haunts $VERSION

Co-Authored-By: Claude <noreply@anthropic.com>"
    git push origin HEAD

    echo ""
    step "PUBLISHED $TAG. Netlify is deploying; appcast/latest.json go live in ~1–2 min (max-age=300)."
    echo "    Verify: curl -s https://gethaunts.app/appcast.xml | head"
else
    step "DRY-RUN complete — nothing pushed. To go live:"
    echo "    scripts/release.sh ${BUMP:+--bump $BUMP }${NOTES:+--notes \"$NOTES\" }--publish"
    echo ""
    echo "  Staged but uncommitted in the SITE repo ($SITE_PATH):"
    echo "    src/assets/dmg/$(basename "$DMG"), src/appcast.xml, src/latest.json, src/_data/changes.json"
    echo "  Revert site staging:   git -C '$SITE_PATH' checkout -- src/ && git -C '$SITE_PATH' clean -fd src/assets/dmg"
    if [ -n "$BUMP" ]; then
        echo "  Revert version bump:   $PB -c 'Set :CFBundleShortVersionString $CUR_VERSION' '$INFO_PLIST'; $PB -c 'Set :CFBundleVersion $CUR_BUILD' '$INFO_PLIST'"
    fi
fi

echo ""
step "Summary: $TAG · build $BUILD · DMG $(basename "$DMG") · mode $([ "$PUBLISH" -eq 1 ] && echo PUBLISHED || echo DRY-RUN)"
