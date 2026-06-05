import AppKit

// z for Finder — thin vertical slice.
// AppKit owns lifecycle + the floating panel + the global hotkey;
// SwiftUI (PaletteView) renders the content inside it.
// Agent app: no Dock icon, lives in the menu bar.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
