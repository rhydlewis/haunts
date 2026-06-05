# z for Finder — Working Context

> Pick-up notes from the ideation session on 2026-06-03. Read this + `docs/ideas/z-for-finder.md` (the spec) to resume.

## What we're building (one line)
A frecency-ranked, keyboard-first **navigator** for the folders/files you actually use — a native macOS app, hotkey-invoked, whose entire promise is **"it works every time, in 50ms"** (a focused correction to flaky Tahoe Spotlight). Not an app launcher, not a context-orchestrator.

## Decisions locked this session
- **Audience:** a real product (notarized, possibly paid) — likely **Developer ID + notarization + Sparkle**, not App Store (permissions we need probably can't live in the sandbox).
- **Targets:** folders → Finder; files → default app; folders → editor/terminal as a *secondary action only*.
- **NOT doing:** app launching; context orchestration (the Bunch/Workspaces space — opening 3 apps breaks the 50ms promise); iCloud sync; NL queries.
- **Ranking signal:** learn from real activity (true `z` frecency), but **bootstrap from native signals so it's warm from minute one** — no cold-start.
- **Build:** native Swift is the final form — but **validate the ranking "brain" with a cheap spike/prototype before building the native shell.** The shell's only job is reliability; it's the wrong place to discover the brain is mediocre.
- **Chosen direction:** "The Warm Navigator" (Direction 2) = plain frecency navigator first, then a *pre-ranked warm list* on open (context by time-of-day + active app). The "start warm" interaction is the soul and the one thing Spotlight/Raycast/Alfred structurally don't do.

## The crux: where does the ranking signal come from?
Outside the terminal there's no `cd` to hook. Four candidate native signals, in order of leverage:
1. `kMDItemLastUsedDate` via **`NSMetadataQuery`** — recency. ✅ works.
2. `~/Library/.../com.apple.sharedfilelist/` per-app **RecentDocuments** — frequency. (Updated live; `.sfl4` = NSKeyedArchiver bookmark data.)
3. **Finder front-window path via Apple Events** — the truest `cd`-equivalent; costs an Automation permission. ⚠️ reliability in Tahoe UNVERIFIED.
4. Editor/IDE recent-workspace lists (VS Code, JetBrains, Sublime).

**Frecency = blend recency (1) + frequency (2) + your own observation (3,4) over time.**

## What we actually tested on this machine (2026-06-03, macOS Tahoe)
Ran live probes. Findings:
- ❌ **`kMDItemUseCount` rollup is dead.** (a) The **`mdls` CLI cannot retrieve per-file metadata at all** on this Tahoe machine — returned "could not find" for *every* plain file (PDF/`.md`/`.txt` in `~/Documents`). (b) Even where counts exist, summing ranks by file-count → surfaces photo archives (`zArchive/Xmas 2019`), not workplaces.
- ✅ **The Spotlight *index* is healthy** — `mdfind` works fine (884 files used in last 30d; 9,088 with use-count>0). It's the per-file *CLI retrieval* that's broken, not the data.
- ✅ **Recency rollup works.** `mdfind "kMDItemLastUsedDate >= $time.now(-2592000)"` rolled up to parent folders surfaced **real working folders on the first try**: `~/code`, `~/code/flowcus-v2`, `~/code/capability-lead`, `~/code/flowcus-eleventy`, `Music/Logic`, `Finance/beancount/ledger`, `Documents/Claude/Projects/AXA Health POC`. Noise (Downloads/HEIC, Screenshots) is filterable.
- 🔑 **`sharedfilelist` exists and is active** — `com.apple.LSSharedFileList.ApplicationRecentDocuments` (161 per-app entries, updated today), `RecentDocuments.sfl4`, `FavoriteItems`, `ProjectsItems`.

### Implications
- **Bootstrap pivots** from use-count → **recency (`NSMetadataQuery`) + `sharedfilelist` frequency.**
- **Hard architectural constraint:** the app must use **framework APIs (`NSMetadataQuery`, direct `.sfl4` parsing), never shell out to `mdls`/metadata CLIs** — the same Tahoe flakiness it's curing would otherwise infect it.
- **Meta:** the `mdls` breakage *confirms the founding premise* — Tahoe's metadata layer really is broken. The moat is real.

## Open red risks — gate building anything
1. ✅ **CLOSED (2026-06-05). `NSMetadataQuery` succeeds.** Spike 1 (`spikes/recency-probe.swift`) returned 332 items, all 332 with readable `kMDItemLastUsedDate`, in ~1.3s incl. compile. Surfaced real working folders (`code/*`, `Music/Logic`, EE conf, `Finance/beancount/ledger`). Also: the Spotlight index was rebuilt (`mdutil -E /System/Volumes/Data`), so `mdls`/`kMDItemUseCount` **work again too** — frequency rejoins recency as a usable signal. See [[mdls-broken]].
2. ⬜ **Is the Finder front-window path (Apple Events) reliable in Tahoe**, or flaky like Spotlight? The "learn from activity" layer rests on it. **Next red risk to close.**
3. ✅ **SUBSTANTIALLY CLOSED (2026-06-05). Tuned ranking beats Spotlight.** Spike 2 (`spikes/ranking-prototype.swift`): frecency = `sqrt(useCount) * recencyHalfLife`, rolled up to nearest `.git` root, transient dirs (Downloads/Desktop/Screenshots) down-weighted ×0.08. Top-20 surfaced real workplaces (EE conf, WIP music, Music/Logic, `code/flowcus-v2`, `code/flowcus-eleventy`, `Finance/beancount`, active repos) in ~1.6s incl compile. Downloads/Screenshots dropped out; git-rollup collapsed deep leaves to repo roots. Remaining noise (`Documents/iCloud In`, Avatars) is blocklist/live-activity tuning, not a signal failure.

## Ranking-design learnings from the spikes (tuning, not blockers)
- Pure recency over-rewards transient dirs: `~/Downloads`, `~/Screenshots`, `~/Desktop` rank too high → blend in **frequency (use-count)** + a small blocklist/down-weight.
- **Roll results up to the nearest project root (git repo / known workspace), not the literal parent dir.** Spike surfaced `flowcus-eleventy/src/assets/images/help` when the wanted unit is `flowcus-eleventy`. This answers the spec's "unit of ranking" open question.

## Next action
Brain is validated AND the tuned ranking is proven (Spikes 1 & 2 green). Two paths remain before/into the native shell:
- (a) **Apple Events spike** — test Finder front-window-path reliability in Tahoe (closes last red risk #2, the live-activity layer). Recommended next: even if flaky, the recency+frequency bootstrap already stands on its own.
- (b) **Native shell** — menu-bar app + global hotkey + palette + "warm" predictive list, with the Spike-2 ranking as the engine. Reuse `spikes/ranking-prototype.swift` scoring; swap the one-shot query for a cached index refreshed in the background.
Tuning backlog for the engine: extend transient blocklist (`Documents/iCloud In`, media dumps); for non-git deep leaves, roll up to "the folder you actually open" once the live-activity layer exists.

## Spikes built (reusable)
- `spikes/recency-probe.swift` — Spike 1, NSMetadataQuery proves kMDItemLastUsedDate readable.
- `spikes/ranking-prototype.swift` — Spike 2, the tuned frecency engine (recency × sqrt(useCount), git-rollup, transient down-weight). **This is the scoring logic to port into the app.**

## Session update — 2026-06-05 (decisions + competitive reality)
Now tracked in **beads** (`bd list`; git-backed, initialised this session):
- `z-for-finder-bf7` (P1) — Spike 3: reliably read live navigation (Finder Apple Events + editor recents) on Tahoe. = old open risk #2.
- `z-for-finder-4g9` (P1) — Define defensible differentiation (see research below).
- `z-for-finder-snz` (P2) — Decide product name ("z for Finder" is a WIP placeholder).
- `z-for-finder-z5b` (P2) — Decide unit of a "place": folder vs project.

**Decisions locked:**
- **Distribution: NOT App Store.** Developer ID + notarization + Sparkle (Apple account & signing keys in hand). Frees us to use Apple Events / Full Disk Access / background agent. Resolves the old sandbox risk.
- **User-facing name: Haunts** (plural; decided 2026-06-05, bead snz). "Jump to your haunts" = the places you frequent. Plural chosen over singular "Haunt" — truer meaning AND the affordable namespace. Domain: **gethaunts.app** (~EUR 11, to register — bead b7t). Dropped: haunt.app (EUR 18,000, not justifiable pre-launch) and haunts.app (make-an-offer). Category is clear (no rival Mac launcher named Haunt/Haunts). Still TODO before branding spend: register gethaunts.app; formal USPTO trademark search; App Store listing ("Haunts — Folder Jumper" or similar). **Internal name `z-for-finder` stays** for repo/bundle id during dev.

**Competitive research (2026) — the sobering truth:**
- The core feature **already ships**. `mrpunkin/raycast-zoxide` is a GUI over zoxide's frecency DB with bidirectional CLI sync — effectively "z for Finder" today. LaunchBar has usage-adaptive navigation (~20 yrs). Alfred learns on a 4-week frequency window + OS metadata. Raycast Root Search has documented frecency (file-level less so). FastFolderFinder = same form-factor, no learning.
- **No feature whitespace.** "Reliability" alone is a weak wedge (invisible until failure, undemoable).
- **Defensible angles (execution, not features):** (1) **zero cold-start** — seed frecency on first launch from existing signals (zoxide DB if present, shell history, git repos, Finder recents, IDE recents); *nobody does this*. (2) zero-dependency, navigation-only scope. (3) better native decaying freq×recency model. (4) never-miss reliability as backstop. Possibly bidirectional zoxide DB sync as table stakes.
- **Implication:** warm-seeding becomes a *core requirement*, not a v2 nicety. The differentiation bet is "correct on day one, zero setup" vs. the zoxide-Raycast path's cold start + CLI ritual.

## Spike 3b — DAY-ONE WARM SEEDING: ✅ proven (2026-06-05)
`spikes/seed-prototype.py` (throwaway, Python). Blends signals that ALREADY EXIST (zero prior observation) into a ranked day-one list with provenance:
- Sources on this machine: **92 git repos** (.git recency), **fish/zsh history** (cd targets + `paths:`), **JetBrains** recentProjects.xml, **Sublime** session, **Spotlight metadata** (mdfind recency). No zoxide present — and it still works (zoxide would just be one more vote).
- **Result:** top list reads like real working life (`flowcus-v2`, `flowcus-eleventy`, `Finance/beancount`, `Music/Logic`, active `lpx-*`). `flowcus-v2` scored ●●●●● — all 5 sources agree. **20/25 of top folders confirmed by ≥2 independent sources.** Instant (~1s incl. 92-repo scan).
- **Key fix:** per-source normalization is essential — raw shell-history frequency blew one folder to 252× before normalizing each source to its own max × a trust weight.
- **This is the wedge, demonstrated:** warm + provenance on first launch is the visible differentiator incumbents (cold-start) cannot show. Feeds bead `z-for-finder-4g9`.
- **Engine tuning identified:** weight by *source diversity* (down-rank `●····` single-source git-only repos); extend transient/junk blocklist (`Documents/iCloud In`).

## Spikes built (so far)
- `spikes/recency-probe.swift` (S1) · `spikes/ranking-prototype.swift` (S2, port this) · `spikes/seed-prototype.py` (S3b, warm-seed blend logic to port).

## Native shell — thin vertical slice BUILT & RUNNING (2026-06-05)
`app/` — dependency-free SwiftPM executable (`cd app && swift run`). Hybrid as designed: AppKit owns lifecycle + Carbon **⌃⌘Space** hotkey (no permissions) + a Spotlight-style non-activating `NSPanel`; SwiftUI renders the palette via `NSHostingView`. Engine ports Spike 2 (NSMetadataQuery recency×√useCount, git-root rollup, transient down-weight) + a git-repo warm seed. Works: type→fuzzy filter, ↑↓ select, ↩ Finder / ⌘↩ VS Code / ⌃↩ Terminal, Esc/click-away dismiss. Builds clean. See `app/README.md`.
**Slice gaps (next):** port full Spike-3b seed blend (shell/IDE) + source-diversity weighting into the Swift engine; package as signed/notarized `.app` + Sparkle; refine to fully non-activating; then live-activity learning (bead `bf7`).

### Debugging saga — filtering "broken in UI" (2026-06-05) — RESOLVED
Long hunt; root causes (all now fixed in `app/`):
1. **SwiftUI render bug (the real one):** rows had `.id(idx)` (positional identity) *inside* a `ForEach(id: \.element.id)`. Double-identity → SwiftUI reused row views in place and never refreshed content, so the list looked frozen on the first (git-seed) render while `state.results` computed correctly underneath. Fix: remove `.id(idx)`; identity by path only; scroll via `proxy.scrollTo(results[sel].id)`.
2. **Process-lifecycle trap (what made it impossible to debug):** launching the app with `nohup … &` inside a *foreground* Bash tool call → the harness kills the process group when the call returns, so every "fixed" relaunch died on exit. Meanwhile the FIRST launch (via Bash `run_in_background: true`) persisted and kept owning ⌃⌘Space (system-wide, first-registrant-wins) running the OLD buggy build. **Lesson: launch the app via Bash `run_in_background: true` (harness-persistent); never via nohup-in-foreground. `pkill -9 -x zforfinder` to clear before launching one.**
3. Earlier genuine fixes that stuck: unstable sort on tied scores → deterministic `rankOrder` (score desc, path asc) so the displayed row == the opened folder; `didSet`-drives-refilter regression → pure computed `results` (no publish-in-view-update staleness); separator-insensitive name matching (`z for`↔`z-for`); editor action → Sublime.
4. Debugging breakthrough was **instrumentation** (NSLog of query/index/results + selfPtr) — proved engine correct, isolated bug to render layer. Should have reached for it ~3 rounds earlier instead of reasoning from screenshots.

**Status: filtering works in the UI.** Confirmed: `code`→[code, xcode, claude-code, …], `alfred`→[alfred-finicky, …]. App currently running (one instance, background task).
**Tuning backlog (not bugs):** empty-query default still shows noise (`Identifying Patterns…`, `Applications`, bare `code`, `iCloud In`) — port Spike-3b transient/blocklist + source-diversity weighting; ~0.4s git-seed→metadata warm-up flash.

## Key files
- `docs/ideas/z-for-finder.md` — the one-pager spec (problem, direction, assumptions, MVP, not-doing).
- `context.md` — this file.
- `prompt.md` — kickoff prompt for the coding agent.

## Reference: the probe commands that worked (for reproducing)
```bash
# Recency rollup that surfaced real working folders:
mdfind "kMDItemLastUsedDate >= \$time.now(-2592000)" \
  | grep -v -E '/Library/|/\.|/Applications/' \
  | sed 's:/[^/]*$::' | sort | uniq -c | sort -rn | head -25

# Proof the index has data but mdls CLI is broken:
mdfind 'kMDItemUseCount > 0' | wc -l          # ~9088, index is fine
mdls -name kMDItemUseCount ~/Documents/some.pdf  # "could not find" — CLI broken

# The frequency signal source:
ls ~/Library/Application\ Support/com.apple.sharedfilelist/
```
