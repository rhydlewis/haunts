import Testing
import Foundation
@testable import ZFFEngine

/// Regression tests for ranking bugs fixed this session.
struct RankerTests {

    private func place(_ path: String, score: Double = 1, sources: Set<String> = ["meta"]) -> Place {
        Place(path: path, score: score, sources: sources)
    }

    // (a) separator-insensitive: "z for" must match "z-for-finder".
    @Test func separatorInsensitiveMatch() {
        let index = [place("/Users/x/code/z-for-finder")]
        let names = Ranker.rank(query: "z for", over: index).map(\.name)
        #expect(names == ["z-for-finder"])
    }

    // (b) name-only matching: "code" matches code/xcode/claude-code but NOT z-for-finder.
    @Test func nameOnlyMatching() {
        let index = [
            place("/Users/x/code"),
            place("/Users/x/dev/xcode"),
            place("/Users/x/dev/claude-code"),
            place("/Users/x/code/z-for-finder"),
        ]
        let matched = Set(Ranker.rank(query: "code", over: index).map(\.name))
        #expect(matched == ["code", "xcode", "claude-code"])
        #expect(!matched.contains("z-for-finder"))
    }

    // (c) deterministic: identical input (regardless of feed order) yields identical order.
    @Test func deterministicStableOrder() {
        let a = place("/Users/x/alpha", score: 5)
        let b = place("/Users/x/beta", score: 5)   // tie with alpha -> path breaks it
        let c = place("/Users/x/gamma", score: 9)

        let run1 = Ranker.rank(query: "", over: [a, b, c].sorted(by: Ranker.rankOrder)).map(\.path)
        let run2 = Ranker.rank(query: "", over: [c, b, a].sorted(by: Ranker.rankOrder)).map(\.path)
        #expect(run1 == run2)
        // gamma (higher score) first; alpha before beta on the tie.
        #expect(run1 == ["/Users/x/gamma", "/Users/x/alpha", "/Users/x/beta"])
    }

    // (d) "v2" ranks flowcus-v2 first.
    @Test func versionSuffixRanksFirst() {
        // flowcus-v2 is the active repo (accumulated frecency); flowcus has no
        // "v2" subsequence so it filters out; v2-notes is a cold also-ran.
        let index = [
            place("/Users/x/code/flowcus-v2", score: 5),
            place("/Users/x/code/flowcus", score: 1),
            place("/Users/x/code/v2-notes", score: 1),
        ]
        let ranked = Ranker.rank(query: "v2", over: index).map(\.name)
        #expect(ranked.first == "flowcus-v2")
        #expect(!ranked.contains("flowcus"))
    }

    // Empty query returns the pre-sorted top slice, untouched.
    @Test func emptyQueryReturnsTopSlice() {
        let index = (0..<20).map { place("/Users/x/p\($0)", score: Double(20 - $0)) }
        let out = Ranker.rank(query: "", over: index, limit: 9)
        #expect(out.count == 9)
        #expect(out.first?.path == "/Users/x/p0")
    }
}
