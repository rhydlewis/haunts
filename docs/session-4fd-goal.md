GOAL: Sign + notarize + staple Haunts.app (bead 4fd) so it runs Gatekeeper-clean on other Macs. Repo: /Users/rhyd/code/z-for-finder (Swift package in app/; GitHub rhydlewis/haunts). Reuse the existing Developer ID setup from ../lpx-explorer (same Apple account). Small commits to main; tests stay green.

REUSE (already on this Mac — do NOT create new creds):
- Signing identity: "Developer ID Application: RHYDIAN GWYN LEWIS (87A97X8DAG)", Team ID 87A97X8DAG. Confirm via: security find-identity -v -p codesigning.
- Notarytool creds: keychain generic-password account "lpx-explorer", services APPLE_ID (Apple ID email) + APPLE_PASSWORD (app-specific password). Read at runtime, NEVER print: security find-generic-password -a lpx-explorer -s APPLE_ID -w (and -s APPLE_PASSWORD -w). Team id 87A97X8DAG.
- Pattern reference: ../lpx-explorer/scripts/build-release.sh (codesign flags + the Sparkle.framework nested-signing you'll need in 7hr).

READ FIRST: `bd show z-for-finder-4fd`; scripts/build-app.sh (produces build/Haunts.app — extend it or add scripts/sign-notarize.sh that runs after it); context.md.

BUILD — a script (extend build-app.sh or new scripts/sign-notarize.sh) that, on this Mac:
1. Create app/Entitlements.plist for a Developer-ID (NON-sandboxed) hardened-runtime app: com.apple.security.automation.apple-events = true (the app sends Apple Events to Finder for FinderTracker; pairs with the existing NSAppleEventsUsageDescription). No App Sandbox.
2. Sign deep, hardened runtime + secure timestamp:
   codesign --force --options runtime --timestamp --entitlements app/Entitlements.plist --sign "Developer ID Application: RHYDIAN GWYN LEWIS (87A97X8DAG)" build/Haunts.app
   (No Sparkle in the bundle yet — when 7hr adds Sparkle.framework, sign its nested XPCServices/Updater.app/Autoupdate/framework FIRST, per lpx build-release.sh.)
3. Notarize: zip the signed .app; xcrun notarytool submit <zip> --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id 87A97X8DAG --wait → must return status Accepted.
4. Staple: xcrun stapler staple build/Haunts.app.
5. Verify: codesign --verify --strict --deep build/Haunts.app; spctl --assess --type execute build/Haunts.app → "accepted".

NOTE — notarization runs LOCALLY on this Mac (needs the keychain creds + network); it CANNOT run on the GitHub CI runner (no secrets). It's a local release step, not a CI job. CI stays build+test only. Do NOT wire notarization into ci.yml or fake it.

OUT OF SCOPE: Sparkle integration (7hr); DMG packaging + release pipeline (ge2); the website. Just a signed+notarized+stapled Haunts.app + the script.

GOTCHAS:
- Keep ZFFEngine pure; 164 tests must stay green (`swift test --package-path app`).
- NEVER print the Apple ID / app-specific password (read keychain into vars; don't echo).
- Hardened runtime + the apple-events entitlement is REQUIRED or the FinderTracker Apple Events break under signing — confirm the signed app still gets Finder consent and tracks.

DONE = each TRUE + VERIFIED on this Mac: build/Haunts.app is signed (codesign --verify --strict --deep passes), hardened-runtime, notarized (notarytool returned Accepted — paste the submission id + status), stapled (stapler validate passes), spctl --assess --type execute = "accepted"; the signed app still launches and the menu-bar/hotkey work; swift build + test green; script committed; pushed; CI green.

VERIFY, DON'T ASSERT: actually run the script end-to-end (it hits Apple's notary service, ~1–5 min) and paste the real notarytool Accepted result + spctl output. If creds are missing or notary fails, report BLOCKED — do not claim success or fake it.

HONESTY: a prior run here faked stats — unacceptable. Notarization either returns Accepted from Apple or it doesn't; report the real result. State partials plainly. Commit only green. Trunk-based small commits to main (no PR). End commits: Co-Authored-By: Claude <noreply@anthropic.com>
