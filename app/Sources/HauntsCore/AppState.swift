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
    private var lastDiscovered: [Place] = []       // warm-seeded scan result for live re-blend
    /// folder → (source name → summed raw weight); fed to `WarmSeed.blend`.
    private var sourceWeights: [String: [String: Double]] = [:]

    private let store: Store
    private let editorAdapters: [EditorAdapter]
    private let shellHistory: ShellHistorySource

    /// Index-build blend, read live from `Settings` so the Ranking tab can change it.
    /// Balanced is the shipped default; Preferences exposes Balanced/Frequent.
    private var rankingMode: RankingMode {
        RankingMode(rawValue: Settings.rankingMode) ?? .default
    }
    private var subfolderFrecency: Bool { Settings.subfolderFrecency }
    private var minVisitCount: Int { Settings.minVisitCount }

    public init(
        store: Store = .defaultStore(),
        adapters: [EditorAdapter] = [ZedAdapter(), XcodeAdapter(), PyCharmAdapter()],
        shellHistory: ShellHistorySource = ShellHistorySource()
    ) {
        self.store = store
        self.editorAdapters = adapters
        self.shellHistory = shellHistory
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
    /// Build the DAY-ONE warm index from signals that already exist on the machine —
    /// git repos, shell history, IDE recents, Spotlight metadata — blended by
    /// `WarmSeed` (per-source normalization + diversity), then layered with any
    /// persisted visit history. Correct on first launch, before any navigation.
    public func rebuild() {
        sourceWeights = [:]
        rootCache = [:]
        repos = discoverRepos()
        let now = Date().timeIntervalSince1970

        // git: weight each repo by recency of .git activity.
        for repo in repos {
            let mt = gitActivity(repo)
            addWeight(repo, "git", Scoring.decay(Scoring.ageDays(since: mt, now: now)))
        }
        // editor recent-folders (configured adapters), rolled up to git roots.
        for adapter in editorAdapters {
            guard let folders = try? adapter.recentFolders() else { continue }
            for url in folders { addWeight(gitRoot(url.path), "editor", 0.5) }
        }
        // shell history: cd/path targets → counts, resolved to dirs and rolled up.
        for (raw, count) in shellHistory.paths(home: HOME) {
            guard let folder = resolveFolder(raw) else { continue }
            addWeight(gitRoot(folder), "shell", Double(count))
        }

        warmSeedAndBlend()      // synchronous warm index from git+shell+editor…
        runMetadata()           // …then enrich asynchronously with the Spotlight signal
    }

    /// Recompute `lastDiscovered` from `sourceWeights` via the warm-seed blend, then
    /// layer in visit history. Called on rebuild and whenever a source updates (meta).
    private func warmSeedAndBlend() {
        lastDiscovered = WarmSeed.blend(sources: sourceWeights, home: HOME)
        reblend()
        dumpIndexIfRequested()
    }

    /// Diagnostic: when `HAUNTS_DUMP_INDEX` is set, log the top of the live index so
    /// the day-one warm list can be inspected without a screenshot. No-op otherwise.
    private func dumpIndexIfRequested() {
        guard ProcessInfo.processInfo.environment["HAUNTS_DUMP_INDEX"] != nil else { return }
        let lines = index.prefix(20).enumerated().map { i, p in
            String(format: "  %2d  %6.2f  [%@]  %@", i + 1, p.score,
                   p.sources.sorted().joined(separator: ","), p.display)
        }
        NSLog("Haunts WARM INDEX (\(index.count) folders):\n" + lines.joined(separator: "\n"))
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

    /// Forget a single learned folder: drop its visit records from the store AND
    /// remove it from the in-memory discovered set so the palette row vanishes now,
    /// even when a scan source (git/shell/meta) also surfaced it. A later full
    /// rebuild may re-learn it — this is delete, not a permanent denylist.
    public func forget(path: String) {
        store.forget(path: path)
        lastDiscovered.removeAll { $0.path == path }
        sourceWeights[path] = nil
        reblend()
        let n = results.count
        if selection >= n { selection = max(0, n - 1) }
    }

    private func addWeight(_ folder: String, _ source: String, _ w: Double) {
        sourceWeights[folder, default: [:]][source, default: 0] += w
    }

    /// Resolve a raw shell-history path to a real directory under `HOME`, or nil to
    /// skip it: expand to a directory (files fall back to their parent), reject
    /// anything outside home, the home root itself, Library, and hidden components.
    private func resolveFolder(_ raw: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: raw, isDirectory: &isDir) else { return nil }
        let dir = isDir.boolValue ? raw : (raw as NSString).deletingLastPathComponent
        let std = (dir as NSString).standardizingPath
        guard std.hasPrefix(HOME), std != HOME else { return nil }
        if std.contains("/Library/") || std.contains("/.") { return nil }
        return std
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

    private func runMetadata() {
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
                    // Raw meta weight; WarmSeed normalizes within the source and applies
                    // the transient penalty uniformly, so no pre-penalty here.
                    let w = Scoring.metaWeight(ageDays: age, useCount: use)
                    self.addWeight(self.gitRoot(dir), "meta", w)
                }
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                self.warmSeedAndBlend()
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
