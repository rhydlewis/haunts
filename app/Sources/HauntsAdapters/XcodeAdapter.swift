import Foundation

/// Reads Xcode's recent documents from IDERecentDocuments.plist.
/// Returns parent directories of resolved file paths that still exist on disk.
/// Returns [] — never throws — when the plist is absent, unreadable, or malformed.
public struct XcodeAdapter: EditorAdapter {
    public var editorName: String { "Xcode" }

    /// Injectable for testing; defaults to the real Xcode recents plist path.
    public let plistURL: URL

    public init(plistURL: URL? = nil) {
        self.plistURL = plistURL ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(
                "Library/Application Support/com.apple.dt.Xcode/UserData/IDERecentDocuments.plist"
            )
    }

    public func recentFolders() throws -> [URL] {
        guard let data = try? Data(contentsOf: plistURL) else { return [] }
        guard let array = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [[String: Any]] else { return [] }

        let fm = FileManager.default
        var folders: Set<String> = []

        for dict in array {
            if let bookmarkData = dict["_bookmark"] as? Data {
                var isStale = false
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withoutUI,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    let parent = folderOf(resolved, fm: fm)
                    if fm.fileExists(atPath: parent.path) { folders.insert(parent.path) }
                }
            } else if let path = (dict["Path"] as? String) ?? (dict["_location"] as? String) {
                let url = URL(fileURLWithPath: path)
                let parent = folderOf(url, fm: fm)
                if fm.fileExists(atPath: parent.path) { folders.insert(parent.path) }
            }
        }

        return folders.map { URL(fileURLWithPath: $0) }
    }

    private func folderOf(_ url: URL, fm: FileManager) -> URL {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}
