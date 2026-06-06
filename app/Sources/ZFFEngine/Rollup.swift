import Foundation

/// Path roll-up + classification. Pure: the repo-set and home dir are injected,
/// so tests use temp-dir fixtures with no real git.
public enum Rollup {
    /// Walk up from `dir` toward `home`; the first ancestor in `repos` is the git
    /// root that `dir` rolls up to. If none is found, `dir` stays where it is.
    public static func gitRoot(_ dir: String, repos: Set<String>, home: String) -> String {
        var cur = dir
        while cur.hasPrefix(home) && cur != home && cur != "/" {
            if repos.contains(cur) { return cur }
            cur = (cur as NSString).deletingLastPathComponent
        }
        return dir
    }

    /// Is `path` under a transient bucket (Downloads/Desktop/Screenshots)?
    public static func isTransient(_ path: String, home: String) -> Bool {
        ["/Downloads", "/Desktop", "/Screenshots"].contains { path.hasPrefix(home + $0) }
    }

    /// Return the subfolder URL unchanged when `visitCount >= minVisitCount`;
    /// otherwise fall back to the git root (or the URL itself when no git ancestor exists).
    ///
    /// - Parameters:
    ///   - url: The candidate subfolder path.
    ///   - repos: Set of known git-root paths (injected for testability).
    ///   - home: Home directory string (injected for testability).
    ///   - minVisitCount: Minimum stored visits to keep the subfolder.
    ///   - visitCount: Total recorded visits for `url.path` (computed from the Store by the caller).
    public static func keepSubfolder(
        _ url: URL,
        repos: Set<String>,
        home: String,
        minVisitCount: Int,
        visitCount: Int
    ) -> URL {
        guard visitCount >= minVisitCount else {
            let root = gitRoot(url.path, repos: repos, home: home)
            return URL(fileURLWithPath: root)
        }
        return url
    }
}
