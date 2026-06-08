import AppKit

// z for Finder — thin vertical slice.
// AppKit owns lifecycle + the floating panel + the global hotkey;
// SwiftUI (PaletteView) renders the content inside it.
// Agent app: no Dock icon, lives in the menu bar.

// Headless diagnostics (no GUI) — used to verify the assembled .app bundle from
// the command line, where a locked screen makes the Preferences toggle
// unclickable. Also handy for ge2 release smoke-tests. Exits without app.run().
if CommandLine.arguments.contains("--diagnostics") {
    Diagnostics.run()
    exit(0)
}

// Headless cleanup: unregister the SMAppService login item for this bundle id.
// Useful after testing the first-run prompt from a debug build, which registers
// a real login item under the shared `app.gethaunts.Haunts` identity. Exits
// without app.run().
if CommandLine.arguments.contains("--unregister-login") {
    Diagnostics.unregisterLogin()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
