import SwiftUI
import Foundation
import ZFFEngine
import HauntsAdapters

let HOME = NSHomeDirectory()

public enum OpenMode: Sendable { case finder, editor, terminal }

/// App state + index assembly. Pure ranking/scoring lives in `ZFFEngine`; this
/// owns the @Published palette state and the impure adapters (git scan, Spotlight,
/// editor recents, navigation persistence, open). Extracted into `HauntsCore` so
/// it is unit-testable (the executable target cannot be imported by tests).
@MainActor
public final class AppState: ObservableObject {
    @Published public var query = ""
    @Published public var index: [Place] = []     // full ranked list (sorted)
    @Published public var selection = 0
    @Published public var focusPing = 0            // bump to refocus the search field

    private var repos: Set<String> = []
    private var rootCache: [String: String] = [:]
    private var metaQuery: NSMetadataQuery?
    private var lastDiscovered: [Place] = []       // cached scan result for live re-blend

    private let store: Store
    private let editorAdapters: [EditorAdapter]

    /// Index-build blend, read live from `Settings` so the Ranking tab can change it.
    /// Balanced is the shipped default; Preferences exposes Balanced/Frequent.
    private var rankingMode: RankingMode {
        RankingMode(rawValue: Settings.rankingMode) ?? .default
    }
    private var subfolderFrecency: Bool { Settings.subfolderFrecency }
    private var minVisitCount: Int { Settings.minVisitCount }

    public init(
        store: Store = .defaultStore(),
        adapters: [EditorAdapter] = [ZedAdapter(), XcodeAdapter(), PyCharmAdapter()]
    ) {
        self.store = store
        self.editorAdapters = adapters
    }

    /// PURE computed view of index+query — always fresh during render, deterministic.
    public var results: [Place] {
        Ranker.rank(query: query, over: index)
    }

    // MARK: lifecycle of a summon
    public func prepareForShow() {
        query = ""
        selection = 0
        focusPing &+= 1
    }
    public func move(_ delta: Int) {
        let n = results.count
        guard n > 0 else { return }
        selection = min(max(0, selection + delta), n - 1)
    }
    public func activate(_ mode: OpenMode) {
        guard results.indices.contains(selection) else { return }
        open(results[selection].path, mode)
    }

    // MARK: index build
    public func rebuild() {
        var seed: [String: Place] = [:]
        repos = discoverRepos()
        let now = Date().timeIntervalSince1970
        for repo in repos {
            let mt = gitActivity(repo)
            bump(&seed, repo, "git", Scoring.decay(Scoring.ageDays(since: mt, now: now)))
        }
        // Editor recent-folders signal (configured adapters), rolled up to git roots.
        for adapter in editorAdapters {
            guard let folders = try? adapter.recentFolders() else { continue }
            for url in folders { bump(&seed, gitRoot(url.path), "editor", 0.5) }
        }
        lastDiscovered = Array(seed.values)
        index = Frecency.blend(discovered: lastDiscovered, records: store.load(),
                               mode: rankingMode, subfolderFrecency: subfolderFrecency,
                               minVisitCount: minVisitCount, repos: repos, home: HOME)
        runMetadata(seed: seed)                            // then enrich with Spotlight signal
    }

    /// Record a live navigation visit and re-blend immediately (used by FinderTracker).
    public func trackNavigation(path: URL) {
        store.record(path: path)
        reblend()
    }
    private func reblend() {
        index = Frecency.blend(discovered: lastDiscovered, records: store.load(),
                               mode: rankingMode, subfolderFrecency: subfolderFrecency,
                               minVisitCount: minVisitCount, repos: repos, home: HOME)
    }

    /// Re-apply ranking settings (mode / subfolder / min-visit) without rescanning
    /// the disk — used after a Preferences change.
    public func applyRankingSettings() { reblend() }

    /// Forget every recorded visit, then re-blend so the change is immediate.
    /// Backs "Reset Learned Data…" in Preferences.
    public func resetLearnedData() {
        store.reset()
        reblend()
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
        for root in Settings.scanRoots { scan(root.path, root.depth) }   // configurable scan roots
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
                    var w = Scoring.metaWeight(ageDays: age, useCount: use)
                    let root = self.gitRoot(dir)
                    if Rollup.isTransient(root, home: HOME) { w *= Scoring.transientMultiplier }
                    self.bump(&map, root, "meta", w)
                }
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                self.lastDiscovered = Array(map.values)
                self.reblend()
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
            if let ed = Settings.editorTargetsOrDefault().first(where: { $0.isEnabled }) {
                run(["-b", ed.bundleID, path])          // open folder in the configured editor
            } else {
                run(["-a", "Sublime Text", path])       // fallback when nothing detected
            }
        case .terminal:
            run(["-a", Settings.terminalTarget, path])
        }
    }
    private func run(_ args: [String]) {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = args
        try? t.run()
    }
}
