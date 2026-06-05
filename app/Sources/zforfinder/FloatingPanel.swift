import AppKit

/// A Spotlight-style overlay: borderless, non-activating, floats above other
/// apps and joins all Spaces. Must override canBecomeKey so the search field
/// can receive typing without fully activating the app.
final class FloatingPanel: NSPanel {
    init(contentView: NSView, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showCentered() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let f = frame
        let x = vf.midX - f.width / 2
        let y = vf.midY + vf.height * 0.10   // upper-middle, like Spotlight
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
