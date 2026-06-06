import AppKit
import SwiftUI
import Carbon.HIToolbox
import HauntsCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState!
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var prefsWindowController: PreferencesWindowController?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance(Settings.appearance)   // honor persisted Light/Dark/System

        state = AppState()
        state.rebuild()

        // SwiftUI content hosted inside the AppKit panel
        let host = NSHostingView(rootView: PaletteView().environmentObject(state))
        panel = FloatingPanel(contentView: host, size: NSSize(width: 640, height: 420))
        panel.delegate = self

        setupStatusItem()

        registerHotKey()   // reads the chord from Settings
        NotificationCenter.default.addObserver(forName: .zffRemapHotKey, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotKey() }
        }

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
        if let button = statusItem.button {
            button.image = GhostIcon.menuBarImage(size: 18)   // template glyph (tints in light/dark)
            button.image?.accessibilityDescription = "Haunts"
        }
        let chord = HotKeyUtils.displayString(keyCode: Settings.hotkeyKeyCode,
                                              carbonModifiers: Settings.hotkeyModifiers)
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open  (\(chord))", action: #selector(toggle), keyEquivalent: "")
        let rebuild = NSMenuItem(title: "Rebuild index", action: #selector(rebuildIndex), keyEquivalent: "r")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit Haunts", action: #selector(quit), keyEquivalent: "q")
        [open, rebuild, settings, quit].forEach { $0.target = self }
        menu.addItem(open); menu.addItem(.separator())
        menu.addItem(rebuild); menu.addItem(settings)
        menu.addItem(.separator()); menu.addItem(quit)
        statusItem.menu = menu
    }

    /// (Re)register the global hotkey from the persisted Settings chord.
    @MainActor private func registerHotKey() {
        hotKey = nil   // deinit unregisters the previous one
        hotKey = HotKey(keyCode: Settings.hotkeyKeyCode,
                        modifiers: Settings.hotkeyModifiers) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
        if hotKey == nil { NSLog("Haunts: failed to register hotkey") }
        // Keep the menu hint in sync with the current chord.
        if let item = statusItem?.menu?.items.first {
            let chord = HotKeyUtils.displayString(keyCode: Settings.hotkeyKeyCode,
                                                  carbonModifiers: Settings.hotkeyModifiers)
            item.title = "Open  (\(chord))"
        }
    }

    @MainActor @objc private func openSettings() {
        if prefsWindowController == nil {
            prefsWindowController = PreferencesWindowController(appState: state)
        }
        prefsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
