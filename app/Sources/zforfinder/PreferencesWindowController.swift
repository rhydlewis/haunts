import AppKit
import SwiftUI
import HauntsCore

/// Hosts `PreferencesView` in a standard titled NSWindow. The app uses an AppKit
/// lifecycle (no SwiftUI `App`/`Settings` scene), so the window is created by hand.
@MainActor
final class PreferencesWindowController: NSWindowController {
    private let model: PreferencesModel

    init(appState: AppState?) {
        self.model = PreferencesModel(appState: appState)
        let hosting = NSHostingController(rootView: PreferencesView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Haunts Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}
