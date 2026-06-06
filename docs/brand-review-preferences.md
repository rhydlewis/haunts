# Brand review — Haunts Settings window

**Reviewer:** Brand Guardian
**Date:** 2026-06-06
**Reference (approved design):** `docs/preferences-mockup.html`
**Shipped implementation:** `app/Sources/zforfinder/PreferencesView.swift`
**Broader aesthetic checked:** `docs/overview.html`

---

## Verdict in one line

The structure, copy, layout and native-macOS feel of the shipped Settings window are faithful to the mockup. **The brand expression is not.** The single defining brand decision — *ember replaces system blue on the real macOS controls* — has not been applied. `Color.ember` exists and is used for decorative icons and the callout, but it is never wired to the control **tint**, so every primary interactive control (selected tab, both segmented controls, toggles, steppers, list selection, focus rings, the active text-field caret) renders in stock system blue. The window reads as generic SwiftUI, not as Haunts.

This is one root cause with broad effect, and it is cheap to fix.

---

## Brand reference points used

From the mockup and overview, the agreed identity for **this surface** is:

- **Primary accent — ember `#e8732c`** (the value already in `Color.ember`). Light variant `#ffb060`, deep `#b8410f`.
- **Secondary accent — teal `#5fd6c2`** ("repo" tags) — used in marketing/overview, not required on Settings.
- **Native macOS:** real controls, SF Pro, standard right-aligned form grid, system spacing. The mockup deliberately does **not** import the marketing site's Fraunces/IBM Plex fonts or dark editorial palette — Settings stays system-native. Honour that.
- In the mockup, the accent is applied to: **selected tab pill** (`.tab.sel`), **switches** (`.sw.on`), **segmented selection**, **popup chevron**, **checkboxes** (`.check.on`), **callout** tint/border, **list app-icon chips**, and the **About ghost gradient** (`#ffc98a → #e8732c → #b8410f`).

---

## MUST-FIX (brand-critical)

### M1 — Global accent: ember must replace system blue on all controls
**Now:** `PreferencesView.body` (lines 146–161) builds a `TabView` with no `.tint(...)`/accent applied anywhere up the tree. All controls inherit the system accent (blue, or whatever the user set in System Settings).
**Mockup/brand wants:** ember drives selection state across the whole window.
**Fix:** apply the brand tint once at the root so every descendant control inherits it:
```swift
TabView { ... }
    .frame(width: 560, height: 420)
    .tint(.ember)            // controls: toggles, steppers, list selection, focus ring
```
`.tint(.ember)` is the modern (macOS 12+) accent propagation and covers the bulk of M2–M5 in one line. Keep it at the `TabView` root (and consider also setting it on the hosting `NSWindow`/`Settings` scene so the **tab bar selection** picks it up — see M2). This is the highest-leverage change in the document.

### M2 — Selected tab pill is blue, should be ember
**Now:** the `.tabItem`-driven tab strip (lines 147–157) uses the system accent for the selected-tab highlight.
**Mockup wants:** `.tab.sel { background: ember@18%; color: ember }` — a soft ember pill with ember glyph/label (mockup line 74).
**Fix:** the toolbar-style `TabView` selection tint follows the window/app accent rather than a child `.tint` in some macOS versions. Two reliable options:
1. Set the app/window accent so the title-bar tab strip inherits ember — set `.tint(.ember)` on the top-level `Settings`/`WindowGroup` scene, or set `NSApp`'s effective accent via the hosting controller; **or**
2. If the OS still forces blue on the native segmented tab strip, treat this as the one place to verify on-device and, only if needed, replace the `.tabItem` tab strip with an explicit ember-tinted selector. Prefer option 1 — do not hand-roll the tab bar unless the OS genuinely refuses the tint, because a custom tab strip risks looking non-native (see N1).

### M3 — Appearance segmented control (System / Light / Dark) is blue
**Now:** `GeneralTab`, lines 185–191 — `Picker("Appearance", …).pickerStyle(.segmented)`. Selected segment renders blue.
**Mockup wants:** ember selected segment (`#appearanceSeg .sel`).
**Fix:** covered by root `.tint(.ember)` (M1). `.segmented` pickers honour the inherited tint for the selected-segment fill on macOS 12+. No per-control code needed once M1 lands; verify visually.

### M4 — Ranking-mode segmented control (Balanced / Frequent) is blue
**Now:** `RankingTab`, lines 230–235 — same `.segmented` picker pattern.
**Mockup wants:** ember selected segment (`#modeSeg .sel`).
**Fix:** inherited from M1. No extra code.

### M5 — Toggles render blue; mockup switches are ember
**Now:** `Toggle("Launch at login", …)` (line 183), `Toggle("Learn from navigation", …)` (line 248), `Toggle("Frequent subfolders", …)` (line 254), and the per-row editor enable `Toggle` (line 357). All inherit system blue.
**Mockup wants:** `.sw.on { background: ember }` (mockup line 100).
**Fix:** inherited from M1's `.tint(.ember)`. If a single toggle ever needs to override, `Toggle(...).tint(.ember)` works locally — but rely on the root tint to keep it consistent and DRY.

### M6 — "Record…" hotkey button uses default accent
**Now:** `GeneralTab` line 179 — `Button(model.recording ? "Stop" : "Record…")` is a plain bordered button; when focused/active its focus ring and any prominence is system blue. The recording-state field background already correctly uses `Color.ember.opacity(0.15)` (line 176) — good, keep it.
**Mockup wants:** ember focus/active treatment consistent with the rest of the window; the mockup's "Record…" is a neutral bordered button (mockup line 199), so it need **not** be a prominent ember fill.
**Fix:** the focus ring is handled by M1's tint. Do **not** make this a `.borderedProminent` ember button — the mockup keeps it neutral, and a filled button here would over-emphasise a secondary action. Leave style native; tint fixes the ring.

---

## POLISH (nice-to-have, after the must-fixes)

### P1 — Scan-root / editor list selection highlight
`FoldersTab` (List, lines 283–301) and `OpenWithTab` (List, lines 354–365) use `List(selection:)`. The row selection highlight inherits the accent — once M1 lands it becomes ember, matching `.lrow:hover`/selection feel in the mockup. No code change; just confirm the selected-row fill reads as ember and stays legible (see A2).

### P2 — List "app icon" chip background
**Mockup:** each list row has a rounded ember-tinted chip behind the icon — `.lrow .appicon { background: ember@16% }` (mockup line 147), and folder/home/editor glyphs sit inside it.
**Now:** `Image(systemName: …).foregroundStyle(Color.ember)` only (lines 286–287, 358) — ember glyph, but no chip background.
**Fix (optional):** wrap the icon in a small rounded ember-wash background to match the mockup's chip:
```swift
Image(systemName: …)
    .foregroundStyle(Color.ember)
    .frame(width: 20, height: 20)
    .background(Color.ember.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
```
Minor; the bare ember glyph already carries brand colour. Skip if it fights native `List` row metrics.

### P3 — Callout iconography
**Mockup:** ranking callout uses a `✦` ember mark (mockup line 238).
**Now:** `RankingTab` lines 237–244 uses `Image(systemName: "sparkles")` in `Color.ember` with ember 9% fill + 22% border — this is an **accurate** match to `.callout` (mockup lines 164–166). No change. (Noting it as a positive: this section is already on-brand.)

### P4 — About ghost gradient depth
**Mockup:** the about ghost tile is a **3-stop radial** gradient `#ffc98a → #e8732c (55%) → #b8410f` with inner highlight + inner shadow and an ember drop-shadow (mockup lines 326–329) — gives a rounded, glossy "ember orb."
**Now:** `AboutTab` lines 412–416 uses a **2-stop linear** gradient `#ffca8a → .ember` (top-leading → bottom-trailing). Close, but flatter and missing the deep `#b8410f` foot and the glow.
**Fix (optional polish):** move to a radial gradient with the deep stop and add the soft ember shadow to match the mockup's premium feel:
```swift
RoundedRectangle(cornerRadius: 21, style: .continuous)
    .fill(RadialGradient(
        colors: [Color(red:1,green:0.79,blue:0.54), .ember, Color(red:0xB8/255,green:0x41/255,blue:0x0F/255)],
        center: .init(x:0.3,y:0.2), startRadius: 4, endRadius: 96))
    .shadow(color: .ember.opacity(0.55), radius: 13, y: 8)
```
This is the brand's hero moment on this surface; worth the polish.

### P5 — Buy-me-a-coffee button
`AboutTab` lines 429–432 — already `.borderedProminent` with `.tint(.ember)`. **On-brand, matches `.btn.accent`** (mockup line 339). No change. (Positive note.)

### P6 — Tagline / About typography
**Mockup:** tagline `"Jump to your haunts."` italic secondary (line 333); shipped matches (line 421). About uses SF Pro throughout, correctly — do **not** pull in the marketing Fraunces/IBM Plex here. Native typography is correct on this surface; flagging only to prevent over-styling (see N2).

### P7 — Token hygiene: define the full ember ramp once
**Now:** `Color.ember` is a single value (lines 8–11). Light/deep variants are re-inlined ad hoc (e.g. About gradient hardcodes `1,0.79,0.54`).
**Fix (optional):** add `Color.emberLight (#ffb060)` and `Color.emberDeep (#b8410f)` next to `.ember`, plus a teal `#5fd6c2` if any "repo" tag ever appears in Settings. Centralising the ramp makes future surfaces consistent and prevents drift. Low effort, good long-term brand-protection hygiene.

---

## Where native macOS convention should win over the mockup (do NOT over-style)

- **N1 — Tab strip:** prefer tinting the OS-native `.tabItem` tab strip (M2 option 1) over hand-rolling a custom pill bar. A bespoke tab bar that doesn't exactly match the system risks looking *less* premium and breaks platform muscle-memory. Only customise if the OS truly refuses the ember tint.
- **N2 — Typography:** keep SF Pro. The marketing site's Fraunces/IBM Plex belong on the web, not in a system Settings window. The mockup deliberately uses `-apple-system` — honour it. Branding here = accent colour + the About hero, **not** custom fonts.
- **N3 — Popup/stepper chrome:** the mockup draws an ember chevron chip on popups (lines 117–119) and custom stepper arrows. Do **not** replicate these as custom-drawn controls in SwiftUI; native `Picker`/`Stepper` are the right call and the mockup's chrome is just an HTML approximation of the system look. Leave them native.
- **N4 — "Record…" button:** keep neutral/bordered, not prominent ember (see M6) — matches mockup and avoids over-emphasis.
- **N5 — Reset Learned Data button:** native bordered button is correct; do not ember-fill a destructive-adjacent action.

---

## Accessibility / contrast risks

- **A1 — Ember-on-white text (light mode):** `#e8732c` on white is ~**3.0:1** contrast — **below WCAG AA (4.5:1) for normal text.** This is fine for *large* text, icons, and non-text UI (the 18% tab pill, switch fills, selected segments are all surfaces/large/non-text, and pass the 3:1 non-text threshold). But **avoid ember for small body/label text on white.** The shipped code already keeps body copy in `.primary`/`.secondary` and uses ember only for icons/fills/the callout — keep it that way. Flag: the mockup's About credit link `color: ember` on white (mockup line 345) is borderline; if ported, use ember at semibold or `#b8410f` (deep) for link text to clear AA.
- **A2 — Ember selection fill behind text (lists):** when a list row becomes a solid ember selection, ensure the row label flips to white/high-contrast (system does this automatically for accent selections; verify after M1). Ember@~3:1 behind dark text is too low.
- **A3 — Dark mode:** ember `#e8732c` on the dark content `#2A2A2C` is ~**4.4:1** — comfortable for non-text and borderline-OK for large text. Better than light mode. Consider using `emberLight #ffb060` for any *text* element in dark mode to lift contrast.
- **A4 — Selected-segment / switch:** white knob/label on ember fill is high-contrast and safe in both modes.
- **A5 — Don't rely on colour alone:** selection state is also conveyed by position/fill shape (segments, switch knob), so colour-blind users aren't blocked. Good — maintain this.

---

## Suggested order of work

1. **M1** — add `.tint(.ember)` at the `TabView` root (and the `Settings` scene for the tab strip). *One change resolves M3, M4, M5, P1, and most of M6.*
2. **M2** — verify/secure the selected-tab pill is ember (scene/window accent).
3. Visual pass to confirm M3–M6 inherited correctly on-device.
4. **P4** (About ghost orb) and **P7** (token ramp) for premium polish + future-proofing.
5. **P2** (icon chips) only if it sits cleanly in native list metrics.

The decorative ember usage already shipped (callout P3, coffee button P5, ember icons, recording-state field) is **correct and on-brand** — the gap is almost entirely the missing control tint, not a wholesale restyle.
