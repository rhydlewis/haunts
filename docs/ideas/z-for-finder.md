# z for Finder — The Warm Navigator

> A frecency-ranked, keyboard-first navigator for the places and files you actually use.
> Not a Spotlight replacement — a Spotlight *correction*. It does one thing: get you there, every time, in 50ms.

## Problem Statement
**How might we** give macOS a frecency-ranked "jump to the place I actually work" launcher — folders, and the files inside them — that opens *warm* (already ranked before you type) and is dramatically more reliable than Spotlight, which is buggy and unpredictable in Tahoe?

## Recommended Direction
Build **the Warm Navigator**: a global hotkey opens a palette that is *already ranked* with where you're most likely to want to go right now — weighted by frecency (frequency × recency, the core `z` mechanic) and context (time-of-day, currently-focused app). Typing only filters an already-good list. Enter opens the target in Finder (folder), its default app (file), or — as a secondary action — your editor/terminal at that path.

The product promise is **reliability, not features**. Spotlight is flaky in Tahoe precisely because it does too much — apps, web, math, Siri suggestions — over a giant index. A focused tool that does *only* place/file navigation, over a small hand-tuned index, can be instant and never miss. "It works every single time" is the entire moat. Every feature that threatens that promise gets cut.

The frecency engine is built in two layers so it's **warm from minute one**: bootstrap from native macOS signals — a **recency** query via `NSMetadataQuery` (`kMDItemLastUsedDate`) blended with a **frequency** signal from `~/Library/.../com.apple.sharedfilelist/` per-app recent-documents — all rolled up to parent folders. Then sharpen over time by observing your real navigation (Finder front-window path via Apple Events; editor/IDE recent-workspace lists). No cold-start dead period, and it gets more personal than anything Apple ships.

> **Validated 2026-06-03.** A naive `kMDItemUseCount` rollup was tested and **failed**: the `mdls` CLI can't retrieve per-file metadata on Tahoe at all ("could not find" for every plain file), and count-rollup ranks by file-count, surfacing photo archives not workplaces. But the **recency** path works: `mdfind 'kMDItemLastUsedDate >= $time.now(-2592000)'` rolled up to folders surfaced real working dirs on the first try (`~/code/*`, `Music/Logic`, `Finance/beancount/ledger`, `Documents/Claude/Projects/*`). The Spotlight *index* is healthy; only the per-file CLI is broken — so the engine must use `NSMetadataQuery`/`sharedfilelist`, never shell out to `mdls`.

**Explicitly not** an app launcher and **not** a context-orchestrator (the Bunch/Workspaces space). Opening Finder + editor + terminal together is one optional *verb on a result*, never the headline — orchestration is where the 50ms reliability promise dies.

## Key Assumptions to Validate
- [x] ~~**`kMDItemUseCount` rolls up into a useful folder ranking.**~~ **TESTED 2026-06-03 → falsified as written, rescued.** Use-count rollup fails (mdls CLI broken on Tahoe; count-rollup surfaces archives). **Recency** rollup via `NSMetadataQuery`/`kMDItemLastUsedDate` works and surfaces real working folders on day one. Bootstrap pivots to recency (mdfind/`NSMetadataQuery`) + `sharedfilelist` recent-docs for frequency. **New open item:** confirm `NSMetadataQuery` (framework) succeeds where the `mdls` CLI fails.
- [ ] **Finder front-window path is readable *reliably* in Tahoe.** If our `cd`-equivalent (Apple Events → Finder) is as flaky as the Spotlight we're fleeing, we inherit the disease. *Test:* poll the Automation path on the real machine, watch for failures/permission churn. **(red risk)**
- [ ] **Frecency-for-places actually beats Spotlight enough to switch.** *Test:* cheap prototype (Raycast extension or CLI) ranking real folders; does it put the right place first more often than Spotlight? Validate the *brain* before building the native *shell*.
- [ ] **Reliability is a sellable wedge vs. free incumbents** (Raycast/Alfred do folder search with frecency-ish ranking, free). *Test:* can we demo "never misses + starts warm" in a way that makes a Raycast user switch?
- [ ] **Permissions don't kill distribution.** Apple Events + likely Full Disk Access + a background agent probably means Developer ID + notarization + Sparkle, not App Store. Confirm and accept early.

## MVP Scope
**In:**
- Global hotkey → palette.
- Frecency index of folders (+ files), **bootstrapped from `NSMetadataQuery` recency (`kMDItemLastUsedDate`) + `sharedfilelist` recent-docs frequency** so it's useful on first launch. (Not `mdls`/`kMDItemUseCount` — proven broken on Tahoe.)
- Enter opens: folder → Finder; file → default app. One secondary action: open folder in editor/terminal.
- Sub-50ms open-to-keystroke; "never misses" reliability bar.

**Out (for MVP):**
- The "warm" predictive pre-ranking (context by time/active app) — ship plain frecency first, add prediction once the index proves good. *This is the soul, but it's the second turn, not the first.*
- The native Swift app itself, until the brain is validated. **Validate ranking with a throwaway Raycast extension or CLI prototype first**; build the native shell only once frecency-for-places is proven better than Spotlight.
- App launching, context orchestration, iCloud sync, natural-language queries.

## Not Doing (and Why)
- **App launching** — Spotlight/Raycast already nail it; including it dilutes the "navigator" focus and the reliability promise.
- **Context orchestration (open editor+terminal+Finder together)** — that's Bunch/Workspaces' crowded, solved space; opening 3 apps breaks "works every time in 50ms." Kept only as a single optional verb.
- **Building the native app before validating the ranking** — the native shell's only job is reliability; it's the wrong place to discover the brain is mediocre.
- **App Store distribution (assumed)** — the permissions we need likely force Developer ID + notarization; don't design around a sandbox we can't live in.
- **iCloud sync / NL queries** — real, but v3 dreams; deliberately deferred so they don't bloat the wedge.

## Open Questions
- ~~Does `kMDItemUseCount` survive in Tahoe?~~ **Answered:** the index has it (`mdfind` works) but the `mdls` CLI can't read per-file metadata; use-count rollup is the wrong signal anyway. Use recency + `sharedfilelist`.
- Does `NSMetadataQuery` (framework) reliably return `kMDItemLastUsedDate` where the `mdls` CLI fails? (Next test, before building the shell.)
- Can `sharedfilelist` `.sfl4` files be parsed cleanly (NSKeyedUnarchiver bookmark data) for a frequency signal, or is the Apple Events / editor-recents route more robust?
- What's the cleanest reliable Tahoe signal for "user navigated to folder X" — Apple Events polling, FSEvents, an Accessibility hook, or editor recents only?
- What's the unit of ranking — folder, or folder+file blended in one list?
- Native shell: AppKit menu-bar app + custom palette window, or a lighter approach? (Decide *after* brain validation.)
- Monetization for a "reliability" product: one-time license vs. subscription?
