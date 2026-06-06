import Testing
import Foundation
@testable import ZFFEngine

// MARK: - Helpers

private func makeTempStore() -> (Store, () -> Void) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("IntegTests-\(UUID().uuidString)", isDirectory: true)
    let store = Store(fileURL: dir.appendingPathComponent("frecency.json"))
    return (store, { try? FileManager.default.removeItem(at: dir) })
}

private func makeTempRepoFixture() throws -> (home: String, repo: String, src: String, cleanup: () -> Void) {
    let fm = FileManager.default
    let home = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("zff-int-\(UUID().uuidString)")
    let repo = (home as NSString).appendingPathComponent("code/myrepo")
    let src = (repo as NSString).appendingPathComponent("src")
    try fm.createDirectory(atPath: (repo as NSString).appendingPathComponent(".git"),
                           withIntermediateDirectories: true)
    try fm.createDirectory(atPath: src, withIntermediateDirectories: true)
    return (home, repo, src, { try? fm.removeItem(atPath: home) })
}

// MARK: - AppState.rebuild() — store seed (criterion: appstate-rebuild-store-seed)

struct RebuildStoreSeedTests {

    @Test func storeOnlyPathAppearsInMergedResults() {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }

        let nonGitPath = "/tmp/a-folder-not-in-any-repo"
        store.record(path: URL(fileURLWithPath: nonGitPath), visitedAt: Date())

        // No discovered repos — path exists only in the store
        let results = store.mergePlaces(
            discovered: [],
            subfolderFrecency: false,
            minVisitCount: 3,
            repos: [],
            home: "/Users/testuser"
        )

        let paths = results.map(\.path)
        #expect(paths.contains(nonGitPath), "Store-only path must appear in rebuild output")
    }

    @Test func storeOnlyPathHasPositiveScore() {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }

        let path = "/tmp/stored-path-only"
        store.record(path: URL(fileURLWithPath: path), visitedAt: Date())

        let results = store.mergePlaces(
            discovered: [],
            subfolderFrecency: false,
            minVisitCount: 3,
            repos: [],
            home: "/Users/testuser"
        )

        let score = results.first(where: { $0.path == path })?.score ?? 0
        #expect(score > 0, "Store-seeded path must have a positive score")
    }
}

// MARK: - AppState.rebuild() — merge strategy (criterion: appstate-rebuild-merge-strategy)

struct RebuildMergeStrategyTests {

    @Test func storedVisitBoostIsObservable() {
        let (storeWithVisits, cleanup1) = makeTempStore()
        defer { cleanup1() }
        let (storeEmpty, cleanup2) = makeTempStore()
        defer { cleanup2() }

        let path = "/tmp/myrepo"
        let repos: Set<String> = [path]
        let home = "/tmp"
        let freshScore = 1.5
        let discovered = [Place(path: path, score: freshScore, sources: ["git"])]

        // 5 stored visits
        for _ in 0..<5 {
            storeWithVisits.record(path: URL(fileURLWithPath: path), visitedAt: Date())
        }

        let scoreWithVisits = storeWithVisits.mergePlaces(
            discovered: discovered,
            subfolderFrecency: false,
            minVisitCount: 3,
            repos: repos,
            home: home
        ).first(where: { $0.path == path })?.score ?? 0

        let scoreNoVisits = storeEmpty.mergePlaces(
            discovered: discovered,
            subfolderFrecency: false,
            minVisitCount: 3,
            repos: repos,
            home: home
        ).first(where: { $0.path == path })?.score ?? 0

        // storedVisitBoost = 5 × 0.1 = 0.5 — must be non-zero and observable
        #expect(scoreWithVisits > scoreNoVisits,
                "Place with 5 stored visits must rank strictly above same place with 0 stored visits")
    }

    @Test func combinedScoreUsesFreshScoreWhenHigher() {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }

        let path = "/tmp/high-fresh-score"
        let repos: Set<String> = [path]
        let home = "/tmp"
        // Very high fresh score — store only has 1 visit
        let discovered = [Place(path: path, score: 100.0, sources: ["git"])]
        store.record(path: URL(fileURLWithPath: path), visitedAt: Date())

        let result = store.mergePlaces(
            discovered: discovered,
            subfolderFrecency: false,
            minVisitCount: 3,
            repos: repos,
            home: home
        ).first(where: { $0.path == path })

        // combinedScore = max(storedScore, freshScore) + storedVisitBoost
        // max(small, 100.0) + 0.1 ≈ 100.1 — must be >= 100
        #expect((result?.score ?? 0) >= 100.0,
                "combinedScore must use max(stored, fresh) — high fresh score should dominate")
    }
}

// MARK: - AppState.rebuild() — subfolder frecency flag (criterion: appstate-subfolder-frecency-flag)

struct SubfolderFrecencyFlagTests {

    @Test func flagTrueKeepsSubfolderWhenAboveThreshold() throws {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }
        let (home, repo, src, cleanupFS) = try makeTempRepoFixture()
        defer { cleanupFS() }

        let repos: Set<String> = [repo]
        let minVisitCount = 3

        for _ in 0..<minVisitCount {
            store.record(path: URL(fileURLWithPath: src), visitedAt: Date())
        }

        let results = store.mergePlaces(
            discovered: [],
            subfolderFrecency: true,
            minVisitCount: minVisitCount,
            repos: repos,
            home: home
        )

        let paths = results.map(\.path)
        #expect(paths.contains(src),
                "subfolderFrecency=true must keep subfolder when visitCount >= minVisitCount")
    }

    @Test func flagFalseCollapsesSubfolderToGitRoot() throws {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }
        let (home, repo, src, cleanupFS) = try makeTempRepoFixture()
        defer { cleanupFS() }

        let repos: Set<String> = [repo]

        for _ in 0..<5 {
            store.record(path: URL(fileURLWithPath: src), visitedAt: Date())
        }

        let results = store.mergePlaces(
            discovered: [],
            subfolderFrecency: false,
            minVisitCount: 3,
            repos: repos,
            home: home
        )

        let paths = results.map(\.path)
        #expect(!paths.contains(src),
                "subfolderFrecency=false must collapse subfolder to git root")
        #expect(paths.contains(repo),
                "subfolderFrecency=false must produce git root in results")
    }

    @Test func flagProducesDifferentOutputsForSameFixture() throws {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }
        let (home, repo, src, cleanupFS) = try makeTempRepoFixture()
        defer { cleanupFS() }

        let repos: Set<String> = [repo]
        for _ in 0..<3 {
            store.record(path: URL(fileURLWithPath: src), visitedAt: Date())
        }

        let withSubfolder = store.mergePlaces(
            discovered: [], subfolderFrecency: true, minVisitCount: 3, repos: repos, home: home
        ).map(\.path)

        let withoutSubfolder = store.mergePlaces(
            discovered: [], subfolderFrecency: false, minVisitCount: 3, repos: repos, home: home
        ).map(\.path)

        #expect(withSubfolder != withoutSubfolder,
                "Different flag values must produce different ranked outputs for the same fixture")
    }
}

// MARK: - Integration: 3 visits → rebuild → subfolder ranks above git root (criterion: swift-test-green)

struct SubfolderRankingIntegrationTests {

    @Test func subfolderRanksAboveGitRootAfter3Visits() throws {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }
        let (home, repo, src, cleanupFS) = try makeTempRepoFixture()
        defer { cleanupFS() }

        let repos: Set<String> = [repo]
        let repoScore = 1.0
        let discovered = [Place(path: repo, score: repoScore, sources: ["git"])]

        let now = Date()
        for _ in 0..<3 {
            store.record(path: URL(fileURLWithPath: src), visitedAt: now)
        }

        let results = store.mergePlaces(
            discovered: discovered,
            subfolderFrecency: true,
            minVisitCount: 3,
            repos: repos,
            home: home
        )

        // Subfolder must appear
        guard let srcPlace = results.first(where: { $0.path == src }) else {
            Issue.record("src subfolder not found in results after 3 visits")
            return
        }

        // Subfolder's combined score must exceed the git root's base fresh score
        #expect(srcPlace.score > repoScore,
                "Subfolder with 3 visits must rank above git root with same freshness")
    }

    @Test func subfolderDoesNotRankAboveRootWhenBelowThreshold() throws {
        let (store, cleanup) = makeTempStore()
        defer { cleanup() }
        let (home, repo, src, cleanupFS) = try makeTempRepoFixture()
        defer { cleanupFS() }

        let repos: Set<String> = [repo]
        let discovered = [Place(path: repo, score: 5.0, sources: ["git"])]

        // Only 2 visits — below minVisitCount of 3
        for _ in 0..<2 {
            store.record(path: URL(fileURLWithPath: src), visitedAt: Date())
        }

        let results = store.mergePlaces(
            discovered: discovered,
            subfolderFrecency: true,
            minVisitCount: 3,
            repos: repos,
            home: home
        )

        let paths = results.map(\.path)
        // Below threshold: visits roll up to git root, subfolder should not appear separately
        #expect(!paths.contains(src),
                "Subfolder below visit threshold must not appear separately — rolls up to git root")
        #expect(paths.contains(repo), "Git root must appear when subfolder rolls up to it")
    }
}
