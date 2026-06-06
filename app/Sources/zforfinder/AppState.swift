import SwiftUI
import Foundation
import ZFFEngine
import HauntsAdapters

let HOME = NSHomeDirectory()

enum OpenMode { case finder, editor, terminal }

/// The frecency engine (ports Spike 2 ranking + a git-repo warm seed) plus the
/// palette's UI state. Pure ranking/scoring lives in `ZFFEngine`; this shell owns
/// the @Published state and the impure adapters (git scan, Spotlight, open).
/// Index is built once at launch and kept cached; typing filters locally so it stays instant.
@MainActor
final class AppState: ObservableObject {
    @Published var query = ""
    @Published var index: [Place] = []       // full ranked list (sorted)
    @Published var selection = 0
    @Published var focusPing = 0             // bump to refocus the search field

    private var repos: Set<String> = []
    private var rootCache: [String: String] = [:]
    private var metaQuery: NSMetadataQuery?

    // Persistence + signal sources (Session 2). Store is empty until live navigation
    // (FinderTracker) populates it, so this wiring is plumbing — no ranking change yet.
    private let store = Store.defaultStore()
    private let editorAdapters: [EditorAdapter] = [ZedAdapter(), XcodeAdapter(), PyCharmAdapter()]
    /// Index-build blend. Balanced is the shipped default; a future Preferences toggle
    /// can expose Frequent (z-style). See `RankingMode`.
    private let rankingMode: RankingMode = .default

    /// PURE computed view of index+query — always fresh during render (no stale
    /// results), deterministic (stable tiebreak) so display == what opens.
    /// Matches the folder NAME only; path is used just to break ties.
    var results: [Place] {
        Ranker.rank(query: query, over: index)
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
        let now = Date().timeIntervalSince1970
        for repo in repos {
            let mt = gitActivity(repo)
            bump(&seed, repo, "git", Scoring.decay(Scoring.ageDays(since: mt, now: now)))
        }
        // Editor recent-folders signal (Zed/Xcode/PyCharm), rolled up to git roots.
        for adapter in editorAdapters {
            guard let folders = try? adapter.recentFolders() else { continue }
            for url in folders { bump(&seed, gitRoot(url.path), "editor", 0.5) }
        }
        let records = store.load()
        // warm immediately: git+editor blended with any persisted visits (empty for now)
        index = Frecency.blend(discovered: Array(seed.values), records: records,
                               mode: rankingMode, repos: repos, home: HOME)
        runMetadata(seed: seed, records: records)          // then enrich with Spotlight signal
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

    /// Memoized roll-up of a path to its git root (pure walk lives in `Rollup`).
    private func gitRoot(_ dir: String) -> String {
        if let c = rootCache[dir] { return c }
        let root = Rollup.gitRoot(dir, repos: repos, home: HOME)
        rootCache[dir] = root
        return root
    }

    private func runMetadata(seed: [String: Place], records: [PlaceRecord]) {
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
                    var w = Scoring.metaWeight(ageDays: age, useCount: use)
                    let root = self.gitRoot(dir)
                    if Rollup.isTransient(root, home: HOME) { w *= Scoring.transientMultiplier }
                    self.bump(&map, root, "meta", w)
                }
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                self.index = Frecency.blend(discovered: Array(map.values), records: records,
                                            mode: self.rankingMode, repos: self.repos, home: HOME)
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
