# Haunts — app (Swift package)

The macOS app. This is the developer/build readme; see the repo-root `README.md`
for the product overview.

## Build · test · run
```bash
cd app
swift build
swift test            # Swift Testing — 167 tests
swift run zforfinder  # menu-bar app; press ⌥Space to summon the palette
```
A ghost glyph appears in the menu bar (no Dock icon). **Settings…** is on the
menu-bar menu. A proper double-clickable, signed `Haunts.app` bundle is bead `v3n`
(this raw `swift run` binary is for development).

## Architecture
Four targets, layered so the ranking logic is pure and unit-testable:

| Target | Role |
|---|---|
| **ZFFEngine** | Pure ranking/scoring — `Place`, `Matcher`, `Ranker`, `Scoring`, `Rollup`, `Store`, `RankingMode`/`Frecency`, `WarmSeed`. No AppKit/SwiftUI; fully unit-tested. |
| **HauntsAdapters** | Signal sources: editor recents (Zed/Xcode/PyCharm) + shell history (fish/zsh). |
| **HauntsCore** | App state + config: `AppState` (`@MainActor`), `Settings`, `FinderTracker`, `OpenMode`. Testable (the executable can't be imported by tests). |
| **zforfinder** (executable) | App shell: `AppDelegate` (status item, global hotkey, palette panel), `PaletteView`, `FloatingPanel`, `HotKey`, `PreferencesView`, `GhostIcon`, `main`. |

**Rule:** keep `ZFFEngine` pure (no AppKit/SwiftUI/file-I/O). Impure work — Spotlight,
git scan, Apple Events, file reads, `open` — lives in the adapters / `HauntsCore` /
the shell and passes plain data into the engine.

## How it works (one paragraph)
On launch the app builds a **warm** index from signals that already exist (git repos,
shell history, IDE recents, Spotlight usage), blended with per-source normalization +
a source-diversity bonus. Opt-in `FinderTracker` then learns from live Finder
navigation. `⌥Space` opens a non-activating palette; type to subsequence-filter;
`↩`/`⌘↩`/`⌃↩` open in Finder/editor/terminal; `⌘⌫` forgets a row.

> Note: the SwiftPM target is named `zforfinder` (historical); the product and the
> shipped bundle are **Haunts**. GitHub repo: `rhydlewis/haunts`.
