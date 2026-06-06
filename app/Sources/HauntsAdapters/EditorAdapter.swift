import Foundation

/// Contract for editor-specific frecency signal sources.
/// Each adapter reads its editor's recent-folders list and returns them as file URLs.
public protocol EditorAdapter {
    var editorName: String { get }
    func recentFolders() throws -> [URL]
}
