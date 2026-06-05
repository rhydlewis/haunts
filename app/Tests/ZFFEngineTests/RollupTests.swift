import Testing
import Foundation
@testable import ZFFEngine

struct RollupTests {

    /// Build a temp "home" with a real repo (has .git) and a loose non-repo dir.
    /// Returns (home, repos) mirroring what the app's discoverRepos would produce.
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

        // Mimic discoverRepos: a dir is a repo iff it contains a .git child.
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
        // 4 uses -> sqrt(4) = 2x the weight of a single use at the same age.
        let one = Scoring.metaWeight(ageDays: 10, useCount: 1)
        let four = Scoring.metaWeight(ageDays: 10, useCount: 4)
        #expect(abs(four / one - 2.0) < 1e-9)
    }
}
