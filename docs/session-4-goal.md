GOAL: Build the Preferences UI for Haunts (a macOS menu-bar folder-navigator). Repo: /Users/rhyd/code/z-for-finder (Swift package in app/). Work test-first; commit small increments to main; end on GREEN CI.

READ FIRST (they carry the context you lack):
- context.md (decisions + a debugging post-mortem of gotchas)
- docs/preferences-mockup.html = THE UI spec; your window must match it: 5 tabs (General/Ranking/Folders/Open With/About), light+dark
- docs/harvest-plan.md ; docs/assets/menubar-ghost.svg
- beads: run `bd show z-for-finder-a07` (and 237, wtn, 4g9)

ARCHITECTURE (extend, don't rewrite): ZFFEngine = pure ranking (keep AppKit-free); HauntsAdapters = editor signals; HauntsCore = AppState (@MainActor, public, testable) + OpenMode + Settings (UserDefaults, haunts.* keys); zforfinder = executable shell (AppDelegate: status item, hotkey, panel). Tests in app/Tests/ZFFEngineTests use Swift Testing; 102 pass now; CI runs swift build+test.

BUILD: a Preferences NSWindow hosting NSHostingView(PreferencesView), opened from a new "Settings…" status-menu item and ⌘,. CRITICAL: this app uses an AppKit lifecycle (main.swift + AppDelegate, .accessory) — do NOT use the SwiftUI `Settings` scene (there is no @main App). PreferencesView = SwiftUI TabView matching the mockup.

WIRE IT UP (not just a pretty window):
- Hotkey: read Settings.hotkeyKeyCode/hotkeyModifiers (currently hardcoded ⌃⌘Space in AppDelegate/HotKey) and RE-REGISTER on change.
- Ranking: AppState.rankingMode is hardcoded `.default`; make ranking mode + subfolderFrecency + minVisitCount read from Settings and re-blend (rebuild) when changed.
- Reset Learned Data: add a tested Store.reset() (writes []), confirm via NSAlert, then rebuild().
- Menu bar: replace status title "⌁" with the ghost as a TEMPLATE NSImage (isTemplate=true). NSImage can't load SVG — draw the path with NSBezierPath in code or bundle a PDF; crisp at 18px; correct in light AND dark menu bars.
- Settings: add rankingMode, subfolderFrecency, minVisitCount, appearance, launchAtLogin, refreshInterval, terminal target — each with a round-trip+default test in HauntsCore.
- Appearance control → NSApp.appearance (system/light/dark).

OUT OF SCOPE (do NOT build): FinderTracker/live navigation (Session 5 — the "Learn from navigation" toggle only PERSISTS a setting); shell-history seed blend (S6); .app bundle / signing / notarization / Sparkle; generating the colour app icon.

GOTCHAS (do not relearn the hard way):
- Run the app as a background task (foreground nohup gets killed on return). FIRST `pkill -9 -x zforfinder` — only ONE instance can own the hotkey; a stale one makes you test the wrong build. Confirm via pgrep -x zforfinder.
- Never put .id(index) on a ForEach over changing data (caused a stale-render bug). Use stable identity.
- Keep ZFFEngine pure. Swift Testing, not XCTest. SMAppService launch-at-login only works from a real signed .app bundle — wire it but say so honestly if you only ran the unbundled binary.

DONE = each TRUE and VERIFIED: Settings window opens (menu + ⌘,); 5 tabs match the mockup; hotkey rebind persists + re-registers (verify the new chord opens the palette); Balanced/Frequent toggles AppState mode + persists; Reset clears ~/Library/Application Support/Haunts/frecency.json to []; scan-roots/editor edits take effect on rebuild; Appearance switches light/dark; menu bar shows the ghost glyph; all prior tests pass + new Settings/Store.reset tests added; `swift build` and `swift test --package-path app` green; pushed to main; CI green.

VERIFY, DON'T ASSERT: swift test after each step; then ACTUALLY run the app (pkill + background) and manually exercise every DONE item; `gh run watch` for green. Then note progress in context.md + beads a07/237/wtn/4g9.

HONESTY: a prior run here falsely claimed notarized DMGs / "50 beta installs" / "100% crash-free" — none true. Unacceptable. Report only what you built/tested/ran. State partials plainly. Commit only green increments.
