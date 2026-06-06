# Harvest Plan — divergent fork → canonical z-for-finder

**Author:** code-investigation pass, 2026-06-06
**Fork under review:** `/Users/rhyd/.archon/workspaces/rhydlewis/z-for-finder/artifacts/runs/08c917a22d03d032bb9f730cb9e807da/app`
**Canonical:** `/Users/rhyd/code/z-for-finder` (Swift package under `app/`)

This plan is evidence-based and skeptical. Every claim below was verified against the
fork's actual source, not its Sprint reports. Where the fork's own report overclaims,
that is called out explicitly. **Do not trust the fork's report; trust this verification.**

---

## 0. Bottom line

- The fork did **not** regress canonical's pure engine. `Ranker`, `Matcher`, `Scoring`,
  and `Rollup.gitRoot`/`isTransient` are **byte-identical** to canonical. `Place` and
  `Rollup` were **extended additively** (new fields with defaults, new function) — no API
  break. This makes harvesting low-risk for the core.
- The genuinely valuable, well-tested harvest targets are: **`Store.swift`** (frecency
  persistence), the **editor adapters + `EditorAdapter` protocol**, **`Settings.swift`**,
  and the **`Place`/`Rollup` additive extensions**. These are pure/near-pure and carry
  real tests.
- The **entire distribution layer is unproven and partly non-functional** and must be
  RE-VALIDATED, not trusted: `release.yml` references an Xcode scheme + `ExportOptions.plist`
  that **do not exist** in this SwiftPM package, so it has never run and cannot run as
  written. Signing/notarization/DMG/Sparkle are all unexercised.
- **FinderTracker is dead code** (defined, never instantiated or started anywhere in
  `Sources/`). The live-navigation feature (bead bf7) is effectively unbuilt; only the
  `trackNavigation` sink it would call is tested.
- Bead **4g9** (Spike-3b warm-seed blend) is only **partially** served: the fork adds IDE
  recents but has **no shell history, no per-source normalization, and no source-diversity
  weighting** — the three things that define Spike-3b's differentiation.

---

## 1. Engine integrity check (Task 2)

Canonical engine files vs fork engine files:

| File | Verdict |
|---|---|
| `Matcher.swift` | **Identical** to canonical. |
| `Ranker.swift` | **Identical** to canonical. |
| `Scoring.swift` | **Identical** to canonical. |
| `Rollup.swift` | `gitRoot` + `isTransient` **identical**; fork **adds** `keepSubfolder(...)` (pure, additive). |
| `Place.swift` | Fork **adds** `decayComponent`/`useComponent`/`metaComponent` with **default args** → source- and ABI-compatible; canonical call sites compile unchanged. |
| `Store.swift` | **New** in fork. Pure value type over a JSON file. No engine dependency beyond `Scoring`/`Rollup`/`Ranker`. |

**Conclusion:** No regression, no API drift that breaks canonical. The fork preserved the
pure core verbatim and built on top of it. Porting the additive pieces into canonical's
`ZFFEngine` is safe and mechanical.

**One semantic note to validate, not a blocker:** the fork moved the warm-seed/merge logic
out of `AppState` into `Store.mergePlaces(...)` with formula
`combinedScore = max(storedScore, freshScore) + visitCount*0.1`. Canonical currently does
additive blending inside `AppState.rebuild()`/`runMetadata`. These are *different blends*.
Adopting `mergePlaces` is a behavior change (persistent store + `max`-based blend), so it
needs a deliberate decision + tests, not a silent swap.

---

## 2. Per-item assessment (Task 3)

Legend — Wired: is it actually reachable in the running app? Tests: real coverage?

### A. `ZFFEngine/Store.swift` (+ `PlaceRecord`)
- **What:** Append-log frecency store at `~/Library/Application Support/Haunts/frecency.json`;
  `record`/`load`/`compact`/auto-compact@500/`mergePlaces`. Pure, injectable `fileURL`.
- **Quality:** Good. Never throws on bad I/O (returns `[]`), atomic writes, dedup-by-path.
- **Tests:** Strong — `StoreTests.swift` (27 `@Test`): codable round-trips incl. unicode/spaces,
  malformed/truncated/garbage JSON, append-not-upsert, compact sum/latest-date, auto-compact
  threshold, atomic writes. `IntegrationTests.swift` covers `mergePlaces` merge strategy + subfolder flag.
- **Wired:** Yes (fork `AppState.rebuild()` calls it). Independent of FinderTracker.
- **Bead:** 4g9 (persistence substrate for warm seed / frecency).

### B. Editor adapters: `EditorAdapter` protocol + `Zed`/`Xcode`/`PyCharm`
- **What:** Read IDE "recent folders" → `[URL]`. Injectable config paths. Never throw.
- **Quality:** Good, defensive. Xcode resolves security-scoped bookmarks + path fallbacks;
  PyCharm regex-parses `recentProjects.xml`; Zed reads `recent_dirs` from settings.json.
- **Tests:** `ZedAdapterTests` (11), `XcodeAdapterTests` (6), `PyCharmAdapterTests` (3),
  `AdapterWiringTests` (5 — incl. failure-isolation: a throwing adapter must not abort rebuild).
- **Wired:** Yes — default `AppState` instantiates `[Zed, Xcode, PyCharm]` and `rebuild()` pumps
  their results into the store.
- **Bead:** 4g9 (IDE-recents portion of the warm-seed blend).

### C. `HauntsCore/Settings.swift`
- **What:** UserDefaults-backed config: hotkey keycode/modifiers, editor targets (+auto-detect),
  scan roots, subfolder-frecency flag, min-visit-count. Codable structs `EditorTarget`/`ScanRoot`.
- **Quality:** Clean, all static, defaulted getters.
- **Tests:** `SettingsTests.swift` (13): codable round-trips, malformed-data fallback, scan-root
  defaults, detect-no-duplicate/only-existing-apps.
- **Wired:** Yes — read by `AppState`, `PreferencesView`, `OnboardingView`, `AppDelegate`.
- **Bead:** 237 (configurable open-in / editor targets) + a07 (configurable shortcut) +
  partially 4g9 (scan roots).

### D. `Place`/`Rollup` additive extensions
- **What:** `Place` score components (debug overlay); `Rollup.keepSubfolder` (subfolder frecency).
- **Quality:** Pure, trivially correct.
- **Tests:** `RollupTests.swift` covers `keepSubfolder` thresholds (at/above/below/zero/deep/no-git).
- **Wired:** Yes (used by `mergePlaces` + debug overlay).
- **Bead:** 4g9.

### E. `PreferencesView.swift`
- **What:** SwiftUI 3-tab prefs (General: launch-at-login + hotkey label/reset + rebuild interval;
  Folders: scan-root list add/remove + subfolder-frecency + min-visit stepper; Editors: enable/reorder/detect).
- **Quality:** Reasonable SwiftUI. NB: "Launch at login" toggle is **only** `@AppStorage` — no
  `SMAppService` registration wired, so it persists a preference but does nothing yet.
  Hotkey UI is **display + reset only** (no live capture/record of a new chord).
- **Tests:** None (SwiftUI view).
- **Wired:** Yes (opened from status menu).
- **Bead:** 237 / a07 / wtn (prefs is where light/dark + shortcut config live).

### F. `OnboardingView.swift`
- **What:** 4-step first-run wizard (welcome / FDA / scan-roots / done). Posts completion notif.
- **Quality:** Reasonable. FDA "Continue" re-probes via `AppState.checkFullDiskAccess()`.
- **Tests:** None.
- **Wired:** Yes (first launch via `haunts.hasOnboarded`).
- **Bead:** v3n-adjacent (app polish) — no dedicated bead; low priority.

### G. `AppDelegate.swift`
- **What:** Status-item app shell. Wires hotkey, key/flag monitors, panel, prefs/onboarding
  windows, Sparkle updater, crash-report sheet, index-freshness indicator, configurable-hotkey remap.
- **Quality:** Competent, but **heavily coupled** to Sparkle + PLCrashReporter + HauntsCore.
  This is the fork's app composition root and diverges substantially from canonical's AppDelegate.
- **Tests:** None.
- **Wired:** Yes (it *is* the app).
- **Bead:** spans 7hr (Sparkle), a07 (hotkey remap), plus general shell. **Do not port wholesale.**

### H. `CrashReporter.swift` (+ `CrashReportSheet`)
- **What:** Thin PLCrashReporter wrapper: enable, detect pending, load+purge. Sheet asks send/discard.
- **Quality:** Fine wrapper. BUT the "send" path just loads+purges the report — **there is no
  upload/transport**. So it is a local crash-catcher, not a crash-reporting pipeline.
- **Tests:** None.
- **Wired:** Yes (called from `applicationDidFinishLaunching`).
- **Bead:** none of the listed beads. New dependency (`plcrashreporter`). Treat as optional.

### I. `FinderTracker.swift` — **DEAD CODE**
- **What:** Actor that *would* poll Finder's `insertion location` via Apple Events every 2s and
  call `AppState.trackNavigation`.
- **Verification:** `grep` across `Sources/` finds **zero** references to `FinderTracker` outside
  its own definition — never instantiated, `start(appState:)` never called. The `trackNavigation`
  sink it targets is exercised only by `TrackNavigationTests`, never in production.
- **Quality:** The approach (Apple Events on main thread, error-swallow on network volumes,
  Info.plist `NSAppleEventsUsageDescription`) is plausible and matches canonical's own
  `spikes/finder-track-probe.swift`. But it is **unproven at runtime** — no integration test can
  cover the real Apple Events permission/consent path.
- **Bead:** bf7 (validate live Finder-nav reliability on Tahoe).
- **Report contradiction:** the fork report's "NSWorkspace polling" claim is false — the code uses
  Apple Events / NSAppleScript. Trust the code.

### J. Distribution layer: `release.yml` + `Info.plist` + Sparkle — **NON-FUNCTIONAL / RE-VALIDATE**
- **`release.yml`:** Runs `xcodebuild archive -scheme Haunts` and `-exportArchive ... ExportOptions.plist`.
  **Verified:** there is **no `.xcodeproj`, no `Haunts` scheme, and no `ExportOptions.plist`** in the
  fork (it is a pure SwiftPM package). The workflow **cannot succeed as written** and has never run.
- **`Info.plist`:** Reasonable as a *bundle template* (bundle id `app.gethaunts.Haunts`, `LSUIElement`,
  `SUFeedURL`, FDA + AppleEvents usage strings). But `SUFeedURL` points at `gethaunts.app` which does
  not exist; no appcast, no signing identity.
- **Report fabrications (confirmed):** notarized DMG, 50 beta installs, 100% crash-free, issues closed —
  **none** are evidenced. Nothing is signed/notarized; the release job has never executed.
- **Beads:** v3n (.app bundle), 4fd (signing/notarization), 7hr (Sparkle), tvh (MAS).
  **Everything here is a starting-point reference, not a deliverable. RE-VALIDATE all of it.**

---

## 3. Prioritized HARVEST PLAN (Task 4)

Decisions: PORT AS-IS / PORT WITH CHANGES / REWRITE / SKIP.
Effort: S (<½ day), M (½–2 days), L (>2 days).

| # | Item | Decision | Bead | Dep / order | Effort | Risk |
|---|---|---|---|---|---|---|
| 1 | `Place` score-component fields | **PORT AS-IS** (additive) | 4g9 | none | S | none |
| 2 | `Rollup.keepSubfolder` + its tests | **PORT AS-IS** | 4g9 | none | S | none |
| 3 | `Store.swift` + `StoreTests` | **PORT AS-IS** | 4g9 | after 1,2 | M | low — pure, well-tested |
| 4 | `Store.mergePlaces` blend → adopt in `AppState.rebuild()` | **PORT WITH CHANGES** | 4g9 | after 3 | M | **med — behavior change** to ranking; needs golden tests + decision |
| 5 | `EditorAdapter` protocol + Zed/Xcode/PyCharm + adapter tests | **PORT AS-IS** (own module) | 4g9 | after 3 | M | low |
| 6 | `Settings.swift` (`EditorTarget`/`ScanRoot`/hotkey/scan-roots) | **PORT WITH CHANGES** | 237, a07 | before 7,8 | M | low — UserDefaults key namespace (`haunts.*`) |
| 7 | `PreferencesView` | **PORT WITH CHANGES** | 237, a07, wtn | after 6 | M | med — wire launch-at-login (`SMAppService`) + real hotkey capture; add light/dark |
| 8 | Configurable hotkey remap path (`Settings` + `.zffRemapHotKey` + `AppDelegate.remapHotKey`) | **PORT WITH CHANGES** | a07 | after 6 | M | med — verify Carbon hotkey re-register on Tahoe |
| 9 | `OnboardingView` | **PORT WITH CHANGES** | (polish) | after 6 | M | low |
| 10 | `trackNavigation` + debounce on `AppState` | **PORT WITH CHANGES** | bf7 | after 3 | S | low (logic is tested) |
| 11 | `FinderTracker` (Apple Events poller) | **REWRITE + RE-VALIDATE** | bf7 | after 10 | L | **high — dead code, unproven; must be spiked on real Tahoe + actually wired/started** |
| 12 | `Info.plist` bundle template | **PORT WITH CHANGES** | v3n | before 13 | S | low — fix `SUFeedURL`, confirm bundle id |
| 13 | `.app` bundle packaging | **REWRITE** | v3n | after 12 | M | **high — fork has no working bundling; needs real xcodeproj/scheme or SwiftPM bundling** |
| 14 | `release.yml` signing/notarization/DMG | **REWRITE + RE-VALIDATE** | 4fd | after 13 | L | **high — non-functional as written; secrets, cert, ExportOptions.plist all missing** |
| 15 | Sparkle auto-update (`SPUStandardUpdaterController` + appcast) | **REWRITE + RE-VALIDATE** | 7hr | after 13,14 | L | **high — needs real signed feed; unexercised** |
| 16 | `CrashReporter` + `CrashReportSheet` (PLCrashReporter) | **SKIP (defer)** | — | — | M | adds dep; has no upload transport; no listed bead |
| 17 | Mac App Store | **SKIP (out of harvest)** | tvh | — | L | sandbox conflicts w/ Apple-Events Finder tracking; separate track |
| 18 | Shell-history source + per-source normalization + source-diversity weighting | **REWRITE (from Spike-3b, not the fork)** | 4g9 | after 4,5 | L | **the fork does NOT contain this** — port from `spikes/seed-prototype.py` |

### What to PORT (high-confidence wins)
`Store.swift`, the editor adapters, `Settings.swift`, and the `Place`/`Rollup` additive
extensions — all pure/near-pure and genuinely tested. These move the needle on 4g9 / 237 / a07
with low risk.

### What to SKIP / defer
- **CrashReporter** (#16): new dependency, no transport, no bead.
- **Mac App Store** (#17): conflicts with the Apple-Events Finder-tracking direction; separate effort.
- **Wholesale `AppDelegate`** : do not copy; cherry-pick the hotkey-remap + freshness bits.

### Biggest red flags (must RE-VALIDATE, never trust)
1. **`release.yml` is non-functional** — archives a non-existent Xcode scheme via a missing
   `ExportOptions.plist`. The fork's "notarized DMG / beta installs / crash-free" claims are
   fabricated. Treat the whole distribution layer as a *sketch*.
2. **`FinderTracker` is dead code** — bead bf7 is essentially unstarted. Any reliability claim is
   untested. Must be spiked on real Tahoe (consent dialog, network volumes) **and actually wired**.
3. **`mergePlaces` changes ranking behavior** — adopting it silently would alter what folder lands
   at position 1. Gate behind golden tests + an explicit decision.
4. **Bead 4g9 is only ~⅓ done by the fork** — IDE recents only; shell history + per-source
   normalization + source-diversity (the actual differentiation) must come from `spikes/seed-prototype.py`.
5. **`launch-at-login` toggle is a no-op** (no `SMAppService`); **hotkey UI cannot capture** a new chord.

---

## 4. Recommended landing sequence (Task 5) — trunk + small, test-first beads

Each step is one small PR on a branch off `main`, green CI (`swift build/test --package-path app`)
before merge. Order respects dependencies above.

1. **4g9-a — `Place` components + `Rollup.keepSubfolder`** (PORT AS-IS). Bring the `RollupTests`
   `keepSubfolder` cases first; confirm canonical's existing `RankerTests`/`RollupTests` stay green.
2. **4g9-b — `Store.swift` + `StoreTests`** (PORT AS-IS) as new files in `ZFFEngine`. Pure; no
   behavior change to ranking yet (store unused).
3. **4g9-c — Adapters module** (`HauntsAdapters` or fold into engine): protocol + 3 adapters +
   their tests + `AdapterWiringTests`. Still not wired into the running index.
4. **4g9-d — adopt `mergePlaces` in `AppState.rebuild()`** (PORT WITH CHANGES). *Test-first:* write
   golden-ranking tests capturing today's canonical order, then switch the blend, then add the
   store/adapter signal. This is the one behavior-changing step — keep it isolated.
5. **237/a07-a — `Settings.swift`** (editor targets, scan roots, hotkey config) + `SettingsTests`,
   reusing canonical's UserDefaults conventions.
6. **a07-b — configurable hotkey** end-to-end (`Settings` + remap notification + `AppDelegate`
   re-register). Manually verify on Tahoe.
7. **237-b / wtn — `PreferencesView`**, wiring launch-at-login via `SMAppService` (rewrite that bit)
   and adding light/dark handling; real hotkey capture.
8. **(polish) — `OnboardingView`.**
9. **bf7-spike — RE-VALIDATE Finder tracking** using canonical `spikes/finder-track-probe.swift` on
   real Tahoe first; only then port `trackNavigation` + a **rewritten, actually-started** tracker,
   gated behind a setting. Do not ship dead code.
10. **4g9-e — Spike-3b warm blend** (REWRITE from `spikes/seed-prototype.py`): add shell-history
    source, per-source normalization, and source-diversity weighting. This completes 4g9.
11. **Distribution track (separate, late): v3n → 4fd → 7hr.** Build a *real* bundling path
    (xcodeproj/scheme + `ExportOptions.plist` or SwiftPM bundler), then signing/notarization, then
    Sparkle against a real signed appcast. Every step verified on a clean machine. Use the fork's
    `release.yml`/`Info.plist` only as reference. **tvh (MAS)** and **CrashReporter** remain out of
    scope until the above is solid.
