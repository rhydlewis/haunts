import AppKit
import SwiftUI
import Carbon.HIToolbox
import HauntsCore
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState!
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var prefsWindowController: PreferencesWindowController?
    private let finderTracker = FinderTracker()

    // Sparkle auto-updater (bead 7hr). Owns the update lifecycle; reads SUFeedURL
    // + SUPublicEDKey from Info.plist at runtime. `startingUpdater: true` schedules
    // background checks; the status-menu "Check for Updates…" item drives a manual
    // check via its checkForUpdates(_:) action.
    private var updaterController: SPUStandardUpdaterController!

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance(Settings.appearance)   // honor persisted Light/Dark/System

        state = AppState()
        state.rebuild()

        // SwiftUI content hosted inside the AppKit panel
        let host = NSHostingView(rootView: PaletteView().environmentObject(state))
        panel = FloatingPanel(contentView: host, size: NSSize(width: 640, height: 420))
        panel.delegate = self

        // Start Sparkle before building the status menu so the "Check for
        // Updates…" item can target the live updater.
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                        updaterDelegate: nil,
                                                        userDriverDelegate: nil)

        setupStatusItem()

        registerHotKey()   // reads the chord from Settings
        NotificationCenter.default.addObserver(forName: .zffRemapHotKey, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.registerHotKey() }
        }

        // Key routing while the palette is open (focus-stable, AppKit-level)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            switch Int(event.keyCode) {
            case kVK_ANSI_Comma:
                // ⌘, opens Settings and dismisses the palette (the status-menu
                // keyEquivalent only fires when a Haunts window is key, which the
                // non-activating panel isn't). Plain ',' must still type into the
                // query field, so require Command.
                guard event.modifierFlags.contains(.command) else { return event }
                self.openSettings(); self.hide(); return nil
            case kVK_Escape:     self.hide(); return nil
            case kVK_DownArrow:  self.state.move(1); return nil
            case kVK_UpArrow:    self.state.move(-1); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                let mode: OpenMode = event.modifierFlags.contains(.command) ? .editor
                    : event.modifierFlags.contains(.control) ? .terminal : .finder
                self.state.activate(mode); self.hide(); return nil
            case kVK_Delete:
                // ⌘⌫ forgets the selected row. Plain ⌫ must pass through so it still
                // edits the query text. (Distinct from ↩/⌘↩/⌃↩/Esc/↑↓.)
                guard event.modifierFlags.contains(.command) else { return event }
                self.forgetSelected(); return nil
            default:
                return event   // let the text field handle typing
            }
        }

        NotificationCenter.default.addObserver(forName: .zffHide, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }

        // Anonymous install/upgrade count (bead 6h7). Fire-and-forget and
        // fail-silent — fires at most one ping per version change, never blocks
        // launch, and honors the Settings ▸ General opt-out.
        Analytics.reportLaunch()

        // First-run prompt: ask once whether to open Haunts at login (bead 2iw).
        // Deferred to the next runloop tick so the menu-bar item is in place
        // before the modal alert steals focus.
        DispatchQueue.main.async { [weak self] in self?.maybePromptLaunchAtLogin() }

        // Live Finder-navigation tracking — start only if the user opted in; the
        // Ranking tab's toggle posts .zffToggleLearnFromNavigation when it flips.
        syncNavigationTracking()
        NotificationCenter.default.addObserver(forName: .zffToggleLearnFromNavigation, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncNavigationTracking() }
        }
    }

    /// Show the one-time "Open Haunts at login?" prompt on the very first launch
    /// (bead 2iw). Gated on `Settings.hasSeenLaunchPrompt`, which is flipped true
    /// as soon as the prompt is shown so it never reappears on subsequent launches.
    /// The user's choice writes `Settings.launchAtLogin` and drives the real
    /// `SMAppService` registration via `LaunchAtLogin.set`.
    @MainActor private func maybePromptLaunchAtLogin() {
        guard !Settings.hasSeenLaunchPrompt else { return }
        Settings.hasSeenLaunchPrompt = true

        let alert = NSAlert()
        alert.messageText = "Open Haunts automatically at login?"
        alert.informativeText = "Haunts lives in the menu bar and stays ready for "
            + HotKeyUtils.displayString(keyCode: Settings.hotkeyKeyCode,
                                        carbonModifiers: Settings.hotkeyModifiers)
            + ". You can change this any time in Settings."
        alert.addButton(withTitle: "Enable")    // default (return)
        alert.addButton(withTitle: "Not Now")

        let enable = alert.runModal() == .alertFirstButtonReturn
        Settings.launchAtLogin = enable
        LaunchAtLogin.set(enable)
        NSLog("Haunts: first-run launch-at-login prompt -> \(enable ? "Enable" : "Not Now")")
    }

    /// Start or stop the FinderTracker to match the persisted Learn-from-navigation
    /// setting. Off means no polling at all.
    @MainActor private func syncNavigationTracking() {
        let on = Settings.learnFromNavigation
        NSLog("Haunts: navigation tracking \(on ? "ON" : "OFF")")
        if on {
            finderTracker.start(appState: state)
        } else {
            finderTracker.stop()
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
        // Sparkle drives this one: its action + validateMenuItem live on the
        // updater controller, not AppDelegate.
        let checkUpdates = NSMenuItem(title: "Check for Updates…",
                                      action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                      keyEquivalent: "")
        checkUpdates.target = updaterController
        menu.addItem(open); menu.addItem(.separator())
        menu.addItem(rebuild); menu.addItem(settings)
        menu.addItem(checkUpdates)
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
    /// Forget the currently-selected palette row (⌘⌫): drop it from the learned
    /// store and the live index so the row disappears immediately.
    @MainActor private func forgetSelected() {
        let results = state.results
        guard results.indices.contains(state.selection) else { return }
        state.forget(path: results[state.selection].path)
    }

    @MainActor @objc private func rebuildIndex() { state.rebuild() }
    @objc private func quit() { NSApp.terminate(nil) }

    // hide when the user clicks away
    func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in self.hide() }
    }
}
