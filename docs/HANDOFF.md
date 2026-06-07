# Haunts — session handoff (2026-06-07)

Resume point after a long build-out. Read `context.md` for full history; this is the "what now."

## State: feature-complete, signed+notarized, NOT yet released
- macOS menu-bar folder navigator. Swift package in `app/`; GitHub repo `rhydlewis/haunts` (local dir is still `z-for-finder`; internal SwiftPM target still `zforfinder` — intentional, don't rename).
- Targets: `ZFFEngine` (pure, tested) · `HauntsAdapters` (git/shell/editor signals) · `HauntsCore` (`AppState`, `Settings`, `FinderTracker`) · `zforfinder` (executable shell). **167 tests, CI green.**
- Done: warm-seed day-one ranking, live Finder tracking, Preferences (5 tabs, ember-branded), `.app` bundle (`scripts/build-app.sh`), sign+notarize (`scripts/sign-notarize.sh`), Sparkle auto-updates + appcast (`scripts/generate-appcast.sh`), `--diagnostics` headless smoke.
- Default hotkey: ⌥Space (was ⌃⌘Space — collided with Emoji viewer).

## Signing / release facts (reused, on this Mac)
- Developer ID Application: RHYDIAN GWYN LEWIS — **Team 87A97X8DAG**.
- notarytool creds: keychain generic-password account **`lpx-explorer`** (services APPLE_ID, APPLE_PASSWORD). Never print.
- Bundle id: **app.gethaunts.Haunts** (dev binary embedded plist aligned too).
- **Sparkle EdDSA key: SHARED with flowcus-v2 + lpx-explorer** — `SUPublicEDKey=K3ez3NH5DW5mbJbJcMWK5yvK5JYv7gjMowuMZsJwzf0=`, Sparkle's DEFAULT keychain account (no `--account`). Already backed up (it's the other apps' key).
- `SUFeedURL=https://gethaunts.app/appcast.xml` (site is LIVE).

## Launch plan — work the `launch`-tagged beads in order
1. **7hr Sparkle — DONE** (closed). Hosted update test deferred to ge2.
2. **ge2 — Release pipeline (P1) ← NEXT.** One-command: version-bump (`agvtool`/PlistBuddy on Info.plist, NOT npm) → build-app → sign-notarize → DMG → generate-appcast → `gh release create` → publish appcast.xml + latest.json to gethaunts.app. Shape from `../flowcus-v2/scripts/release.sh`; DMG on GitHub Releases, appcast on the site. **Completes Sparkle's hosted end-to-end test.** Prompt NOT yet written — to write it, peek at the live gethaunts.app site repo (sibling, e.g. `../gethaunts*`) for how it serves appcast/`latest.json`.
3. **2cp — Open With via Launch Services + manual app picker (P2, launch).** Website-independent; can run anytime. Fixes JetBrains-Toolbox (`~/Applications`) detection blind spot.
4. **6h7 — GoatCounter install/upgrade (P2, launch).** Needs user to create **haunts.goatcounter.com** site first.

## Post-launch beads
pjp (bash history in warm-seed), 2iw (login durability test), p6z (⌘, opens Settings), wtn (palette light-mode audit), gv9 (About "try my other apps").

## How `/goal` sessions run here (the working pattern)
- User runs each `docs/session-*-goal.md` prompt in a fresh session; reports back; this session vets (build/test/run, don't trust the report).
- Prompts must fit **4000 chars** (watch multibyte ⌘⌥↩ glyphs vs byte limits).
- Hard-won rules baked into every prompt: run the app via Bash `run_in_background:true` + `pkill -9 -x zforfinder` first (one instance owns the hotkey); keep `ZFFEngine` pure; Swift Testing; commit only green to `main` (no PR); **honesty mandate** (a prior fork run faked beta/notarization stats — verify, never assert).

## User TODOs (not code)
- Create **haunts.goatcounter.com** (for 6h7).
- (Optional) delete the now-unused `haunts` Sparkle keychain key.

## Next action
Write the **ge2** `/goal` prompt (peek at the live site repo first), run it, vet it → that ships Haunts v0.1.
