# Haunts

A keyboard-driven folder launcher for macOS that's **warm on first launch**. Hit a
hotkey, type a few letters, and jump straight to a folder in Finder, your editor, or
a terminal — ranked by a frecency model (frequency × recency) that's already useful
on day one, before it has watched you do anything.

Most "smart" launchers start cold and take weeks to learn your habits. Haunts seeds
its ranking on first run from signals that already exist on your machine — your git
repos, shell history, IDE recent-projects, your `zoxide`/`z`/`autojump` history, and
Spotlight metadata — and blends them so the folders you actually work in surface
immediately.

## Features

- **Zero cold-start.** The day-one index is built from git repos + shell history
  (fish/zsh/bash) + your jump database (`zoxide`/`z`/`autojump`) + IDE recents
  (Zed, Xcode, PyCharm) + Spotlight usage, with no prior observation required.
- **Cross-source ranking.** Each signal source is normalized independently (so one
  high-volume source can't dominate) and folders that several sources agree on get a
  small confidence boost.
- **Learns as you go.** Opt-in live Finder-navigation tracking keeps the model fresh.
- **Fast keyboard flow.** Summon, filter by subsequence match, open — without leaving
  the keyboard.
- **Native & dependency-free.** A menu-bar app with no zoxide/fzf/host-launcher
  required.

## Keyboard shortcuts

While the palette is open:

| Key | Action |
| --- | --- |
| `⌥Space` | Summon / dismiss the palette (rebindable in Preferences) |
| type | Filter results by name |
| `↑` / `↓` | Move selection |
| `↩` | Open the selected folder in **Finder** |
| `⌘↩` | Open in your **editor** |
| `⌃↩` | Open in your **terminal** |
| `⌘⌫` | **Forget** the selected folder (remove it from the learned set) |
| `Esc` | Close the palette |

> The default summon chord is `⌥Space` — clear of macOS's reserved shortcuts
> (Spotlight, input source, Emoji & Symbols). Rebind it under **Settings → General**.

## Build & run

Requires macOS 14+ and a Swift 5.9 toolchain (Xcode 15+).

```bash
# Build
swift build --package-path app

# Run (menu-bar app — look for the ghost glyph in the menu bar)
swift run --package-path app zforfinder

# Test
swift test --package-path app
```

On first launch, grant Automation (Apple Events) access if you enable
**Learn from navigation** — it's needed to observe the front Finder window.

## Preferences

Open **Settings…** from the menu-bar item (or `⌘,` when a Haunts window is focused):

- **General** — hotkey recorder, appearance (Light/Dark/System), launch at login.
- **Ranking** — Balanced vs. Frequent ranking, subfolder frecency, and a
  *Reset Learned Data…* button.
- **Folders** — which roots to scan for git repos (with per-root depth).
- **Open With** — editor priority + terminal of choice for the `⌘↩` / `⌃↩` verbs.

## Architecture

A Swift package (`app/`) split so the ranking logic stays pure and unit-testable:

| Target | Role |
| --- | --- |
| `ZFFEngine` | Pure ranking/scoring — no AppKit, SwiftUI, or I/O. `WarmSeed`, `Frecency`, `Ranker`, `Scoring`, `Store`, `Rollup`. |
| `HauntsAdapters` | Signal sources: editor recents, shell-history, and jump-database (`zoxide`/`z`/`autojump`) parsing. Foundation-only, never-throw. |
| `HauntsCore` | `AppState` (index assembly), `Settings`, live `FinderTracker`. Testable without the executable. |
| `zforfinder` | App shell: `AppDelegate`, the SwiftUI palette, the floating panel, and the global hotkey. |

**How ranking works.** Each source contributes per-folder weights; `WarmSeed` scales
each source to `0…1`, multiplies by a per-source trust weight, sums them, and adds a
small bonus per additional agreeing source (transient folders like Downloads/Desktop
are heavily down-weighted). Persisted visit history is then layered on top via
`Frecency.blend`. All of the math is pure and deterministic — `now` is injected — so
it's covered by unit tests in `app/Tests/ZFFEngineTests`.

The learned frecency store lives at
`~/Library/Application Support/Haunts/frecency.json`.
