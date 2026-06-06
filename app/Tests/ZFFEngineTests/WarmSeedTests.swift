import Testing
import Foundation
@testable import ZFFEngine

struct WarmSeedTests {
    let home = "/Users/x"

    private func rank(_ sources: [String: [String: Double]]) -> [String] {
        WarmSeed.blend(sources: sources, home: home).map(\.path)
    }

    // All-empty input is stable: no crash, empty output.
    @Test func emptyIsStable() {
        #expect(WarmSeed.blend(sources: [:], home: home).isEmpty)
    }

    // A single source with one enormous raw weight is normalized to 1.0 and CANNOT
    // dominate a folder that two independent sources agree on. This is the whole
    // point: the old raw-sum blend would put the 1000-weight folder on top.
    @Test func highVolumeSingleSourceDoesNotDominate() {
        let sources: [String: [String: Double]] = [
            "/Users/x/spammy":  ["shell": 1000.0],            // one giant source
            "/Users/x/agreed":  ["git": 0.3, "meta": 0.2],    // two modest sources
        ]
        let order = rank(sources)
        #expect(order.first == "/Users/x/agreed",
                "multi-source agreement must beat a single high-volume source")
        // And the giant raw weight is capped: its normalized score is ~1.0, not 1000.
        let spammy = WarmSeed.blend(sources: sources, home: home).first { $0.path == "/Users/x/spammy" }!
        #expect(spammy.score <= 1.0 + 1e-9)
    }

    // Two folders, equal single-source strength, but one is confirmed by a 2nd source:
    // the multi-source folder ranks higher purely on the diversity bonus.
    @Test func multiSourceLiftsAboveSingleSource() {
        let sources: [String: [String: Double]] = [
            "/Users/x/solo":  ["git": 1.0],
            "/Users/x/multi": ["git": 1.0, "shell": 1.0],
        ]
        let blended = WarmSeed.blend(sources: sources, home: home)
        let solo = blended.first { $0.path == "/Users/x/solo" }!
        let multi = blended.first { $0.path == "/Users/x/multi" }!
        #expect(multi.score > solo.score)
        #expect(rank(sources).first == "/Users/x/multi")
    }

    // The diversity bonus grows with distinct-source count (monotonic).
    @Test func diversityBonusIsMonotonicInSourceCount() {
        let sources: [String: [String: Double]] = [
            "/Users/x/one":   ["git": 1.0],
            "/Users/x/two":   ["git": 1.0, "shell": 1.0],
            "/Users/x/three": ["git": 1.0, "shell": 1.0, "meta": 1.0],
        ]
        let b = WarmSeed.blend(sources: sources, home: home)
        let s1 = b.first { $0.path == "/Users/x/one" }!.score
        let s2 = b.first { $0.path == "/Users/x/two" }!.score
        let s3 = b.first { $0.path == "/Users/x/three" }!.score
        // Each extra source adds its normalized contribution (1.0 here) PLUS the
        // diversity bonus, so each step rises by exactly 1.0 + bonus — strictly monotonic.
        #expect(s2 - s1 == 1.0 + WarmSeed.diversityBonus)
        #expect(s3 - s2 == 1.0 + WarmSeed.diversityBonus)
        #expect(s1 < s2 && s2 < s3)
    }

    // Per-source trust scales a source's contribution; a low-trust source contributes less.
    @Test func trustScalesContribution() {
        let sources: [String: [String: Double]] = [
            "/Users/x/trusted":   ["git": 1.0],
            "/Users/x/untrusted": ["sublime": 1.0],
        ]
        let trust = ["git": 1.0, "sublime": 0.5]
        let b = WarmSeed.blend(sources: sources, trust: trust, home: home)
        #expect(b.first?.path == "/Users/x/trusted")
        #expect(b.first { $0.path == "/Users/x/untrusted" }!.score == 0.5)
    }

    // Transient folders (Downloads/Desktop/Screenshots) are heavily down-weighted,
    // so even a strongly-voted Downloads sinks below a modest real project.
    @Test func transientFolderIsDownWeighted() {
        let sources: [String: [String: Double]] = [
            "/Users/x/Downloads": ["git": 1.0, "shell": 1.0, "meta": 1.0],
            "/Users/x/realproj":  ["git": 0.5],
        ]
        let b = WarmSeed.blend(sources: sources, home: home)
        #expect(b.first?.path == "/Users/x/realproj",
                "a transient bucket must not outrank a real project even with more sources")
        let dl = b.first { $0.path == "/Users/x/Downloads" }!
        #expect(dl.score < 0.5)   // (2.0 + 0.30) * 0.08 ≈ 0.184
    }

    // Deterministic tiebreak: equal scores order by path ascending (matches Ranker).
    @Test func tiesBreakByPathAscending() {
        let sources: [String: [String: Double]] = [
            "/Users/x/bbb": ["git": 1.0],
            "/Users/x/aaa": ["git": 1.0],
        ]
        #expect(rank(sources) == ["/Users/x/aaa", "/Users/x/bbb"])
    }
}
