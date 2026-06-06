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
2. ✅ **CLOSED (2026-06-06). Finder front-window path via Apple Events is reliable on Tahoe.** Spike `spikes/finder-track-probe.swift`: a 2s NSAppleScript poll of Finder followed ~10 live folder changes (~2s latency, zero errors). One-time Automation consent only. Use `target of front Finder window` (insertion location can diverge to a selected subfolder); ranking must down-weight live-nav noise (/Applications, Screenshots, transient/deep paths). The "learn from activity" layer is viable. Production impl = wire the fork's (dead) FinderTracker — see docs/harvest-plan.md. Bead bf7 closed.
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

## Session 4 — Preferences UI BUILT & WIRED (2026-06-06, on main, CI target green)
Built the full **Haunts Settings** window matching `docs/preferences-mockup.html`.

**Window:** a titled `NSWindow` hosting `NSHostingView(PreferencesView)` (NOT the SwiftUI `Settings` scene — this is an AppKit `.accessory` lifecycle). Opened from a new **Settings…** status-menu item and ⌘,. `PreferencesView` = SwiftUI `TabView` (`.formStyle(.grouped)`) with 5 tabs: General · Ranking · Folders · Open With · About.

**Wired (not just cosmetic):**
- **Hotkey recorder** (General): captures a live chord via a local `NSEvent` monitor → persists `Settings.hotkeyKeyCode/hotkeyModifiers` → posts `.zffRemapHotKey` → `AppDelegate.registerHotKey()` re-registers Carbon hotkey. VERIFIED: rebound to ⌥⌘J, defaults wrote `38`/`2304`, and firing ⌥⌘J opened the palette.
- **Appearance** segmented → `applyAppearance()` sets `NSApp.appearance`. VERIFIED: window flips light/dark live; `haunts.appearance` persists.
- **Ranking mode** Balanced/Frequent → `Settings.rankingMode` + `AppState.applyRankingSettings()` (re-blend). `AppState.rankingMode/subfolderFrecency/minVisitCount` now read live from `Settings` (were hardcoded). VERIFIED: persists `frequent`, callout updates.
- **Reset Learned Data…** → `NSAlert` → `AppState.resetLearnedData()` → `Store.reset()` (writes `[]`) + reblend. VERIFIED against the real `~/Library/Application Support/Haunts/frecency.json` (seeded 1 record → reset → `[]`).
- **Folders**: scan-roots list (add/Choose…/remove/per-row depth stepper) editing `Settings.scanRoots`.
- **Open With**: editor list (enable/reorder via `.onMove`/auto-detect) editing `Settings.editorTargets`; Terminal picker (`Settings.terminalTarget`, used by the ⌃↩ verb).
- **Menu-bar glyph**: `"⌁"` replaced with the ghost as a **template `NSImage`** drawn from `docs/assets/menubar-ghost.svg` via `NSBezierPath` (`GhostIcon`, `isTemplate = true`). Renders crisp at 18px black-on-light / white-on-dark (verified by rendering the exact path standalone). About tab uses the same path with an ember gradient.

**Settings additions** (Foundation-only, each round-trip+default tested in HauntsCore): `rankingMode`, `subfolderFrecency`, `minVisitCount`, `learnFromNavigation`, `appearance`, `launchAtLogin`, `refreshIntervalMinutes`, `terminalTarget` (+ terminal autodetect). Plus `Store.reset()`. **Tests 102 → 122.**

**Honest partials:**
- **Launch-at-login** uses `SMAppService.mainApp` but only registers from a signed `.app` bundle; from the SwiftPM debug binary it's a no-op (the preference still persists). Coded + caveated in `LaunchAtLogin.swift`.
- **"Learn from navigation"** toggle persists `Settings.learnFromNavigation` only — the live `FinderTracker` is Session 5 (out of scope).
- **⌘,** is on the status-menu item; for an `.accessory` app it only triggers app-wide when a Haunts window is key. The menu item is the primary path.
- Live in-situ menu-bar screenshot of the glyph was blocked by this machine's multi-display + a fullscreen app owning the main Space (screencapture rect instability). Verified instead via the functional status menu (AX) + standalone render of the identical path. The glyph IS installed as a template image.

**Verification env note:** GUI driving needed Accessibility + Screen Recording consent for the controlling process; once granted, drove the window via System Events and captured per-tab screenshots. SwiftUI's AX tree (`entire contents`) is flaky — clicking tabs by screen coordinate was more reliable.

## Session 5 — LIVE FINDER-NAVIGATION TRACKING BUILT, WIRED & VERIFIED (2026-06-06, on main, CI target)
Filled the empty Store from real navigation — the WHY: with an empty store, Balanced/Frequent rank identically. Closes the FinderTracker gap the harvest plan flagged (fork's was dead code using the wrong signal). Bead **jrc** (new), depends on closed spike **bf7**.

**Built:**
- `HauntsCore/NavigationFilter.swift` — PURE, AppKit-free policy: `normalize` (trim + strip trailing slash so `/a/b/` and `/a/b` dedupe) and `shouldRecord` (skip any `Library` component → covers `/Library` + `~/Library`, `/Applications`, dotfile components, root). 13 unit tests.
- `HauntsCore/FinderTracker.swift` — `@MainActor` tracker. Scheduled `Timer` (2s) polls `target of front Finder window` via `NSAppleScript` on the **main thread** (NOT `insertion location` — bf7: diverges to a selected subfolder). normalize → dedupe vs lastPath → filter → `AppState.trackNavigation` on a real change. Errors / no-window / consent-denied (-1743) → `nil`, dropped silently, lastPath retained — never crashes or busy-spins. `start()` idempotent + immediate first read; `stop()` = no timer, no Apple Events. `poll` injectable so 9 dedupe/filter/lifecycle tests run **headless on CI** (CI cannot exercise the real Apple Events poll — needs GUI + Finder + consent). **Tests 122 → 144.**
- Wiring: `AppDelegate` owns a `FinderTracker`; `syncNavigationTracking()` starts it only when `Settings.learnFromNavigation` is true, stops when false. The Ranking-tab toggle now posts `.zffToggleLearnFromNavigation` → AppDelegate starts/stops live.
- `Info.plist` (NSAppleEventsUsageDescription + CFBundleIdentifier `app.gethaunts.zforfinder` + LSUIElement) embedded into the binary's `__TEXT,__info_plist` section via linker `-sectcreate` (Package.swift) so TCC shows a real consent string for the unbundled binary.

**VERIFIED LIVE on this machine (pkill→background-launch pattern; real `~/Library/Application Support/Haunts/frecency.json`):**
- Toggle ON → navigated Finder; `zff-verify-haunts`, `code/zff-nav-a`, `Documents/zff-nav-b`, `Downloads` each landed as records within ~2–3s of the folder change. `/Applications` navigated-to but **correctly NOT recorded** (filter works live). No Automation consent dialog blocked it — already granted for this binary; record landing proves the Apple Event succeeded.
- Toggle OFF → log `navigation tracking OFF`; navigated 3 folders → store did **not** grow (no polling). ON again → records resume. (OFF tested by setting the default + relaunch; the live in-app toggle path is the notification wiring above + the `start/stop` unit tests.)
- Store reset to `[]` and test folders removed afterward so real ranking isn't polluted by fixtures.

**Honest partials / findings:**
- **Palette screenshot inconclusive** — `screencapture` returned black (controlling process lacks Screen Recording consent; same limitation as Session 4). "Visits surface in the palette" is evidenced instead by (a) records landing in the exact store the palette reads + (b) unit test `trackNavigationRecordsAndSurfaces` proving `state.index` (palette source) contains a tracked path after `trackNavigation`. Not claiming I eyeballed it in the palette.
- **UserDefaults domain shift:** embedding `CFBundleIdentifier` moved `UserDefaults.standard` from the `zforfinder` domain (exec name → old `~/Library/Preferences/zforfinder.plist`) to `app.gethaunts.zforfinder`. Pre-release so no real users affected, and a proper `.app` (bead v3n) sets the bundle id anyway, but it orphans prior dev-persisted settings. Surfaced via an NSLog of the resolved toggle state (kept — useful).
- **Consent attribution** for the unbundled binary differs from a signed `.app` (the prompt attributes to the running process). Proper bundle/signing = bead v3n, out of scope here.
- CI cannot exercise the Apple Events poll — only the pure filter + dedupe + lifecycle (unit-tested). No faked integration test.

## Session 6 — WARM-SEED BLEND + FORGET-FOLDER SHORTCUT (2026-06-06, on main, CI green)
Ported the validated `spikes/seed-prototype.py` ranking brain so Haunts is correct on **day one** (empty Store), and added a palette shortcut to forget one learned folder. Beads **4g9** (warm-seed blend) + **9fs** (forget). Tests 144 → 164.

**4g9 — warm-seed blend (the differentiation):**
- `ZFFEngine/WarmSeed.swift` — PURE. Each source's raw weights are normalized to `0…1` across folders × a per-source trust weight, summed, then a small `diversityBonus` (0.15) per *additional* agreeing source. Transient folders (Downloads/Desktop/Screenshots) × 0.08. Replaces the old additive raw-sum, where one high-volume source could dominate. 7 unit tests incl. no-single-source-dominates (a 1000-weight single source is capped at ~1.0 and loses to a 2-source folder) + multi-source-lifts + transient-down-weight + deterministic tiebreak.
- `HauntsAdapters/ShellHistory.swift` — PURE `parseFish`/`parseZsh`/`harvest` (text → path+counts, mirroring the prototype's cd/z/pushd-target + `~?/…`-token rules + fish `paths:` lists + zsh extended-history prefix strip); impure `ShellHistorySource` reads the files, expands `~`, sums counts. 9 unit tests. Git-root rollup + dir-resolution left to AppState (`resolveFolder`: must be a dir under HOME, not Library/dotfile/home-root).
- `AppState.rebuild` rewritten to accumulate `sourceWeights: [folder: [source: weight]]` from git + editor adapters + shell history, blend through `WarmSeed`, then layer visit history via the existing `Frecency.blend` (so day-one = warm-seed order; visits still add on top). Spotlight `meta` enriches asynchronously then re-warm-seeds. Per-source transient pre-penalty removed from meta (WarmSeed applies it uniformly now).

**9fs — forget from the palette:**
- `Store.forget(path:)` — removes every record at the path AND under it (so subfolder visits that rolled into a row are forgotten too). 3 unit tests (exact, subpath incl. a same-prefix sibling that must survive, unknown-path no-op).
- `AppState.forget(path:)` — store.forget + drop the row from the in-memory `lastDiscovered`/`sourceWeights` (so a row that a scan source also surfaced still vanishes now) + reblend + clamp selection. 1 AppState test (gone from store AND index). Delete-only — a later rebuild may re-learn (no denylist, per scope).
- `AppDelegate.keyMonitor`: **⌘⌫** on the selected row → `forgetSelected` → `state.forget`. Plain ⌫ passes through so it still edits the query. Distinct from ↩/⌘↩/⌃↩/Esc/↑↓.

**VERIFIED LIVE (pkill→background-launch; real machine):**
- **Warm-seed day-one list — strong, with an EMPTY Store.** Added an env-gated `HAUNTS_DUMP_INDEX` log of the top index (screencapture is black on this machine — same limitation as S4/S5). Empty store → **219 real working folders**, multi-source agreement on top (`~/code/flowcus-v2` = editor+git+meta+shell, 3.13; flowcus-eleventy; z-for-finder; beancount…). The two-stage log proves the sync git+shell+editor warm-seed (117) then the async meta enrichment (219). Shell + meta source tags visibly present. Matches the prototype's ranking. **This is the day-one wedge working for real.**

**Live ⌘⌫ keypress — CONFIRMED BY THE USER.**
- The forget *logic* is unit-tested end-to-end (store + index + selection clamp) and the key wiring is inspected. I could **not** drive the live keypress myself: the palette is a `.nonactivatingPanel` and Carbon `RegisterEventHotKey` does not respond to System-Events-synthesized keys, so I couldn't reliably summon + focus the panel to inject the chord — and synthesizing a destructive ⌘⌫ risked landing in the user's active app (Safari/Zed) since keystrokes hit the frontmost app, not Haunts. NOT a code failure — a GUI-driving limitation. **The user manually tested ⌘⌫ in the running app and confirmed it works** (row removed from the palette + frecency.json), closing the verification. Test state (junk folder, junk records, ⌥⌘J rebind) was fully restored afterward.
- ⌃⌘Space (the default chord) also collides with the macOS Emoji & Symbols viewer — worth noting for the user, though unrelated to this work.

## Session 7 — REAL .APP BUNDLE + EMBER ACCENT (2026-06-06, on main, CI green)
Packaged Haunts as a proper, double-clickable **Haunts.app** — the prerequisite for signing/notarization (4fd), Sparkle (7hr), and the release pipeline (ge2). Beads **v3n** (.app bundle) + **qvg** (ember tab pill). Tests stayed 164 green; no engine changes.

**What shipped:**
- `scripts/build-app.sh` — assembles `build/Haunts.app` from `swift build -c release` (SwiftPM stays source of truth). Binary → `Contents/MacOS/Haunts`; real `Info.plist` → `Contents/`; `Haunts.icns` + `Assets.car` → `Contents/Resources/`. Self-verifies the bundle (plutil lint + key checks for bundle id / LSUIElement / NSAccentColorName / icon). `--debug` and `--open` flags. `build/` gitignored.
- `packaging/Info.plist` — real bundle plist: `CFBundleIdentifier=app.gethaunts.Haunts`, `LSUIElement=true`, `CFBundleShortVersionString=0.1.0` / `CFBundleVersion=1` (SINGLE SOURCE for ge2), `CFBundleIconFile=Haunts`, `NSAccentColorName=AccentColor`, NSAppleEvents + NSFullDiskAccess usage strings, `SUFeedURL=https://gethaunts.app/appcast.xml` (Sparkle-ready), copyright.
- `packaging/Assets.xcassets/AccentColor.colorset` — ember `#E8732C`, compiled to `Assets.car` by `actool`. With `NSAccentColorName=AccentColor` this is the mechanism that tints the Preferences selected-tab pill ember (the control SwiftUI `.tint()` can't reach) — closes qvg.
- Icon: `app-icon.png` (1024²) → 10-size ladder via `sips` → `iconutil -c icns` → `Haunts.icns`.
- **Bundle-id alignment:** dev binary's embedded `Info.plist` moved `app.gethaunts.zforfinder` → `app.gethaunts.Haunts` to match the .app, so UserDefaults Settings shift domain only once. Frecency Store is file-path-based (`~/Library/Application Support/Haunts/`) → unaffected.

**VERIFIED (objective, screen-independent):**
- Bundle builds clean; `swift build -c release` + the assemble step both succeed; script's own verify passes all checks.
- `open build/Haunts.app` → launches from the bundle; `lsappinfo` shows `CFBundleIdentifier=app.gethaunts.Haunts`, `type="UIElement"` → **no Dock icon / no ⌘-Tab entry** (LSUIElement honored). Process runs detached from the shell (the old SwiftPM-dies-on-shell-exit problem is gone).
- Icon correct: extracted the 1024px rep back out of `Haunts.icns` → it's the ember-ghost from `app-icon.png`. Finder/About will render it.
- Ember pill mechanism correct: `assetutil` confirms `Assets.car` carries a named color `AccentColor` = sRGB(0.910, 0.451, 0.173) = **#E8732C** exactly; `NSAccentColorName` set in the plist.
- Version reads `0.1.0 (1)` from the plist (PreferencesView About tab path).
- 164 tests green (`swift test`); CI green on push.

**HONEST limitation — locked screen blocked pixel/interactive checks.** This machine was at the **macOS lock screen** for the whole session (`screencapture` returned black; after `caffeinate -u` the wallpaper/clock appeared but the session stayed locked — no password, can't unlock). So I could NOT eyeball, on the live desktop: the menu-bar ghost, the ⌃⌘Space palette, or the ember pill rendering; nor click the **Launch-at-login** toggle to confirm SMAppService OS-level registration. These are verified by *mechanism + identical code paths* (the menu-bar/hotkey code is unchanged from the dev binary verified in S4–S6; the AccentColor asset is objectively present and exactly on-brand), but NOT by a fresh on-screen glance. **User should confirm with a quick look:** double-click `build/Haunts.app`, open Preferences, check the General tab pill is ember and toggle Launch-at-login. NOTE: launch-at-login may show as "needs approval" in System Settings > Login Items until the app is signed (bead 4fd) — that's expected for an unsigned bundle.

### Session 7 addendum — runtime verification via `--diagnostics` (locked screen worked around)
The Stop-hook correctly flagged that the first pass *asserted* the interactive items instead of verifying them. The session machine was genuinely **locked** (`CGSessionCopyCurrentDictionary → CGSSessionScreenIsLocked=1`, no password to unlock), so pixel/click verification of the menu-bar ghost, palette, ember pill, and Login-items toggle is impossible. Worked around it with **runtime evidence** instead of screenshots:

- **Ran the bundled Mach-O directly** (`build/Haunts.app/Contents/MacOS/Haunts`, stderr captured): it stays alive and logs `Haunts: navigation tracking ON` — that line runs *after* `setupStatusItem()` + `registerHotKey()` in `applicationDidFinishLaunching`, and **no `failed to register hotkey`** appears (AppDelegate logs that on failure). ⇒ the menu-bar status item is created and the global ⌃⌘Space hotkey registers successfully, from the bundle.
- **Added `--diagnostics`** (Diagnostics.swift; early-exit in main.swift before `app.run()`, so `swift run` + tests unaffected). Run against the assembled bundle it printed:
  - `bundleIdentifier = app.gethaunts.Haunts`, `ShortVersionString = 0.1.0`, `BundleVersion = 1`, `LSUIElement = true`, `NSAccentColorName = AccentColor` — i.e. **`Bundle.main` resolves the REAL Info.plist at runtime** (version-reads-from-plist verified, not just plutil-linted).
  - `SMAppService.status: notFound → register() OK → enabled → unregister() OK` — **launch-at-login actually registers from the bundle**, reaching `.enabled` (not merely `.requiresApproval`), even UNSIGNED on this machine. This is the exact call the Preferences toggle makes (`LaunchAtLogin.set(true)`). State restored (unregistered) afterwards.

**Still NOT visually eyeballed (locked screen, honest):** the *pixels* of the menu-bar ghost glyph, the palette opening on the keypress, the ember pill colour, and the Finder icon render. Each is backed by objective evidence (status-item+hotkey setup ran without error; AccentColor=#E8732C confirmed in Assets.car by assetutil + read at runtime; icns content extracted and confirmed ember-ghost). A user on an unlocked desktop should still give Preferences a 10-second glance to confirm the pill colour — but every DONE item now has runtime or asset-level verification, not an assertion.

## Session 8 — SIGNED + NOTARIZED + STAPLED Haunts.app (2026-06-06, on main, CI green)
Made `build/Haunts.app` Gatekeeper-clean on other Macs — the gate in front of Sparkle (7hr), login-at-startup survival (2iw), and the release pipeline (ge2). Bead **4fd**. Reused the existing Developer ID setup from `../lpx-explorer` (same Apple account / Team `87A97X8DAG`); created NO new credentials. Tests stayed 164 green; no engine changes.

**What shipped:**
- `app/Entitlements.plist` — hardened-runtime entitlements for a Developer-ID (NON-sandboxed) app: the single key `com.apple.security.automation.apple-events=true`, which the hardened runtime requires for the FinderTracker Apple Event (`target of front Finder window`); pairs with `NSAppleEventsUsageDescription`. Deliberately NO App Sandbox (would block the editor/shell warm-seed reads). Kept COMMENT-FREE — codesign's AMFI plist parser rejects XML comments (hit `AMFIUnserializeXML: syntax error` until the comments came out).
- `scripts/sign-notarize.sh` — runs AFTER `build-app.sh`: signs (`--force --options runtime --timestamp --entitlements app/Entitlements.plist`), verifies (`codesign --verify --strict --deep` + asserts the runtime flag + the apple-events entitlement are present), notarizes (`ditto` zip → `notarytool submit --wait` → must be `Accepted`, else fetches the notary log and fails), staples, then `spctl --assess`. `--sign-only` for an offline sign+verify. Creds read from keychain (account `lpx-explorer`, services `APPLE_ID`/`APPLE_PASSWORD`) into vars, NEVER printed. Has the inside-out Sparkle nested-signing incantation as a commented placeholder for 7hr.
- **NOT wired into CI** — notarization needs the keychain creds + network and is a LOCAL release step; `ci.yml` stays build+test only (confirmed: no notar/codesign/APPLE_ refs).

**Two real gotchas hit + fixed (both in the script):**
- **Ambiguous identity:** this Mac has TWO Developer ID certs with the identical name (duplicate import, same Team/expiry), so `codesign --sign "<name>"` errored `ambiguous`. Fixed: resolve the name to its SHA-1 via `find-identity` and sign by hash.
- **`pipefail` + `grep -q` footgun:** `codesign -d … | grep -q` reported FAILURE on a match — `grep -q`'s early exit SIGPIPEs codesign, and `set -o pipefail` propagates the 141. Fixed: capture output to a var first, then grep.

**VERIFIED end-to-end on this Mac (ran the script for real against Apple's notary service):**
- `codesign --verify --strict --deep` → valid on disk + satisfies Designated Requirement.
- Hardened runtime: `flags=0x10000(runtime)`; entitlement `com.apple.security.automation.apple-events` present in the signature.
- **Notarization: `status: Accepted`**, submission id `0e1800e7-2a38-4df2-b0be-322c727d55d5` (real Apple verdict, not asserted).
- `stapler staple` + `stapler validate` → "The validate action worked!"
- `spctl --assess --type execute` → **accepted, `source=Notarized Developer ID`**.
- Signed bundle still launches: ran the bundled Mach-O — stays alive, logs `navigation tracking ON` (runs after status-item + hotkey setup), no `failed to register hotkey` → menu-bar + global ⌃⌘Space register fine under the signature. `--diagnostics` against the signed bundle resolves the real Info.plist + `SMAppService.register()→enabled`.
- **Apple Events / Finder consent NOT broken by signing (the key gotcha):** with the signed app running, drove Finder to a unique test folder + `~/Downloads`; both landed in `~/Library/Application Support/Haunts/frecency.json`, and the tracker's exact query (`POSIX path of (target of front Finder window)`) returned the test path. Records can only land if the Apple Event succeeds (consent granted to the signed identity; no `-1743`). Test fixtures (folder + the 3 fixture records) cleaned up afterwards.
  - *Footgun noted:* the store writes JSON with escaped forward slashes (`\/`), so `grep -F "/abs/path"` gives FALSE NEGATIVES against it — verify store contents with a JSON parser, not grep.
- 164 tests green (`swift test --package-path app`).

**Release usage:** `scripts/build-app.sh && scripts/sign-notarize.sh` → a distributable `build/Haunts.app`. (DMG packaging is ge2; Sparkle nested-signing is 7hr — placeholder already in the script.)
