import Foundation

/// Day-one warm-seed blend (ported from `spikes/seed-prototype.py`).
///
/// The cold-start wedge: rank folders from signals that already exist on the
/// machine (git repos, shell history, IDE recents, Spotlight metadata) *before*
/// the app has observed a single navigation. The blend has two properties the
/// old additive sum lacked:
///
///  1. **Per-source normalization.** Each source's raw weights are scaled to
///     `0...1` across folders, then multiplied by a per-source trust weight, then
///     summed. So a high-volume source (e.g. thousands of shell-history hits on one
///     folder) contributes at most its trust weight and cannot drown the others.
///  2. **Source-diversity bonus.** A small bonus per *additional* distinct source
///     that voted for a folder. Cross-source agreement is the confidence story a
///     cold-starting incumbent can't tell — so folders multiple sources agree on
///     rank above single-source folders of equal raw strength.
///
/// Pure + deterministic: the caller supplies the already-summed per-source weights,
/// so there is no clock, filesystem, or hidden state here.
public enum WarmSeed {
    /// Per-source trust. git / shell / editor / meta are first-class; unknown
    /// sources default to 1.0 via the lookup below.
    public static let defaultTrust: [String: Double] = [
        "git": 1.0, "editor": 1.0, "shell": 1.0, "meta": 1.0,
    ]

    /// Score added per *additional* distinct source (so a single-source folder gets
    /// none, two sources get one unit, three get two, …). Small relative to the
    /// per-source max of 1.0 so it tips ties toward agreement without overpowering
    /// a genuinely strong single source.
    public static let diversityBonus = 0.15

    /// Blend per-source raw weights into ranked `Place`s.
    ///
    /// - Parameters:
    ///   - sources: folder path → (source name → summed raw weight).
    ///   - trust: per-source trust weight; missing keys default to 1.0.
    ///   - diversityBonus: bonus per additional distinct source.
    ///   - home: home dir (injected) for the transient-folder check.
    public static func blend(
        sources: [String: [String: Double]],
        trust: [String: Double] = defaultTrust,
        diversityBonus: Double = diversityBonus,
        home: String
    ) -> [Place] {
        // Per-source maximum across all folders — the normalizer.
        var srcMax: [String: Double] = [:]
        for (_, srcs) in sources {
            for (s, w) in srcs where w > (srcMax[s] ?? 0) { srcMax[s] = w }
        }

        var out: [Place] = []
        out.reserveCapacity(sources.count)
        for (folder, srcs) in sources {
            var total = 0.0
            var voted: Set<String> = []
            for (s, w) in srcs {
                guard let mx = srcMax[s], mx > 0 else { continue }
                total += (w / mx) * (trust[s] ?? 1.0)
                voted.insert(s)
            }
            total += Double(max(0, voted.count - 1)) * diversityBonus
            if Rollup.isTransient(folder, home: home) {
                total *= Scoring.transientMultiplier
            }
            out.append(Place(path: folder, score: total, sources: voted))
        }
        return out.sorted(by: Ranker.rankOrder)
    }
}
