import Testing
import Foundation
@testable import ZFFEngine

struct RollupTests {

    /// Build a temp "home" with a real repo (has .git) and a loose non-repo dir.
    private func makeFixture() throws -> (home: String, repos: Set<String>, cleanup: () -> Void) {
        let fm = FileManager.default
        let home = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("zff-fixture-\(UUID().uuidString)")
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let deep = (repo as NSString).appendingPathComponent("src/feature/impl")
        let loose = (home as NSString).appendingPathComponent("notes/scratch")
        try fm.createDirectory(atPath: (repo as NSString).appendingPathComponent(".git"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(atPath: deep, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: loose, withIntermediateDirectories: true)

        var repos: Set<String> = []
        if fm.fileExists(atPath: (repo as NSString).appendingPathComponent(".git")) {
            repos.insert(repo)
        }
        return (home, repos, { try? fm.removeItem(atPath: home) })
    }

    // A file deep inside a repo rolls up to the .git root.
    @Test func deepFileRollsUpToRepoRoot() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let deepDir = (repo as NSString).appendingPathComponent("src/feature/impl")

        #expect(Rollup.gitRoot(deepDir, repos: repos, home: home) == repo)
    }

    // A non-repo path stays at its parent (no ancestor is a repo).
    @Test func nonRepoPathStaysPut() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let loose = (home as NSString).appendingPathComponent("notes/scratch")

        #expect(Rollup.gitRoot(loose, repos: repos, home: home) == loose)
    }

    @Test func transientClassification() {
        let home = "/Users/x"
        #expect(Rollup.isTransient("/Users/x/Downloads/a.pdf", home: home))
        #expect(Rollup.isTransient("/Users/x/Desktop/shot.png", home: home))
        #expect(!Rollup.isTransient("/Users/x/code/myrepo", home: home))
    }

    // MARK: - keepSubfolder tests

    @Test func keepSubfolderAboveThresholdReturnsSelf() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let src = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src"))

        // visitCount >= minVisitCount → returns input unchanged
        let result = Rollup.keepSubfolder(src, repos: repos, home: home, minVisitCount: 3, visitCount: 3)
        #expect(result.path == src.path)
    }

    @Test func keepSubfolderExactlyAtThresholdReturnsSelf() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let src = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src"))

        // visitCount == minVisitCount exactly → must return subfolder, not git root
        let result = Rollup.keepSubfolder(src, repos: repos, home: home, minVisitCount: 5, visitCount: 5)
        #expect(result.path == src.path)
    }

    @Test func keepSubfolderAboveHigherThreshold() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let src = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src"))

        // 10 visits >> minVisitCount of 3
        let result = Rollup.keepSubfolder(src, repos: repos, home: home, minVisitCount: 3, visitCount: 10)
        #expect(result.path == src.path)
    }

    @Test func keepSubfolderBelowThresholdFallsBackToGitRoot() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let src = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src"))

        // visitCount < minVisitCount → returns git root
        let result = Rollup.keepSubfolder(src, repos: repos, home: home, minVisitCount: 3, visitCount: 2)
        #expect(result.path == repo)
    }

    @Test func keepSubfolderZeroVisitsFallsBackToGitRoot() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let src = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src"))

        let result = Rollup.keepSubfolder(src, repos: repos, home: home, minVisitCount: 3, visitCount: 0)
        #expect(result.path == repo)
    }

    @Test func keepSubfolderNoGitAncestorReturnsSelf() {
        // A path with no git ancestor falls back to itself (not to some random parent)
        let home = "/Users/testuser"
        let repos: Set<String> = []
        let url = URL(fileURLWithPath: "/Users/testuser/notes/scratch")

        // Below threshold but no git root → returns the URL itself
        let result = Rollup.keepSubfolder(url, repos: repos, home: home, minVisitCount: 3, visitCount: 0)
        #expect(result.path == url.path)
    }

    @Test func keepSubfolderDeepSubfolderAboveThreshold() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let deep = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src/feature/impl"))

        // Deep path with enough visits → kept as-is
        let result = Rollup.keepSubfolder(deep, repos: repos, home: home, minVisitCount: 3, visitCount: 3)
        #expect(result.path == deep.path)
    }

    @Test func keepSubfolderDeepSubfolderBelowThreshold() throws {
        let (home, repos, cleanup) = try makeFixture()
        defer { cleanup() }
        let repo = (home as NSString).appendingPathComponent("code/myrepo")
        let deep = URL(fileURLWithPath: (repo as NSString).appendingPathComponent("src/feature/impl"))

        // Deep path below threshold → collapses to git root
        let result = Rollup.keepSubfolder(deep, repos: repos, home: home, minVisitCount: 3, visitCount: 1)
        #expect(result.path == repo)
    }
}

struct ScoringTests {

    // A transient path scores ~0.08x an equivalent non-transient path.
    @Test func transientDownWeight() {
        let age = 3.0, use = 4.0
        let base = Scoring.metaWeight(ageDays: age, useCount: use)
        let transient = base * Scoring.transientMultiplier
        #expect(abs(transient / base - 0.08) < 1e-9)
    }

    @Test func decayHalfLife() {
        #expect(abs(Scoring.decay(0) - 1.0) < 1e-9)
        #expect(abs(Scoring.decay(Scoring.halfLifeDays) - 0.5) < 1e-9)
        #expect(abs(Scoring.decay(-5) - 1.0) < 1e-9)   // negative age clamps to 0 -> 1.0
    }

    @Test func useCountBoost() {
        let one = Scoring.metaWeight(ageDays: 10, useCount: 1)
        let four = Scoring.metaWeight(ageDays: 10, useCount: 4)
        #expect(abs(four / one - 2.0) < 1e-9)
    }
}
