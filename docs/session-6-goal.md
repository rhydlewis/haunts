GOAL: Finish Haunts' ranking brain (Session 6): port the warm-seed blend so the app is correct on DAY ONE (before any navigation), and add a palette shortcut to forget one learned folder. Repo: /Users/rhyd/code/z-for-finder (Swift package in app/). Test-first; small commits to main; end on GREEN CI.

WHY: the index sums RAW per-source weights, so one source can dominate; it has no shell-history signal and no multi-source-agreement boost. A spike proved a better blend (4g9, the differentiation). Plus 9fs: prune a bad learned folder.

READ FIRST:
- spikes/seed-prototype.py — VALIDATED prototype; the SPEC. Read its comments/output for the exact formulas: per-source normalization, source-diversity weighting, and the source set (git, shell history, IDE recents, Spotlight meta).
- context.md (decisions + seed findings); docs/harvest-plan.md.
- app/Sources/ZFFEngine/{RankingMode,Store,Ranker,Scoring}.swift + HauntsCore/AppState.swift (current blend = Frecency.blend, additive).
- `bd show z-for-finder-4g9`; `bd show z-for-finder-9fs`.

ARCHITECTURE: ZFFEngine = pure (AppKit-free); HauntsAdapters = signal sources; HauntsCore = AppState + Settings; zforfinder = shell. Tests: app/Tests/ZFFEngineTests (Swift Testing); 144 pass; CI runs swift build+test.

BUILD — 4g9 (warm-seed blend):
- In a PURE ZFFEngine function (extend Frecency.blend or add one), port from seed-prototype.py: normalize each source's contribution to 0..1 within that source × a per-source trust weight, sum, then add a small bonus for source DIVERSITY (distinct-source count). Deterministic (inject now). Unit-test: a high-volume source must NOT dominate; multi-source folders rank above single-source; all-empty is stable.
- Add a SHELL-HISTORY source: parse ~/.local/share/fish/fish_history (+ ~/.zsh_history) for cd targets/dirs → [URL]+counts. The PARSE is a pure function (text → paths+counts), unit-tested; the file read is the impure shell. Feed it in like the editor adapters; roll up to git roots; obey existing transient rules.
- Wire into AppState.rebuild so the day-one index (empty Store) is warm from git+shell+IDE+meta.

BUILD — 9fs (forget from the palette):
- Store.forget(path:) — pure, removes all PlaceRecords for a path; unit-test. AppState.forget(path:) → store.forget + reblend + drop from index now.
- Wire a key in AppDelegate.keyMonitor (only when the panel is visible) on the SELECTED result: chord ⌘⌫. Must NOT clash with ↩/⌘↩/⌃↩/Esc/↑↓. Row disappears after. Delete-only (may re-learn later — fine).

OUT OF SCOPE: distribution (.app/sign/Sparkle/release); app icon; tab-pill accent; a permanent denylist.

GOTCHAS:
- Run the app as a background task (foreground nohup gets killed). FIRST `pkill -9 -x zforfinder` — one instance only; a stale one tests the wrong build. Confirm via pgrep -x zforfinder.
- Keep ZFFEngine pure (no AppKit/SwiftUI/file-I/O in the blend math — pass data in). Swift Testing, not XCTest.
- Blend change = ranking change: write golden/characterization tests of the current top-N FIRST, then change, so the shift is deliberate.

DONE = TRUE + VERIFIED: normalization + diversity ported & unit-tested (incl. no-single-source-dominates + multi-source-lifts); shell parse pure + tested; day-one index with EMPTY Store surfaces real working folders (git+shell+IDE+meta); ⌘⌫ on a palette row removes it from store + palette; all prior tests pass; swift build + `swift test --package-path app` green; pushed; CI green.

VERIFY, DON'T ASSERT: swift test each step; then run the app (pkill+background) with the store emptied, ⌃⌘Space, confirm the warm list looks right; pick a junk row, ⌘⌫, confirm gone from palette AND frecency.json. `gh run watch`. Then close 4g9 + 9fs; note in context.md.

HONESTY: a prior run here faked beta/crash stats — unacceptable. Report only what you built/tested/ran; state partials plainly. Commit only green. Trunk-based small commits to main (no PR). End commits: Co-Authored-By: Claude <noreply@anthropic.com>
