GOAL: Change Haunts' DEFAULT summon hotkey off ⌃⌘Space (bead 8wa) — it collides with macOS's Emoji & Symbols viewer, so a fresh user's first press pops the emoji picker, not Haunts. Repo: /Users/rhyd/code/z-for-finder (Swift package in app/; GitHub rhydlewis/haunts). Test-first; small commits to main; end on GREEN CI.

DECISION (use this): new default = ⌥Space (Option-Space). It's the conventional launcher chord and is clear of macOS symbolic hotkeys (⌘Space=Spotlight, ⌃Space/⌃⌥Space=input source, ⌃⌘Space=emoji) and of Finder's ⌘⇧H=Home. Carbon: keyCode kVK_Space (49), modifiers optionKey (2048). If you find ⌥Space already registered/conflicting on this Mac (defaults read com.apple.symbolichotkeys), fall back to ⌘⇧Space and note why.

READ FIRST: `bd show z-for-finder-8wa` (the analysis); HauntsCore/Settings.swift (defaultHotkeyKeyCode / defaultHotkeyModifiers); AppDelegate (registerHotKey reads Settings; menu hint); HotKeyUtils (display string); PreferencesView General tab (hotkey display).

BUILD:
- In HauntsCore/Settings.swift change defaultHotkeyModifiers from cmdKey|controlKey (256+4096=4352) to optionKey (2048); keep defaultHotkeyKeyCode = 49 (Space). This is the core change. Settings.hotkeyModifiers returns the STORED value if the user rebound, else this default — so only fresh/unmodified installs flip; anyone who customised keeps theirs.
- Verify the chain still renders the new default: AppDelegate.registerHotKey reads Settings.hotkey* (it does); the status-menu "Open (…)" hint and the Preferences recorder display both come from HotKeyUtils.displayString.
- Update any test/fixture that hard-codes the OLD default — search Tests + Settings for 4352, cmdKey|controlKey, "⌃⌘Space", 256+4096.

OUT OF SCOPE: the recorder UI / re-register logic (already shipped in a07) — just the DEFAULT. Nothing else.

GOTCHAS:
- Run the app as a background task (foreground nohup gets killed). FIRST `pkill -9 -x zforfinder` — one instance only; a stale one tests the wrong build. Confirm via pgrep -x zforfinder. (The process is still named zforfinder.)
- Only one process can own a global hotkey — make sure you're testing the NEW build, not a stale instance.
- Keep ZFFEngine pure. Swift Testing, not XCTest.

DONE = each TRUE + VERIFIED: the default constant = ⌥Space (keyCode 49 / optionKey 2048); a FRESH launch (no stored override) registers it and **pressing ⌥Space opens the palette**; ⌃⌘Space no longer summons Haunts (free for the emoji viewer); the menu hint + Preferences General both show the new default; rebinding via the recorder still works; updated tests pass; swift build + `swift test --package-path app` green; pushed; CI green.

VERIFY, DON'T ASSERT: build + run (pkill+background) with no stored override (fresh defaults); press ⌥Space → palette opens; press ⌃⌘Space → it does NOT open Haunts. Capture what you saw. If the screen is locked and you can't inject keys, say so honestly — you can still confirm registration ran (no "failed to register hotkey" line) + the default constant/display value. `gh run watch`; then close 8wa + note in context.md.

HONESTY: a prior run here faked stats — unacceptable. Report only what you built/tested/ran; state partials plainly (e.g. couldn't inject the keypress on a locked screen). Commit only green. Trunk-based small commits to main (no PR). End commits: Co-Authored-By: Claude <noreply@anthropic.com>
