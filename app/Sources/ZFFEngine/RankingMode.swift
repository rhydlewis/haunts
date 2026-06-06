import Foundation

/// How per-folder signals combine into a final score at index-build time.
///
/// Signals: the **scan** score already summed into `Place.score` (git + Spotlight
/// meta + editor recents) and the persisted **visit** history (`[PlaceRecord]`).
/// The modes only diverge once there is visit history — with an empty store they
/// all preserve the scan order.
public enum RankingMode: String, Sendable, CaseIterable {
    /// A — `scan + decay(visitAge)·√visits`. Structure and visits both count;
    /// the scan's transient penalties stay in force. The shipped default.
    case balanced
    /// C — rank purely by your visits (`decay(visitAge)·visits`); the scan only
    /// discovers candidates. Terminal `z`/`zoxide`-style. Power-user opt-in.
    case frequent
    /// B — `max(visits, scan) + visits·0.1` (the fork's `mergePlaces`). A muddy
    /// middle kept for internal comparison only; not exposed in the UI.
    case visitMax

    public static let `default`: RankingMode = .balanced
}

public enum Frecency {
    /// Blend freshly-discovered places (whose `.score` already sums git+meta+editor)
    /// with persisted visit `records`, per `mode`. Pure + deterministic — inject `now`.
    ///
    /// Visits roll up to their git root (or, when `subfolderFrecency`, stay on a
    /// frequently-visited subfolder). With `records == []` every mode returns the
    /// discovered list in its original order.
    public static func blend(
        discovered: [Place],
        records: [PlaceRecord],
        mode: RankingMode = .default,
        subfolderFrecency: Bool = false,
        minVisitCount: Int = 3,
        repos: Set<String>,
        home: String,
        now: Date = Date()
    ) -> [Place] {
        // 1. Sum raw visit counts / latest date per raw path.
        var rawCount: [String: Int] = [:]
        var rawLast: [String: Date] = [:]
        for r in records {
            rawCount[r.path, default: 0] += r.visitCount
            if let e = rawLast[r.path] { if r.lastVisitDate > e { rawLast[r.path] = r.lastVisitDate } }
            else { rawLast[r.path] = r.lastVisitDate }
        }

        // 2. Roll each raw path to its effective (git-root or kept-subfolder) path.
        var visByEff: [String: Int] = [:]
        var lastByEff: [String: Date] = [:]
        for (raw, count) in rawCount {
            let eff: String
            if subfolderFrecency {
                eff = Rollup.keepSubfolder(URL(fileURLWithPath: raw), repos: repos, home: home,
                                           minVisitCount: minVisitCount, visitCount: count).path
            } else {
                eff = Rollup.gitRoot(raw, repos: repos, home: home)
            }
            visByEff[eff, default: 0] += count
            let d = rawLast[raw] ?? Date(timeIntervalSince1970: 0)
            if let e = lastByEff[eff] { if d > e { lastByEff[eff] = d } } else { lastByEff[eff] = d }
        }

        // 3. Score the union of discovered + visited paths by mode.
        var seed: [String: Place] = [:]
        for p in discovered { seed[p.path] = p }

        var out: [Place] = []
        out.reserveCapacity(seed.count + visByEff.count)
        for path in Set(seed.keys).union(visByEff.keys) {
            let base = seed[path]
            let fresh = base?.score ?? 0
            let count = visByEff[path] ?? 0

            var storedSqrt = 0.0, storedLinear = 0.0
            if count > 0 {
                let ageDays = max(0, now.timeIntervalSince(lastByEff[path] ?? now) / 86400)
                let dk = Scoring.decay(ageDays)
                storedSqrt = dk * Double(count).squareRoot()
                storedLinear = dk * Double(count)
            }

            let score: Double
            switch mode {
            case .balanced: score = fresh + storedSqrt
            case .visitMax: score = max(storedSqrt, fresh) + Double(count) * 0.1
            case .frequent: score = storedLinear + fresh * 0.001
            }

            var place = base ?? Place(path: path, score: 0, sources: [])
            place.score = score
            if count > 0 {
                place.sources.insert("store")
                place.useComponent = Double(count)
                if place.decayComponent == 0 { place.decayComponent = storedSqrt }
            }
            out.append(place)
        }
        return out.sorted(by: Ranker.rankOrder)
    }
}
