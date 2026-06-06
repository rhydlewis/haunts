import Testing
import Foundation
@testable import ZFFEngine

struct RankingModeTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let repos: Set<String> = []
    let home = "/Users/x"

    private func place(_ path: String, _ score: Double) -> Place {
        Place(path: path, score: score, sources: ["git"])
    }
    private func rec(_ path: String, count: Int, ageDays: Double) -> PlaceRecord {
        PlaceRecord(path: path, visitCount: count, lastVisitDate: now.addingTimeInterval(-ageDays * 86400))
    }

    @Test func defaultModeIsBalanced() { #expect(RankingMode.default == .balanced) }

    // Characterization: empty store leaves the scan order untouched — in EVERY mode.
    // This is the safety net: wiring the store changes nothing until visits exist.
    @Test func allModesPreserveScanOrderWhenStoreEmpty() {
        let d = [place("/Users/x/a", 1), place("/Users/x/b", 3), place("/Users/x/c", 2)]
        for m in RankingMode.allCases {
            let out = Frecency.blend(discovered: d, records: [], mode: m, repos: repos, home: home, now: now)
            #expect(out.map(\.path) == ["/Users/x/b", "/Users/x/c", "/Users/x/a"], "mode \(m)")
        }
    }

    // Balanced: a low-scan folder with many recent visits rises above a higher-scan, unvisited one.
    @Test func balancedAddsDecayedVisits() {
        let d = [place("/Users/x/hi", 2.0), place("/Users/x/lo", 0.5)]
        let r = [rec("/Users/x/lo", count: 9, ageDays: 0)]   // 0.5 + decay(0)*√9 = 3.5 > 2.0
        let out = Frecency.blend(discovered: d, records: r, mode: .balanced, repos: repos, home: home, now: now)
        #expect(out.first?.path == "/Users/x/lo")
    }

    // Frequent (z): visits dominate; a high-scan but UNVISITED folder sinks to the bottom.
    @Test func frequentRanksByVisitsIgnoringScan() {
        let d = [place("/Users/x/scanHigh", 5.0), place("/Users/x/visited", 0.1)]
        let r = [rec("/Users/x/visited", count: 10, ageDays: 0)]   // 10 >> 5*0.001
        let out = Frecency.blend(discovered: d, records: r, mode: .frequent, repos: repos, home: home, now: now)
        #expect(out.first?.path == "/Users/x/visited")
        #expect(out.last?.path == "/Users/x/scanHigh")
    }

    // visitMax (fork): the flat per-visit boost lifts a heavily-visited low-scan folder.
    @Test func visitMaxFlatBoostLiftsHeavyVisits() {
        let d = [place("/Users/x/proj", 2.0), place("/Users/x/dl", 0.2)]
        let r = [rec("/Users/x/dl", count: 25, ageDays: 30)]   // max(2.5,0.2)+2.5 = 5.0 > 2.0
        let out = Frecency.blend(discovered: d, records: r, mode: .visitMax, repos: repos, home: home, now: now)
        #expect(out.first?.path == "/Users/x/dl")
    }

    // Visits to a deep subfolder fold into the git root when subfolderFrecency is off.
    @Test func visitsRollUpToGitRoot() {
        let repos: Set<String> = ["/Users/x/code/proj"]
        let d = [place("/Users/x/code/proj", 1.0)]
        let r = [rec("/Users/x/code/proj/src/deep", count: 5, ageDays: 0)]
        let out = Frecency.blend(discovered: d, records: r, mode: .balanced, repos: repos, home: home, now: now)
        #expect(out.count == 1)
        #expect(out.first?.path == "/Users/x/code/proj")
        #expect(out.first!.score > 1.0)
    }

    // With subfolderFrecency on, a frequently-visited subfolder keeps its own row.
    @Test func subfolderFrecencyKeepsSubfolder() {
        let repos: Set<String> = ["/Users/x/code/proj"]
        let d = [place("/Users/x/code/proj", 1.0)]
        let r = [rec("/Users/x/code/proj/src/deep", count: 5, ageDays: 0)]
        let out = Frecency.blend(discovered: d, records: r, mode: .balanced,
                                 subfolderFrecency: true, minVisitCount: 3, repos: repos, home: home, now: now)
        #expect(out.contains { $0.path == "/Users/x/code/proj/src/deep" })
    }
}
