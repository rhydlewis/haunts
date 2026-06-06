import Foundation

/// Reads Zed's recent directories from ~/.config/zed/settings.json.
/// Returns [] — never throws — when the file is absent or malformed.
public struct ZedAdapter: EditorAdapter {
    public var editorName: String { "Zed" }

    /// Injectable for testing; defaults to the real Zed settings path.
    public let configURL: URL

    public init(configURL: URL? = nil) {
        self.configURL = configURL ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/zed/settings.json")
    }

    public func recentFolders() throws -> [URL] {
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dirs = json["recent_dirs"] as? [String],
              !dirs.isEmpty else { return [] }
        return dirs.map { path in
            let expanded = path.hasPrefix("~")
                ? NSHomeDirectory() + path.dropFirst()
                : path
            return URL(fileURLWithPath: expanded)
        }
    }
}
