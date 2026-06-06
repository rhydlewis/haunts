GOAL: Add live Finder-navigation tracking to Haunts (a macOS menu-bar folder navigator) so it learns where you work and ranking reflects it. Repo: /Users/rhyd/code/z-for-finder (Swift package in app/). Work test-first; commit small increments to main; end on GREEN CI.

WHY: the Store is empty today, so Balanced/Frequent rank identically. This fills it from real navigation — the "learns where you work" promise.

READ FIRST:
- context.md — esp. the closed-risk entry on Finder Apple-Events tracking (validated approach + caveats).
- spikes/finder-track-probe.swift — the VALIDATED probe (NSAppleScript polling Finder); base the tracker's script on it.
- docs/harvest-plan.md (FinderTracker = REWRITE + RE-VALIDATE); `bd show z-for-finder-bf7`.
- Reference only (dead code, used the WRONG signal): the fork's HauntsCore/FinderTracker.swift (path in docs/harvest-plan.md).

ALREADY DONE (use, don't rebuild): AppState.trackNavigation(path:) records a visit + re-blends (tested); Settings.learnFromNavigation persists the toggle; the Ranking tab writes it.

ARCHITECTURE: ZFFEngine = pure (keep AppKit-free); HauntsCore = AppState (@MainActor) + Settings + (new) FinderTracker; zforfinder = executable (AppDelegate starts/stops the tracker). Tests: app/Tests/ZFFEngineTests (Swift Testing); 122 pass; CI runs swift build+test.

BUILD:
- A FinderTracker in HauntsCore polling Finder's CURRENT FOLDER every ~2s via NSAppleScript → appState.trackNavigation(path:) on change. Use `target of front Finder window` (NOT `insertion location` — bf7: it diverges to a selected subfolder). NSAppleScript on MAIN thread; dedupe identical paths; on error/no-window/consent-denied(-1743) drop silently, keep last path, never crash or busy-spin.
- Start from AppDelegate ONLY when Settings.learnFromNavigation is true; STOP when toggled off (off = no polling).
- SKIP recording paths under /Library, dotfiles, /Applications (engine already down-weights transient dirs). Put this should-record check in a PURE, unit-tested function.
- Apple Events needs one-time Automation consent. Add NSAppleEventsUsageDescription to Info.plist; handle denial gracefully.

OUT OF SCOPE: shell-history seed blend / normalization (Session 6); .app bundle / signing / Sparkle / release; the tab-pill accent.

GOTCHAS (don't relearn the hard way):
- Run the app as a background task (foreground nohup gets killed). FIRST `pkill -9 -x zforfinder` — one instance only; a stale one makes you test the wrong build. Confirm via pgrep -x zforfinder.
- NSAppleScript MAIN thread only; never block main for 2s — schedule the poll (Timer/Task), keep each call quick.
- Keep ZFFEngine pure. Swift Testing, not XCTest. Don't ship dead code: the tracker must actually be STARTED and wired to the toggle.

CI CANNOT TEST THIS: the Apple Events poll needs a GUI + Finder + consent; it won't run on CI. So unit-test the PURE bits (should-record filter, dedupe) and VERIFY live behaviour manually (below). Do NOT fake an integration test.

DONE = each TRUE + VERIFIED: toggle ON → navigating Finder records visits to ~/Library/Application Support/Haunts/frecency.json within ~2s and visited folders rise in the palette (⌃⌘Space); toggle OFF → no new records, no polling; consent-denied/no-window doesn't crash; pure filter+dedupe unit-tested; all 122 prior tests pass; `swift build` + `swift test --package-path app` green; pushed to main; CI green.

VERIFY, DON'T ASSERT: swift test each step; then run the app (pkill+background), toggle Learn-from-navigation ON, navigate a few Finder folders, confirm records land in frecency.json AND surface in the palette; toggle OFF → polling stops. Capture what you saw; `gh run watch` for green. Then note progress in context.md + beads bf7/4g9.

HONESTY: a prior run here falsely claimed beta installs / crash-free stats that never happened — unacceptable. Report only what you built/tested/ran; state partials plainly (consent attribution differs for the unbundled binary; CI can't exercise Apple Events). Commit only green. Trunk-based small commits to main (no PR). End commits with: Co-Authored-By: Claude <noreply@anthropic.com>
