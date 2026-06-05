import AppKit
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState!
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var keyMonitor: Any?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        state.rebuild()

        // SwiftUI content hosted inside the AppKit panel
        let host = NSHostingView(rootView: PaletteView().environmentObject(state))
        panel = FloatingPanel(contentView: host, size: NSSize(width: 640, height: 420))
        panel.delegate = self

        setupStatusItem()

        // ⌃⌘Space — Carbon hotkey (no special permissions required)
        hotKey = HotKey(keyCode: UInt32(kVK_Space),
                        modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
        if hotKey == nil { NSLog("z-for-finder: failed to register ⌃⌘Space hotkey") }

        // Key routing while the palette is open (focus-stable, AppKit-level)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:     self.hide(); return nil
            case kVK_DownArrow:  self.state.move(1); return nil
            case kVK_UpArrow:    self.state.move(-1); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                let mode: OpenMode = event.modifierFlags.contains(.command) ? .editor
                    : event.modifierFlags.contains(.control) ? .terminal : .finder
                self.state.activate(mode); self.hide(); return nil
            default:
                return event   // let the text field handle typing
            }
        }

        NotificationCenter.default.addObserver(forName: .zffHide, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⌁"
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open  (⌃⌘Space)", action: #selector(toggle), keyEquivalent: "")
        let rebuild = NSMenuItem(title: "Rebuild index", action: #selector(rebuildIndex), keyEquivalent: "r")
        let quit = NSMenuItem(title: "Quit z for Finder", action: #selector(quit), keyEquivalent: "q")
        [open, rebuild, quit].forEach { $0.target = self }
        menu.addItem(open); menu.addItem(.separator()); menu.addItem(rebuild); menu.addItem(quit)
        statusItem.menu = menu
    }

    @MainActor @objc private func toggle() {
        panel.isVisible ? hide() : show()
    }
    @MainActor private func show() {
        state.prepareForShow()
        panel.showCentered()
    }
    @MainActor private func hide() {
        panel.orderOut(nil)
    }
    @MainActor @objc private func rebuildIndex() { state.rebuild() }
    @objc private func quit() { NSApp.terminate(nil) }

    // hide when the user clicks away
    func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in self.hide() }
    }
}
