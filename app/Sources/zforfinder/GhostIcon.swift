import AppKit

/// The Haunts ghost, drawn in code from `docs/assets/menubar-ghost.svg`.
/// NSImage can't load SVG, so the path is transcribed to `NSBezierPath`.
/// Returned as a template image so macOS tints it correctly in light & dark menu bars.
enum GhostIcon {

    /// Menu-bar template glyph. Crisp at any scale (the drawing handler re-runs
    /// per backing-scale). Default 18pt to sit well in the status bar.
    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            // SVG viewBox is 24×24, y-down — `flipped: true` matches that.
            let s = rect.width / 24.0
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

            let path = NSBezierPath()
            // Body silhouette (cubic béziers + lines), traced from the SVG `d`.
            path.move(to: p(12, 2.5))
            path.curve(to: p(4.8, 9.7),  controlPoint1: p(8, 2.5),    controlPoint2: p(4.8, 5.7))
            path.line(to: p(4.8, 18.9))
            path.curve(to: p(7, 19.8),   controlPoint1: p(4.8, 20),   controlPoint2: p(6.1, 20.6))
            path.line(to: p(8.2, 18.7))
            path.curve(to: p(9.7, 18.7), controlPoint1: p(8.6, 18.3), controlPoint2: p(9.3, 18.3))
            path.line(to: p(10.9, 19.8))
            path.curve(to: p(13.1, 19.8), controlPoint1: p(11.5, 20.4), controlPoint2: p(12.5, 20.4))
            path.line(to: p(14.3, 18.7))
            path.curve(to: p(15.8, 18.7), controlPoint1: p(14.7, 18.3), controlPoint2: p(15.4, 18.3))
            path.line(to: p(17, 19.8))
            path.curve(to: p(19.2, 18.9), controlPoint1: p(17.9, 20.6), controlPoint2: p(19.2, 20))
            path.line(to: p(19.2, 9.7))
            path.curve(to: p(12, 2.5),   controlPoint1: p(19.2, 5.7), controlPoint2: p(16, 2.5))
            path.close()

            // Eyes — cut out via even-odd. Circles r=1.35 centred at y=10.45.
            let r: CGFloat = 1.35 * s
            path.appendOval(in: NSRect(x: 9.9 * s - r, y: 10.45 * s - r, width: 2 * r, height: 2 * r))
            path.appendOval(in: NSRect(x: 14.1 * s - r, y: 10.45 * s - r, width: 2 * r, height: 2 * r))

            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Filled ember-gradient app glyph for the About tab (not a template).
    static func aboutImage(size: CGFloat = 88) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width / 24.0
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            let path = NSBezierPath()
            path.move(to: p(12, 2.5))
            path.curve(to: p(4.8, 9.7),  controlPoint1: p(8, 2.5),    controlPoint2: p(4.8, 5.7))
            path.line(to: p(4.8, 18.9))
            path.curve(to: p(7, 19.8),   controlPoint1: p(4.8, 20),   controlPoint2: p(6.1, 20.6))
            path.line(to: p(8.2, 18.7))
            path.curve(to: p(9.7, 18.7), controlPoint1: p(8.6, 18.3), controlPoint2: p(9.3, 18.3))
            path.line(to: p(10.9, 19.8))
            path.curve(to: p(13.1, 19.8), controlPoint1: p(11.5, 20.4), controlPoint2: p(12.5, 20.4))
            path.line(to: p(14.3, 18.7))
            path.curve(to: p(15.8, 18.7), controlPoint1: p(14.7, 18.3), controlPoint2: p(15.4, 18.3))
            path.line(to: p(17, 19.8))
            path.curve(to: p(19.2, 18.9), controlPoint1: p(17.9, 20.6), controlPoint2: p(19.2, 20))
            path.line(to: p(19.2, 9.7))
            path.curve(to: p(12, 2.5),   controlPoint1: p(19.2, 5.7), controlPoint2: p(16, 2.5))
            path.close()
            let r: CGFloat = 1.35 * s
            path.appendOval(in: NSRect(x: 9.9 * s - r, y: 10.45 * s - r, width: 2 * r, height: 2 * r))
            path.appendOval(in: NSRect(x: 14.1 * s - r, y: 10.45 * s - r, width: 2 * r, height: 2 * r))
            path.windingRule = .evenOdd
            NSColor.white.setFill()
            path.fill()
            return true
        }
    }
}
