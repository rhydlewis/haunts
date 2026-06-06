# Goal: Build the Haunts Preferences UI (harvest Session 4)

You are working in `/Users/rhyd/code/z-for-finder` (a macOS Swift package under `app/`).
Build the Preferences window for **Haunts**, a menu-bar folder-navigator app.
Work **test-first**, commit small increments to `main`, and **end on green CI**.

## READ THESE FIRST (do not skip — they carry all the context you lack)
1. `context.md` — project state, decisions, and a debugging post-mortem of hard-won gotchas.
2. `docs/preferences-mockup.html` — **the exact UI spec.** Open it; the window you build must match it (5 tabs: General · Ranking · Folders · Open With · About; light + dark).
3. `docs/harvest-plan.md` — what's already been ported and what's deferred.
4. `docs/assets/menubar-ghost.svg` — the menu-bar glyph to ship.
5. Beads: run `bd show z-for-finder-a07`, `bd show z-for-finder-237`, `bd show z-for-finder-wtn`, `bd show z-for-finder-4g9`.

## Architecture (already in place — extend, don't rewrite)
- `app/Sources/ZFFEngine/` — pure ranking/scoring (`Place`, `Ranker`, `Scoring`, `Rollup`, `Store`, `RankingMode`/`Frecency`). **No AppKit/SwiftUI — keep it that way.**
- `app/Sources/HauntsAdapters/` — editor recent-folder adapters.
- `app/Sources/HauntsCore/` — `AppState` (@MainActor, public, testable), `OpenMode`, `Settings` (UserDefaults, `haunts.*` keys).
- `app/Sources/zforfinder/` — executable shell: `AppDelegate` (status item, hotkey, key monitor, panel), `PaletteView`, `FloatingPanel`, `HotKey` (Carbon), `main.swift`.
- Tests: `app/Tests/ZFFEngineTests/` (Swift Testing — `import Testing`, `@Test`/`#expect`). **102 tests currently pass.**
- CI: `.github/workflows/ci.yml` runs `swift build` + `swift test --package-path app` on push.

## SCOPE — build a Preferences window matching the mockup, and wire it up

**The window itself:** This app uses an AppKit lifecycle (`main.swift` + `AppDelegate`, `.accessory` activation policy) — it does **NOT** use the SwiftUI `@main App` lifecycle, so you **cannot** use the SwiftUI `Settings` scene. Instead, create a borderless/titled `NSWindow` hosting `NSHostingView(rootView: PreferencesView())`, opened from a new "Settings…" item in the status-bar menu (and ⌘, ). Build `PreferencesView` in SwiftUI as a `TabView` (toolbar/tab style) with the 5 tabs.

**Per tab (match the mockup):**
- **General:** hotkey recorder (capture a real chord → persist to `Settings.hotkeyKeyCode`/`hotkeyModifiers`); Launch-at-login (SMAppService — see caveat); Appearance segmented (System/Light/Dark → drives `NSApp.appearance`); Refresh-index interval.
- **Ranking:** Balanced/Frequent segmented → sets the ranking mode (persist + apply); "Learn from navigation" toggle (persists a setting only — the live tracker is Session 5, out of scope); "Frequent subfolders" toggle + "keep after N visits" stepper; **"Reset Learned Data…"** button (confirm via `NSAlert`, then clear the `Store` and `rebuild()`).
- **Folders:** scan-roots list (add/remove/Choose…/depth) editing `Settings.scanRoots`.
- **Open With:** editor list (enable/reorder/auto-detect) editing `Settings.editorTargets`; Terminal picker.
- **About:** ghost app-icon, "Haunts", version, tagline, **Buy-me-a-coffee** + gethaunts.app/GitHub/Acknowledgements buttons, "Made by Rhyd Lewis" credit. (Use placeholder URLs; the real app-icon PNG is being generated separately — use the menu-bar ghost or a placeholder.)

**Wiring (the part that makes it real, not just a pretty window):**
- **Hotkey:** `HotKey`/`AppDelegate` must READ `Settings.hotkeyKeyCode`/`hotkeyModifiers` (currently hardcoded ⌃⌘Space) and **re-register** when changed.
- **Ranking mode + subfolder/min-visit:** `AppState` currently has `private let rankingMode: RankingMode = .default` and calls `Frecency.blend(... subfolderFrecency: false ...)`. Make these read from `Settings` and re-blend (`rebuild()`) when changed.
- **Reset learned data:** add a tested `Store.reset()` (writes `[]`), call it then `rebuild()`.
- **Menu-bar glyph:** replace the `"⌁"` status-item title with the ghost as a **template** `NSImage` (`image.isTemplate = true`). NSImage can't load SVG directly — either bundle a PDF rendered from `docs/assets/menubar-ghost.svg`, or draw the ghost path in code with `NSBezierPath`. Make it crisp at 18px.
- **Settings additions:** add `rankingMode`, `subfolderFrecency`, `minVisitCount`, `appearance`, `launchAtLogin`, refresh-interval, and a terminal target to `Settings` — each with a test (round-trip + default). Keep `Settings` Foundation-only and tested in `HauntsCore`.

## OUT OF SCOPE (do NOT build — they are later sessions)
- Live Finder navigation tracking / `FinderTracker` (Session 5). The "Learn from navigation" toggle only persists a setting.
- Spike-3b warm blend / shell-history seeding (Session 6).
- `.app` bundling, signing, notarization, Sparkle, the App Store (separate track).
- Generating the colour app icon (the user is doing this).

## HARD CONSTRAINTS / hard-won gotchas (do not relearn these the hard way)
- **Running the app:** launch it via the Bash tool with `run_in_background: true` (the harness kills foreground `nohup &` processes on return). **Before launching, `pkill -9 -x zforfinder`** — only one instance can hold the global hotkey, and a stale instance will make you test the wrong build. Confirm exactly one instance with `pgrep -x zforfinder`.
- **SwiftUI list rendering:** never put `.id(index)` on `ForEach` rows over a changing collection — it caused a stale-render bug. Use stable identity by value/id.
- **Keep `ZFFEngine` pure** (no AppKit/SwiftUI/NSMetadataQuery). UI-bound code goes in the executable; testable state in `HauntsCore`.
- **Swift Testing**, not XCTest. New pure logic must have tests; SwiftUI views don't need unit tests but their backing logic (Settings, Store.reset, mode wiring) does.
- **SMAppService caveat:** launch-at-login only works for a proper signed `.app` bundle; from the SwiftPM debug binary it may be a no-op. Wire it but note this in your report — do not claim it works if you only ran the unbundled binary.
- **macOS version note:** if `mdls`/Spotlight or Apple-Events behave oddly, see `context.md` (there's a documented `mdutil -E` fix and an Apple-Events finding) — but those are not in this session's scope.

## DEFINITION OF DONE (every item must be TRUE and VERIFIED)
- [ ] Preferences window opens from the status menu and ⌘, ; 5 tabs present and visually match `docs/preferences-mockup.html`.
- [ ] Changing the hotkey persists and re-registers (manually verify the new chord opens the palette).
- [ ] Balanced/Frequent toggle changes `AppState`'s mode and re-blends; persisted across relaunch.
- [ ] Reset-learned-data clears the store (verify `~/Library/Application Support/Haunts/frecency.json` becomes `[]`).
- [ ] Scan-roots and editor-targets edits persist and take effect on next `rebuild()`.
- [ ] Appearance control switches the app between light/dark.
- [ ] Menu-bar shows the ghost template glyph (not `⌁`), correct in light AND dark menu bars.
- [ ] All previously-passing tests still pass; new `Settings`/`Store.reset`/mode-wiring tests added and green.
- [ ] `swift build` and `swift test --package-path app` are green; pushed to `main`; CI run is green.

## VERIFICATION PROTOCOL (do this; don't assert without it)
1. `cd app && swift test` after each increment — keep it green.
2. Build + run the real app (background task, after `pkill`), then **manually exercise**: open Settings, switch tabs, flip Appearance (light/dark), toggle ranking mode, hit Reset, rebind the hotkey, confirm the menu-bar glyph. Capture what you actually observed.
3. Push; wait for CI; confirm green via `gh run watch`.
4. Update `context.md` (a short Session-4 entry) and append progress notes to beads `a07`, `237`, `wtn` (and `4g9` for the mode toggle).

## HONESTY MANDATE
A previous automated run on this project shipped a report claiming notarized DMGs, "50 beta installs", and "100% crash-free" — none of which had happened. **That is unacceptable.** Report only what you verified by building, testing, and running. If something is partial (e.g. SMAppService unbundled, or a tab you couldn't fully wire), say so plainly. Commit only green increments. Prefer a smaller, true result over a larger, claimed one.

## Working style
Trunk-based, small commits straight to `main` (no PR needed), each green. End commit messages with:
`Co-Authored-By: Claude <noreply@anthropic.com>`
