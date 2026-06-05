import Foundation

/// Frecency scoring math. Pure: caller supplies ages / counts / timestamps,
/// so there is no hidden clock and tests are deterministic.
public enum Scoring {
    public static let halfLifeDays = 30.0

    /// Transient locations (Downloads/Desktop/Screenshots) get heavily down-weighted.
    public static let transientMultiplier = 0.08

    /// Exponential time-decay with a 30-day half-life. Clamps negative ages to 0.
    public static func decay(_ ageDays: Double) -> Double {
        pow(0.5, max(0, ageDays) / halfLifeDays)
    }

    /// Age in days between a unix timestamp and `now` (also a unix timestamp).
    public static func ageDays(since ts: Double, now: Double) -> Double {
        (now - ts) / 86400
    }

    /// Spotlight signal weight: time-decayed and boosted by sqrt(useCount).
    public static func metaWeight(ageDays: Double, useCount: Double) -> Double {
        decay(ageDays) * sqrt(useCount)
    }
}
