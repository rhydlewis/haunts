import SwiftUI
import Foundation

let HOME = NSHomeDirectory()
private let HALFLIFE_D = 30.0
private func decay(_ ageDays: Double) -> Double { pow(0.5, max(0, ageDays) / HALFLIFE_D) }
private func ageDays(since ts: Double) -> Double { (Date().timeIntervalSince1970 - ts) / 86400 }

enum OpenMode { case finder, editor, terminal }

struct Place: Identifiable {
    let path: String
    var score: Double
    var sources: Set<String>
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var display: String { path.hasPrefix(HOME) ? "~" + path.dropFirst(HOME.count) : path }
    var isRepo: Bool { sources.contains("git") }
}

/// The frecency engine (ports Spike 2 ranking + a git-repo warm seed) plus the
/// palette's UI state. Index is built once at launch and kept cached; typing
/// filters the cached list locally so it stays instant.
@MainActor
final class AppState: ObservableObject {
    @Published var query = ""
    @Published var index: [Place] = []       // full ranked list (sorted)
    @Published var selection = 0
    @Published var focusPing = 0             // bump to refocus the search field

    private var repos: Set<String> = []
    private var rootCache: [String: String] = [:]
    private var metaQuery: NSMetadataQuery?

    // MARK: ranking / filtering
    /// Stable order: score desc, then path asc — ties never shuffle between
    /// renders (the shuffling was what opened the wrong folder).
    private static func rankOrder(_ a: Place, _ b: Place) -> Bool {
        a.score != b.score ? a.score > b.score : a.path < b.path
    }

    /// Lowercase and strip separators so `z for` matches `z-for-finder`.
    private func norm(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    private func isSubseq(_ q: String, _ s: String) -> Bool {
        var i = q.startIndex
        for c in s where i < q.endIndex && c == q[i] { i = q.index(after: i) }
        return i == q.endIndex
    }
    private func matchScore(_ q: String, _ p: Place) -> Double {
        let n = norm(p.name)
        var bonus = 0.0
        if n.hasPrefix(q) { bonus += 3 } else if n.contains(q) { bonus += 1.5 }
        return bonus + p.score
    }

    /// PURE computed view of index+query — always fresh during render (no stale
    /// results), deterministic (stable tiebreak) so display == what opens.
    /// Matches the folder NAME only; path is used just to break ties.
    var results: [Place] {
        let q = norm(query)
        guard !q.isEmpty else { return Array(index.prefix(9)) }
        return index
            .filter { isSubseq(q, norm($0.name)) }
            .sorted { matchScore(q, $0) != matchScore(q, $1)
                      ? matchScore(q, $0) > matchScore(q, $1)
                      : $0.path < $1.path }
            .prefix(9).map { $0 }
    }

    // MARK: lifecycle of a summon
    func prepareForShow() {
        query = ""
        selection = 0
        focusPing &+= 1
    }
    func move(_ delta: Int) {
        let n = results.count
        guard n > 0 else { return }
        selection = min(max(0, selection + delta), n - 1)
    }
    func activate(_ mode: OpenMode) {
        guard results.indices.contains(selection) else { return }
        open(results[selection].path, mode)
    }

    // MARK: index build
    func rebuild() {
        var seed: [String: Place] = [:]
        repos = discoverRepos()
        for repo in repos {
            let mt = gitActivity(repo)
            bump(&seed, repo, "git", decay(ageDays(since: mt)))
        }
        index = seed.values.sorted(by: Self.rankOrder)   // warm immediately from git
        runMetadata(seed: seed)                          // then enrich with Spotlight signal
    }

    private func bump(_ map: inout [String: Place], _ path: String, _ source: String, _ w: Double) {
        if var pl = map[path] { pl.score += w; pl.sources.insert(source); map[path] = pl }
        else { map[path] = Place(path: path, score: w, sources: [source]) }
    }

    private func discoverRepos() -> Set<String> {
        var found: Set<String> = []
        let fm = FileManager.default
        func scan(_ root: String, _ maxDepth: Int) {
            guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else { return }
            for case let url as URL in en {
                if en.level > maxDepth { en.skipDescendants(); continue }
                let p = url.path
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true { continue }
                if ["node_modules", "Library", "Pictures", "Movies"].contains(url.lastPathComponent) {
                    en.skipDescendants(); continue
                }
                if fm.fileExists(atPath: p + "/.git") { found.insert(p); en.skipDescendants() }
            }
        }
        scan(HOME + "/code", 4)
        scan(HOME, 2)
        return found
    }

    private func gitActivity(_ repo: String) -> Double {
        let fm = FileManager.default
        let candidates = ["/.git/HEAD", "/.git/index"].map { repo + $0 }
        let mtimes = candidates.compactMap { (try? fm.attributesOfItem(atPath: $0)[.modificationDate]) as? Date }
        return (mtimes.max() ?? Date(timeIntervalSince1970: 0)).timeIntervalSince1970
    }

    private func gitRoot(_ dir: String) -> String {
        if let c = rootCache[dir] { return c }
        var cur = dir
        var root = dir
        while cur.hasPrefix(HOME) && cur != HOME && cur != "/" {
            if repos.contains(cur) { root = cur; break }
            cur = (cur as NSString).deletingLastPathComponent
        }
        rootCache[dir] = root
        return root
    }

    private func isTransient(_ path: String) -> Bool {
        ["/Downloads", "/Desktop", "/Screenshots"].contains { path.hasPrefix(HOME + $0) }
    }

    private func runMetadata(seed: [String: Place]) {
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@",
                                  Date(timeIntervalSinceNow: -90 * 86400) as NSDate)
        q.searchScopes = [HOME]
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            // Delivered on the main queue, so it is safe to hop onto the actor.
            MainActor.assumeIsolated {
                guard let self else { return }
                q.disableUpdates()
                var map = seed
                let now = Date()
                for i in 0..<q.resultCount {
                    guard let it = q.result(at: i) as? NSMetadataItem,
                          let p = it.value(forAttribute: NSMetadataItemPathKey) as? String,
                          !p.contains("/Library/"), !p.contains("/.") else { continue }
                    let dir = (p as NSString).deletingLastPathComponent
                    if dir.isEmpty || dir == HOME { continue }
                    let last = it.value(forAttribute: "kMDItemLastUsedDate") as? Date
                    let age = last.map { max(0, now.timeIntervalSince($0) / 86400) } ?? 90
                    let use = (it.value(forAttribute: "kMDItemUseCount") as? NSNumber)?.doubleValue ?? 1
                    var w = pow(0.5, age / HALFLIFE_D) * sqrt(use)
                    let root = self.gitRoot(dir)
                    if self.isTransient(root) { w *= 0.08 }
                    self.bump(&map, root, "meta", w)
                }
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                self.index = map.values.sorted(by: Self.rankOrder)
            }
        }
        metaQuery = q
        q.start()
    }

    // MARK: open
    private func open(_ path: String, _ mode: OpenMode) {
        switch mode {
        case .finder:
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .editor:
            run(["-a", "Sublime Text", path])
        case .terminal:
            run(["-a", "Terminal", path])
        }
    }
    private func run(_ args: [String]) {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = args
        try? t.run()
    }
}
