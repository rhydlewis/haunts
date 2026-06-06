# Goal: Build the gethaunts.app marketing website

Build the marketing/landing website for **Haunts**, a macOS menu-bar app. Use the **frontend-design skill** — this is a marketing site, so a bold, distinctive, memorable design is wanted (NOT the restrained native-macOS look; that's only for the app's own UI). Production-grade, fast, accessible, responsive.

## The product (what you're selling)
**Haunts** — a keyboard-first macOS navigator that **learns where you actually work and takes you there instantly**. Hit **⌃⌘Space**, type a couple of letters, land in the folder/project — in Finder, your editor, or a terminal. It's not an app launcher and not "better Spotlight feature-for-feature": it's a *focused navigator* that's **warm from day one** (ranks by frequency × recency of where you go) and **never misses**. Menu-bar only, no Dock icon. Private — everything stays on your Mac. Auto-updates via Sparkle.

- **Tagline:** "Jump to your haunts."
- **One-liner:** The fastest way back to the folders you live in.
- **Audience:** Mac developers / power users with lots of projects who move between Finder, editors and terminals all day.
- **Honest differentiation** (use, don't overclaim): Spotlight does too much and is flaky; Raycast/Alfred are broad launchers that start cold. Haunts is narrow, **starts warm**, learns your places, and just works. (Spiritual successor to the terminal `z`/`zoxide`, set free into the GUI.)
- **Status:** new / pre-1.0. Do NOT invent testimonials, user counts, awards, or "trusted by X developers" — there are none yet. Honest and confident, not fake-popular.

## Brand kit (reuse — don't reinvent)
- **Look already established in:** `docs/overview.html` (the dossier — ember/charcoal, editorial serif + mono, warm glow, hexagon/grain). **Echo this aesthetic** so the site feels like the app.
- **Ember ramp:** glow `#FFC98A` · ember `#E8732C` · deep `#B8410F`. Warm charcoal darks (`#0e0c0b`/`#161109`). Teal `#5fd6c2` as a sparing secondary.
- **Type:** distinctive display serif (Fraunces) + mono (IBM Plex Mono); body IBM Plex Sans. (Matches `docs/overview.html`.)
- **Mascot:** the friendly ghost. Glyph asset: `docs/assets/menubar-ghost.svg`. The colour app icon is being generated separately — use a placeholder/the ghost for now.
- **UI to show off:** `docs/preferences-mockup.html` and the palette visual in `docs/overview.html` — render/screenshot a palette mock for the hero/how-it-works.
- **Voice:** warm, sharp, a little playful (ghost puns are fair game), developer-credible, honest.

## Tech / stack
Match the existing app sites for consistency + release-pipeline compatibility: **Eleventy + Nunjucks, deployed on Netlify**, with `src/latest.json` (`{ version, filename }`) as the version/download source of truth (see `../flowcus-eleventy` for the exact pattern: `latest.json`, partials, `changelog`, `llms.njk`, `sitemap.njk`). A clean standalone static site is acceptable if simpler, but keep `latest.json` + a changelog so the release script can update them.
- Build as a **sibling repo** (e.g. `../gethaunts` or `../haunts-site`), not inside the app repo.
- **Download CTA** → the latest `.dmg` from the app's GitHub Releases (URL pattern from `../lpx-explorer/scripts/generate-appcast.sh`). Show "requires macOS 14+".
- **Host `appcast.xml`** at `gethaunts.app/appcast.xml` — the app's Sparkle `SUFeedURL` already points there. The release pipeline generates the file; the site just needs to serve it (place it where Netlify publishes it).
- Free / donationware: a prominent **Buy me a coffee** (buymeacoffee.com/rhydlewis) and GitHub link.

## Page / sections (single landing page + a couple of sub-pages)
1. **Hero** — ghost/icon, "Haunts", tagline, the ⌃⌘Space pitch with a palette mock, Download button (+ macOS 14+), and a one-line "what it is."
2. **The problem → the promise** — Spotlight is flaky and does too much; Haunts is a focused navigator that's warm on day one and never misses.
3. **How it works** — hotkey → warm pre-ranked palette → land (Finder / editor / terminal). Three keystrokes: ↩ Finder · ⌘↩ editor · ⌃↩ terminal.
4. **Features** — learns where you work (frecency); warm from launch; open three ways; configurable (hotkey, scan roots, editors, Balanced/Frequent ranking); light & dark; private/local; auto-updates.
5. **Why not Spotlight / Raycast / Alfred** — honest, respectful framing of the focused-and-warm difference.
6. **Privacy** — everything stays on your Mac; clear about the one-time Automation (Finder) consent and that nothing is uploaded.
7. **Download / support** — DMG download, "free — buy me a coffee if it saves you time", GitHub, changelog link.
8. **Footer** — GitHub, privacy, changelog/release notes, "Made by Rhyd Lewis", ©.
- Plus: **/changelog** (from release notes) and an **llms.txt / llms page** (like flowcus) for AI crawlers.

## Production checklist
- SEO meta + OpenGraph/Twitter card (ghost OG image, 1200×630), favicon (ghost), `sitemap.xml`, `robots.txt`.
- Responsive (mobile→desktop), accessible (contrast — remember ember `#E8732C` on white is ~3:1, fine for large/icons but use deep `#B8410F` or semibold for small ember text), prefers-color-scheme aware.
- Fast: no heavy frameworks needed; optimise images; lazy-load.
- One well-orchestrated hero load (staggered reveal) beats scattered micro-animations.

## Out of scope
The app itself; generating `appcast.xml` (the release pipeline does that — the site just serves it); payment processing; fabricated social proof.

## Honesty
This is a new product. No invented stats, testimonials, ratings, or popularity claims. Confident and clear about what it does — nothing it hasn't earned.
