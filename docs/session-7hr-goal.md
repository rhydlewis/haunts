GOAL: Add Sparkle auto-updates to Haunts (bead 7hr). gethaunts.app is LIVE and hosts the appcast. Repo: /Users/rhyd/code/z-for-finder (Swift package app/; GitHub rhydlewis/haunts). Test-first; small commits to main; end on GREEN CI.

CONTEXT: Haunts.app is already a signed+notarized bundle (v3n/4fd; build via scripts/build-app.sh then scripts/sign-notarize.sh). Info.plist already has SUFeedURL=https://gethaunts.app/appcast.xml. Reuse the Developer ID cert + notarytool creds from lpx-explorer (Team 87A97X8DAG; keychain account 'lpx-explorer' → APPLE_ID/APPLE_PASSWORD).

READ FIRST: `bd show z-for-finder-7hr`; scripts/build-app.sh + scripts/sign-notarize.sh (the Sparkle nested-signing PLACEHOLDER is already in sign-notarize.sh); ../lpx-explorer/scripts/build-release.sh (Sparkle.framework nested codesign) + ../lpx-explorer/scripts/generate-appcast.sh (sign_update + appcast template — lifts near-verbatim); ../lpx-explorer/src-tauri/sparkle-bin/ (sign_update + generate_keys tools).

BUILD:
1. Add Sparkle (sparkle-project/Sparkle) as an SPM dependency in app/Package.swift; link into the zforfinder executable target.
2. EdDSA key — NEW for Haunts (do NOT reuse lpx's): run Sparkle generate_keys → stores the PRIVATE key in the login keychain, prints the PUBLIC key. Put the public key in Info.plist as SUPublicEDKey. Commit ONLY the public key; NEVER the private key. Report the public key + REMIND the user to back up/export the private key (it signs all future updates).
3. AppDelegate: an SPUStandardUpdaterController + a "Check for Updates…" status-menu item (action checkForUpdates:). Confirm SUFeedURL + SUPublicEDKey are read at runtime.
4. appcast: add scripts/generate-appcast.sh modelled on lpx's — given a built DMG, run sign_update (EdDSA) and emit appcast.xml with the GitHub-releases download URL + version from Info.plist.
5. Signing: extend scripts/sign-notarize.sh to sign the embedded Sparkle.framework FIRST (its XPCServices Downloader+Installer, Updater.app, Autoupdate, then the framework) with --options runtime --timestamp, BEFORE the app — per lpx build-release.sh. Re-notarize → must stay Accepted (Sparkle adds nested code).

OUT OF SCOPE: the release pipeline / version bump / GitHub Release (ge2 — next bead). The HOSTED end-to-end test needs a published release (ge2); do a LOCAL self-update test here instead.

GOTCHAS:
- Run the app as a background task (foreground nohup gets killed); FIRST `pkill -9 -x zforfinder`; one instance only (process is named zforfinder).
- Keep ZFFEngine pure. Swift Testing, not XCTest. 167 tests must stay green.
- NEVER commit/print the EdDSA private key or the notarytool password.
- Sparkle.framework MUST be (nested-)signed or notarization/Gatekeeper fails.

DONE = each TRUE + VERIFIED: Sparkle linked; SUPublicEDKey in Info.plist (private key in keychain; back-up reminded); "Check for Updates…" menu item present and opens Sparkle's UI; the signed app (Sparkle.framework signed too) passes codesign --verify --strict --deep AND notarytool returns Accepted AND spctl accepts; scripts/generate-appcast.sh emits a valid EdDSA-signed appcast.xml; a LOCAL self-update works (serve a higher-version appcast+DMG over local HTTP → the running app detects, verifies the EdDSA sig, downloads, relaunches updated); 167 tests green; pushed; CI green. (Hosted gethaunts.app test deferred to ge2.)

VERIFY, DON'T ASSERT: actually run the local self-update (two versions + a local HTTP server for appcast/DMG) and report what happened; paste codesign/notarytool/spctl output. If a step can't run (creds/network), report BLOCKED — do not fake it.

HONESTY: a prior run here faked stats — unacceptable. Report only what you built/tested/ran; state partials plainly (e.g. hosted test deferred to ge2). Commit only green. Trunk-based small commits to main (no PR). End commits: Co-Authored-By: Claude <noreply@anthropic.com>
