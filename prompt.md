# Kickoff Prompt — z for Finder

Paste this to a coding agent working in `/Users/rhyd/code/z-for-finder`.

---

You're picking up a project to build **"z for Finder"** — a native macOS app that's a frecency-ranked, keyboard-first navigator for the folders and files I actually use. Think `rupa/z` (the terminal directory-jumper) but as a system-wide hotkey app, built to be a reliable replacement for flaky Tahoe Spotlight.

**Before writing any code, read these two files in full:**
- `docs/ideas/z-for-finder.md` — the spec (problem, recommended direction, assumptions, MVP scope, not-doing list).
- `context.md` — what we decided and what we already tested on this machine.

## Non-negotiable constraints (learned the hard way — see context.md)
- The product promise is **reliability: "it works every time, in 50ms."** Every decision serves that. Cut anything that threatens it.
- **Do NOT use the `mdls` CLI or `kMDItemUseCount`** — both are proven broken on this Tahoe machine. Use **`NSMetadataQuery`** (framework) for recency and parse **`~/Library/Application Support/com.apple.sharedfilelist/`** for frequency.
- This is a **navigator**, not an app launcher and not a context-orchestrator (no opening 3 apps at once). Folders → Finder, files → default app, folder → editor/terminal as a single secondary action.
- Validate the ranking **brain** before building the native **shell**. Don't gold-plate UI on top of an unproven signal.

## Your first task: Spike 1 — close the #1 red risk
**Question to answer:** Does `NSMetadataQuery` (the framework) reliably return `kMDItemLastUsedDate` where the `mdls` CLI fails on Tahoe?

Write a minimal Swift command-line tool (Swift Package or a single `swift` script — no app, no UI) that:
1. Runs an `NSMetadataQuery` for items with `kMDItemLastUsedDate` within the last 30 days, scoped to the home directory.
2. For each result, reads `kMDItemPath` and `kMDItemLastUsedDate`.
3. Rolls results up to **parent folder**, filtering out `/Library/`, dotfile paths, and `/Applications/`.
4. Prints the top ~25 folders ranked by a simple frecency score (recency-weighted count is fine for the spike).

**Success = the output lists my real working folders** (expect things like `~/code/*`, `~/Music/Logic`, `~/Finance/beancount/ledger`, `~/Documents/Claude/Projects/*`) and the query returns dates the CLI couldn't. The bash equivalent of this query already produced good folders (see `context.md`) — the spike proves the *framework* path works for a real app.

Report back:
- Did `NSMetadataQuery` return `kMDItemLastUsedDate` values? (This is the gate.)
- Paste the top-25 folder ranking so I can eyeball signal quality.
- Note any permission prompts (Full Disk Access?), latency, or Tahoe quirks.
- Recommend the frecency scoring formula (recency half-life + frequency weighting) for the next step.

**Do not** scaffold the menu-bar app, hotkey handling, or palette UI yet. Spike 1 is a throwaway probe to confirm the signal is real. If it's green, the next step is a `sharedfilelist` frequency parser to blend in, then a ranking prototype, then the native shell.

Keep it small. Ask me before adding dependencies or expanding scope.
