import Foundation

/// A ranked filesystem location. Pure value type: no AppKit / SwiftUI / metadata.
/// `score` accumulates frecency weight from one or more `sources` (e.g. "git", "meta").
public struct Place: Identifiable, Equatable, Sendable {
    public let path: String
    public var score: Double
    public var sources: Set<String>

    public init(path: String, score: Double, sources: Set<String>) {
        self.path = path
        self.score = score
        self.sources = sources
    }

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var isRepo: Bool { sources.contains("git") }

    /// Cosmetic home-relative path for display.
    public var display: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
