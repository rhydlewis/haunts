GOAL: One-command release pipeline for Haunts (bead ge2) that ships v0.1 and completes Sparkle's HOSTED self-update test. Two repos: APP /Users/rhyd/code/z-for-finder (rhydlewis/haunts; Swift pkg in app/), SITE /Users/rhyd/code/gethaunts-dot-app (rhydlewis/gethaunts-dot-app; Eleventy on Netlify, live at gethaunts.app). Small commits to main; end GREEN CI.

HOSTING MODEL (overrides older notes): DMG is served from gethaunts.app, NOT GitHub Releases. Commit it into the SITE repo at src/assets/dmg/Haunts_X.Y.Z_universal.dmg (flowcus pattern); Netlify serves gethaunts.app/assets/dmg/... . APP repo: TAG ONLY (git tag vX.Y.Z + push tag) — NO GitHub Release, NO dmg asset anywhere.

READ FIRST: bd show z-for-finder-ge2; app scripts/{build-app,sign-notarize,generate-appcast}.sh; ../gethaunts-dot-app/src/_data/release.js + src/latest.json + src/_data/changes.json + src/appcast.xml + netlify.toml; ../flowcus-v2/scripts/{release.sh,update-site.js} (SHAPE only).

VERSION source of truth = packaging/Info.plist: CFBundleShortVersionString (semver) + CFBundleVersion (build). Bump via PlistBuddy/agvtool, NOT npm. v0.1 ships the values already set (0.1.0 build 1) — confirm, do not re-bump.

BUILD scripts/release.sh (dry-run default; --publish to go live; --bump patch|minor|major; --notes "..."):
1. bump Info.plist version+build only if --bump.
2. scripts/build-app.sh, then sign the app (scripts/sign-notarize.sh).
3. NEW CODE (no dmg-maker exists yet — Tauri gave lpx/flowcus theirs free): make a DMG (hdiutil create) of the signed Haunts.app named Haunts_X.Y.Z_universal.dmg, then NOTARIZE + STAPLE the DMG ITSELF (reuse sign-notarize creds: account lpx-explorer, Team 87A97X8DAG). DMG must be Gatekeeper-clean offline: stapler validate AND spctl --assess pass.
4. scripts/generate-appcast.sh with APPCAST_DOWNLOAD_BASE_URL=https://gethaunts.app/assets/dmg -> appcast.xml. Sign with the DEFAULT Sparkle key (NO --account; matches SUPublicEDKey already in Info.plist). Do NOT pass --account haunts — that abandoned key fails to match, so every user's update fails sig verification.
5. PUBLISH to SITE repo: copy DMG -> src/assets/dmg/; overwrite src/appcast.xml with the generated one; update src/latest.json (version, build, filename, publishedAt, released:true); prepend a changes.json entry from --notes. ONE-TIME FIX: repoint src/_data/release.js (+ src/llms.njk wording) so downloadUrl = gethaunts.app/assets/dmg/<filename>, NOT github releases.
6. --publish ONLY: commit+push the app version bump to main + push tag vX.Y.Z; commit+push the site repo (Netlify auto-deploys). Dry-run: do all above locally, push NOTHING, print the publish commands.

OUT OF SCOPE: GoatCounter (6h7), Open-With (2cp).

GOTCHAS:
- Run the app as a background task (foreground nohup gets killed); FIRST pkill -9 -x zforfinder; one instance only.
- Keep ZFFEngine pure; Swift Testing not XCTest; 167 tests stay green.
- NEVER print/commit the notarytool password or any EdDSA private key.
- Netlify caches /appcast.xml + /latest.json (max-age=300) — after deploy, wait for it live before the hosted test.

DONE = each VERIFIED: scripts/release.sh exists (dry-run + --publish); a full DRY-RUN produces a notarized+stapled Haunts_0.1.0_universal.dmg (paste spctl + stapler validate) and a valid EdDSA appcast.xml (xmllint clean; enclosure on gethaunts.app); site files updated right; HOSTED Sparkle test PASSES — publish v0.1, then an OLDER local build's Check for Updates hits gethaunts.app/appcast.xml, verifies the sig, downloads, relaunches updated; 167 tests green; pushed; CI green.

VERIFY, DON'T ASSERT: actually run the dry-run AND the hosted self-update; paste spctl/stapler/notarytool/xmllint output and what Sparkle did. If a step can't run, report BLOCKED — never fake it.

HONESTY: a prior run faked notarization stats — unacceptable. Report only what you built/ran; state partials plainly. Commit only green to main (no PR). End commits: Co-Authored-By: Claude <noreply@anthropic.com>
