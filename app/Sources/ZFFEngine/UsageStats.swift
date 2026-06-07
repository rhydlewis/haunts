import Foundation

/// Pure aggregation backing the Preferences → Usage tab.
///
/// Input: the raw frecency records, the install date, and "now". Output: the
/// headline numbers and the top-10 explicitly-jumped locations. No AppKit, no
/// I/O, no `Date()` — everything is injected so it is deterministic and fully
/// unit-testable. The view is a passive renderer over this.
///
/// Truthfulness: only `.jump` records count. Passive Finder-navigation (`.nav`)
/// and imported zoxide/z/autojump scores are never shown as "jumps".
public struct UsageStats: Equatable, Sendable {

    /// One row of the "Your top haunts" list.
    public struct Row: Identifiable, Equatable, Sendable {
        public let path: String          // absolute; abbreviated for display
        public let jumpCount: Int
        public let lastJumped: Date?
        public var id: String { path }
        public init(path: String, jumpCount: Int, lastJumped: Date?) {
            self.path = path
            self.jumpCount = jumpCount
            self.lastJumped = lastJumped
        }
    }

    /// Sum of `.jump` visit counts. Zero ⇒ the view shows its empty state.
    public let totalJumps: Int
    /// `max(1, calendarDaysBetween(install, now))` — never zero (no div-by-zero).
    public let daysSinceInstall: Int
    /// `totalJumps / daysSinceInstall`. Zero when there are no jumps.
    public let perDayAverage: Double
    /// Top 10 locations by jump count (tie-break most-recent jump, then path A→Z).
    public let topLocations: [Row]
    /// First-launch date, for the "Since …" headline.
    public let installDate: Date
    /// True when `installDate` falls on the same calendar day as `now`.
    public let isInstallToday: Bool

    public var isEmpty: Bool { totalJumps == 0 }
    /// At least one top row carries a `lastJumped` date (drives the date column).
    public var hasAnyDate: Bool { topLocations.contains { $0.lastJumped != nil } }

    public init(
        totalJumps: Int,
        daysSinceInstall: Int,
        perDayAverage: Double,
        topLocations: [Row],
        installDate: Date,
        isInstallToday: Bool
    ) {
        self.totalJumps = totalJumps
        self.daysSinceInstall = daysSinceInstall
        self.perDayAverage = perDayAverage
        self.topLocations = topLocations
        self.installDate = installDate
        self.isInstallToday = isInstallToday
    }

    // MARK: - Aggregation (pure)

    /// Build the stats from raw records. Pure: pass `now`/`calendar` explicitly.
    public static func make(
        records: [PlaceRecord],
        installDate: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> UsageStats {
        var counts: [String: Int] = [:]
        var lastDates: [String: Date] = [:]
        for r in records where r.origin == .jump {
            counts[r.path, default: 0] += r.visitCount
            if let existing = lastDates[r.path] {
                if r.lastVisitDate > existing { lastDates[r.path] = r.lastVisitDate }
            } else {
                lastDates[r.path] = r.lastVisitDate
            }
        }

        let total = counts.values.reduce(0, +)

        let startInstall = calendar.startOfDay(for: installDate)
        let startNow = calendar.startOfDay(for: now)
        let calDays = calendar.dateComponents([.day], from: startInstall, to: startNow).day ?? 0
        let daysSince = max(1, calDays)
        let avg = total == 0 ? 0 : Double(total) / Double(daysSince)

        let rows = counts
            .map { Row(path: $0.key, jumpCount: $0.value, lastJumped: lastDates[$0.key]) }
            .sorted(by: Row.rankOrder)
            .prefix(10)

        return UsageStats(
            totalJumps: total,
            daysSinceInstall: daysSince,
            perDayAverage: avg,
            topLocations: Array(rows),
            installDate: installDate,
            isInstallToday: calDays == 0
        )
    }

    // MARK: - Copy (locale-aware, but the branching logic is testable)

    /// The big ember headline: "1 time" (singular) / "1,248 times" (grouped).
    public func countText() -> String {
        totalJumps == 1 ? "1 time" : "\(totalJumps.formatted(.number)) times"
    }

    /// The cadence line, or `nil` when it should be omitted.
    ///
    /// Omitted on day 0 / day 1 (`daysSinceInstall == 1`) and for a single jump —
    /// an average over one day is meaningless. Below one-a-day we describe the
    /// rhythm in words rather than print a misleading "0.1 a day".
    public func cadenceText() -> String? {
        guard daysSinceInstall > 1, totalJumps > 1 else { return nil }
        let avg = perDayAverage
        if avg < 1 {
            return avg >= 0.15 ? "a few times a week." : "now and then."
        }
        if avg >= 10 {
            return "That's about \(Int(avg.rounded()).formatted(.number)) a day."
        }
        let oneDP = avg.formatted(.number.precision(.fractionLength(1)))
        return "That's about \(oneDP) a day."
    }

    /// The "Since …" lead line, locale-aware. Uses the literal "today" on day 0,
    /// and appends the year only when the install year differs from now's.
    public func leadText(now: Date, calendar: Calendar = .current) -> String {
        if isInstallToday {
            return "Since today, you've jumped to your haunts"
        }
        let installYear = calendar.component(.year, from: installDate)
        let nowYear = calendar.component(.year, from: now)
        let formatted = installYear == nowYear
            ? installDate.formatted(.dateTime.day().month(.wide))
            : installDate.formatted(.dateTime.day().month(.wide).year())
        return "Since \(formatted), you've jumped to your haunts"
    }
}

extension UsageStats.Row {
    /// Sort: jump count desc, then most-recent jump desc (nils last), then path A→Z.
    /// Stable and total, so ranks stay sequential with no shared positions.
    static func rankOrder(_ a: UsageStats.Row, _ b: UsageStats.Row) -> Bool {
        if a.jumpCount != b.jumpCount { return a.jumpCount > b.jumpCount }
        switch (a.lastJumped, b.lastJumped) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.path < b.path
        }
    }
}
