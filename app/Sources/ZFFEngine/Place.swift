import Foundation

/// A ranked filesystem location. Pure value type: no AppKit / SwiftUI / metadata.
/// `score` accumulates frecency weight from one or more `sources` (e.g. "git", "meta").
/// The three component fields capture individual scoring contributions for debug display.
public struct Place: Identifiable, Equatable, Sendable {
    public let path: String
    public var score: Double
    public var sources: Set<String>
    /// Time-decay contribution from git activity or store recency.
    public var decayComponent: Double
    /// Raw visit count from the frecency store.
    public var useComponent: Double
    /// Spotlight metadata weight contribution.
    public var metaComponent: Double

    public init(
        path: String,
        score: Double,
        sources: Set<String>,
        decayComponent: Double = 0,
        useComponent: Double = 0,
        metaComponent: Double = 0
    ) {
        self.path = path
        self.score = score
        self.sources = sources
        self.decayComponent = decayComponent
        self.useComponent = useComponent
        self.metaComponent = metaComponent
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
