# z for Finder — app (thin vertical slice)

A runnable proof of the spine: global hotkey → floating palette → frecency-ranked places → open. Built from the validated spikes.

## Run
```bash
cd app
swift run            # or: ./.build/debug/zforfinder
```
A `⌁` icon appears in the menu bar. Press **⌃⌘Space** to summon the palette. Quit from the menu-bar menu.

## What works (this slice)
- **⌃⌘Space** global hotkey (Carbon `RegisterEventHotKey` — *no* Accessibility/Input-Monitoring permission needed).
- **Warm on launch**: index seeded from git repos under `~/code` + Spotlight frecency (`NSMetadataQuery`, recency × √useCount, git-root rollup, transient down-weight — ports Spike 2).
- **Type** to fuzzy-filter · **↑/↓** to move · **↩** open in Finder · **⌘↩** VS Code · **⌃↩** Terminal · **Esc / click-away** to dismiss.
- Borderless non-activating `NSPanel` (AppKit) hosting SwiftUI content via `NSHostingView`.

## Known limitations (deliberate — it's a slice)
- Swift engine seeds from **git + Spotlight only**. The full Spike-3b blend (shell history, JetBrains/Sublime recents, source-diversity weighting) is not yet ported — see `../spikes/seed-prototype.py`.
- Editor action hardcoded to VS Code bundle id (`com.microsoft.VSCode`); silently no-ops if absent.
- Runs as an unbundled binary from the terminal — **not** yet a signed/notarized `.app` with Sparkle.
- On summon it calls `NSApp.activate` for reliable text focus; a fully non-activating flow can be refined later.
- No live-activity learning yet (that's bead `z-for-finder-bf7`, Spike 3).

## Architecture
| File | Role |
|---|---|
| `main.swift` | Agent-app bootstrap (`.accessory` policy) |
| `AppDelegate.swift` | Status item, hotkey, key routing, show/hide |
| `HotKey.swift` | Carbon global hotkey (permission-free) |
| `FloatingPanel.swift` | Spotlight-style non-activating `NSPanel` |
| `AppState.swift` | Frecency engine (Spike 2 port) + palette state |
| `PaletteView.swift` | SwiftUI search field + results list |
