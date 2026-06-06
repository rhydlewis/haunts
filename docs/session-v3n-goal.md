GOAL: Package Haunts as a proper, double-clickable macOS .app bundle (bead v3n) — the foundation for signing/notarization/Sparkle/release. Repo: /Users/rhyd/code/z-for-finder (Swift package in app/; GitHub repo is rhydlewis/haunts). Test-first; small commits to main; end on GREEN CI.

WHY: it's a bare SwiftPM executable today. A real .app unlocks launch-at-login (SMAppService needs a bundle), the ember Preferences tab-pill (AccentColor asset), the app icon in Finder/⌘-Tab/About, and is the prerequisite for 4fd/7hr/ge2.

READ FIRST:
- `bd show z-for-finder-v3n` (esp. the BUNDLE-ID CONSISTENCY note) + the tab-pill polish bead (`bd list` → grep pill).
- context.md; docs/preferences-mockup.html (the ember look the tab-pill must match).
- app/Package.swift — the executable already embeds Info.plist via linker -sectcreate (Apple Events consent on the unbundled binary); the .app uses a REAL Info.plist instead.
- app-icon.png (repo root, 1024² ember-ghost) — the app-icon source.

BUILD — produce **Haunts.app** from `swift build -c release`. SwiftPM doesn't emit a .app, so pick ONE (RECOMMEND a script: keeps SwiftPM as source of truth + scriptable for ge2; Xcode project is the alternative): scripts/build-app.sh assembling Haunts.app — binary → Contents/MacOS/Haunts, Info.plist → Contents/, .icns + Assets.car → Contents/Resources/.
- Icon: from app-icon.png, sips to the standard 16–1024 @1x/@2x sizes → `iconutil -c icns` → Haunts.icns; reference via CFBundleIconFile.
- Ember accent (CLOSES the tab-pill bead): an Assets.xcassets with an AccentColor colorset = #E8732C, compiled with `actool` → Assets.car, plus Info.plist NSAccentColorName=AccentColor. This makes the Preferences selected-tab pill render ember (the one control .tint() couldn't reach).
- Info.plist (real): LSUIElement=true; CFBundleIdentifier=app.gethaunts.Haunts; CFBundleName=Haunts; CFBundleShortVersionString + CFBundleVersion (single source for ge2); CFBundleIconFile; NSAppleEventsUsageDescription; NSFullDiskAccessUsageDescription; SUFeedURL=https://gethaunts.app/appcast.xml (for later Sparkle); copyright.

DECIDE ONCE — bundle id = **app.gethaunts.Haunts** in the .app AND align the dev binary's embedded plist (Package.swift) to the SAME id, so UserDefaults Settings don't shift domain twice (the frecency Store is file-path-based → unaffected). Pre-release, harmless to set now.

OUT OF SCOPE: code signing / notarization (4fd); Sparkle integration (7hr); release pipeline / version bump (ge2); the website. Just the UNSIGNED, runnable .app + its build script.

GOTCHAS:
- actool + iconutil need Xcode command-line tools.
- Keep ZFFEngine pure; all 164 tests must stay green (`swift test --package-path app`).
- The .app launches with `open Haunts.app`; keep `swift run` working for debugging.
- Swift Testing, not XCTest.

DONE = each TRUE + VERIFIED by building Haunts.app and opening it: double-clicks to launch; menu-bar ghost present, NO Dock icon (LSUIElement); ⌃⌘Space opens the palette; Finder/⌘-Tab/About show the app-icon.png icon; Preferences selected-tab pill renders EMBER (AccentColor); bundle id = app.gethaunts.Haunts; version reads from Info.plist; the launch-at-login toggle actually registers via SMAppService from the bundle; swift build + swift test green; pushed; CI green. Close v3n + the tab-pill bead.

VERIFY, DON'T ASSERT: after building, OPEN the .app and manually confirm each DONE item (icon, no-Dock, hotkey, ember pill, launch-at-login). Capture what you saw. State honestly if AccentColor/actool is fiddly or launch-at-login still won't register while unsigned. `gh run watch`; then note in context.md.

HONESTY: a prior run here faked stats — unacceptable. Report only what you built/tested/ran; state partials plainly. Commit only green. Trunk-based small commits to main (no PR). End commits: Co-Authored-By: Claude <noreply@anthropic.com>
