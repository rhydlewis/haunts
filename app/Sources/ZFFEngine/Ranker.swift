import Foundation

/// Pure ranking of `Place`s against a query. Deterministic everywhere: the
/// tiebreak is a total order (path asc), so identical input yields identical
/// output across runs — no tie shuffle that opens the wrong folder.
public enum Ranker {
    /// Stable index order: score desc, then path asc.
    public static func rankOrder(_ a: Place, _ b: Place) -> Bool {
        a.score != b.score ? a.score > b.score : a.path < b.path
    }

    /// Query-relevance score for a place: name-prefix > name-substring, plus base score.
    /// `q` must already be normalized (see `Matcher.norm`).
    public static func matchScore(_ q: String, _ p: Place) -> Double {
        let n = Matcher.norm(p.name)
        var bonus = 0.0
        if n.hasPrefix(q) { bonus += 3 } else if n.contains(q) { bonus += 1.5 }
        return bonus + p.score
    }

    /// Filter `index` to places whose NAME subsequence-matches `query`, then sort by
    /// relevance (deterministic tiebreak), capped at `limit`. An empty query returns
    /// the top `limit` of `index` as-is (callers keep `index` pre-sorted by `rankOrder`).
    public static func rank(query: String, over index: [Place], limit: Int = 9) -> [Place] {
        let q = Matcher.norm(query)
        guard !q.isEmpty else { return Array(index.prefix(limit)) }
        return index
            .filter { Matcher.isSubseq(q, Matcher.norm($0.name)) }
            .sorted { matchScore(q, $0) != matchScore(q, $1)
                      ? matchScore(q, $0) > matchScore(q, $1)
                      : $0.path < $1.path }
            .prefix(limit).map { $0 }
    }
}
