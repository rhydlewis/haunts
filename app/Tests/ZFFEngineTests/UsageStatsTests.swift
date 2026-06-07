import Testing
import Foundation
@testable import ZFFEngine

@Suite("UsageStatsTests")
struct UsageStatsTests {

    // A fixed UTC calendar so day-boundary maths is deterministic across machines.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: iso)!
    }

    private func rec(_ path: String, _ count: Int, _ origin: PlaceOrigin, _ date: Date = Date(timeIntervalSince1970: 0)) -> PlaceRecord {
        PlaceRecord(path: path, visitCount: count, lastVisitDate: date, origin: origin)
    }

    // MARK: totals & data truth

    @Test func totalCountsJumpsOnly() {
        let stats = UsageStats.make(
            records: [rec("/a", 3, .jump), rec("/a", 100, .nav), rec("/b", 2, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.totalJumps == 5)
        #expect(!stats.isEmpty)
    }

    @Test func emptyWhenNoJumps() {
        let stats = UsageStats.make(
            records: [rec("/a", 99, .nav)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.totalJumps == 0)
        #expect(stats.isEmpty)
        #expect(stats.topLocations.isEmpty)
    }

    // MARK: per-day average & cadence copy

    @Test func perDayAverageDividesByCalendarDays() {
        // 100 jumps over 10 days = 10/day → whole-number cadence.
        let stats = UsageStats.make(
            records: [rec("/a", 100, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.daysSinceInstall == 10)
        #expect(stats.perDayAverage == 10.0)
        #expect(stats.cadenceText() == "That's about 10 a day.")
    }

    @Test func cadenceOneDecimalBelowTen() {
        // 16 jumps over 5 days = 3.2/day.
        let stats = UsageStats.make(
            records: [rec("/a", 16, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-06T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.cadenceText() == "That's about 3.2 a day.")
    }

    @Test func cadenceSubOneADayUsesWordsNotZeroPointOne() {
        // 2 jumps over 20 days = 0.1/day → below 0.15 → "now and then."
        let rare = UsageStats.make(
            records: [rec("/a", 2, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-21T00:00:00Z"),
            calendar: utc
        )
        #expect(rare.cadenceText() == "now and then.")
        // 3 jumps over 10 days = 0.3/day → >= 0.15 → "a few times a week."
        let some = UsageStats.make(
            records: [rec("/a", 3, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(some.cadenceText() == "a few times a week.")
    }

    // MARK: day-0 / singular edge cases

    @Test func dayZeroSuppressesCadenceAndSaysToday() {
        let stats = UsageStats.make(
            records: [rec("/a", 4, .jump)],
            installDate: day("2026-03-03T09:00:00Z"),
            now: day("2026-03-03T18:00:00Z"),
            calendar: utc
        )
        #expect(stats.daysSinceInstall == 1)   // max(1, 0)
        #expect(stats.isInstallToday)
        #expect(stats.cadenceText() == nil)
        #expect(stats.leadText(now: day("2026-03-03T18:00:00Z"), calendar: utc)
                == "Since today, you've jumped to your haunts")
    }

    @Test func singleJumpSuppressesCadenceAndIsSingular() {
        let stats = UsageStats.make(
            records: [rec("/a", 1, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-15T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.countText() == "1 time")
        #expect(stats.cadenceText() == nil)
    }

    @Test func pluralCountIsGrouped() {
        let stats = UsageStats.make(
            records: [rec("/a", 1248, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-04-01T00:00:00Z"),
            calendar: utc
        )
        // Locale-aware grouping; assert via the same formatter rather than a literal.
        #expect(stats.countText() == "\(1248.formatted(.number)) times")
    }

    // MARK: top locations & tie-breaks

    @Test func topLocationsSortedByCountDescending() {
        let stats = UsageStats.make(
            records: [rec("/a", 3, .jump), rec("/b", 5, .jump), rec("/c", 1, .jump)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.topLocations.map(\.path) == ["/b", "/a", "/c"])
        #expect(stats.topLocations.map(\.jumpCount) == [5, 3, 1])
    }

    @Test func tiesBreakByMostRecentThenPath() {
        let older = day("2026-01-05T00:00:00Z")
        let newer = day("2026-01-09T00:00:00Z")
        let stats = UsageStats.make(
            records: [
                rec("/z", 2, .jump, older),
                rec("/a", 2, .jump, newer),   // same count, more recent → first
                rec("/m", 2, .jump, older),   // ties with /z on count+date → path A→Z
            ],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.topLocations.map(\.path) == ["/a", "/m", "/z"])
    }

    @Test func topLocationsCappedAtTenWithSequentialOrder() {
        let records = (1...15).map { rec("/p\(String(format: "%02d", $0))", $0, .jump) }
        let stats = UsageStats.make(
            records: records,
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-02-01T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.topLocations.count == 10)
        // Highest counts first: 15, 14, … 6.
        #expect(stats.topLocations.first?.jumpCount == 15)
        #expect(stats.topLocations.last?.jumpCount == 6)
    }

    @Test func lastJumpedAggregatesLatestPerPath() {
        let early = day("2026-01-02T00:00:00Z")
        let late = day("2026-01-08T00:00:00Z")
        let stats = UsageStats.make(
            records: [rec("/a", 1, .jump, early), rec("/a", 1, .jump, late)],
            installDate: day("2026-01-01T00:00:00Z"),
            now: day("2026-01-11T00:00:00Z"),
            calendar: utc
        )
        #expect(stats.topLocations.first?.jumpCount == 2)
        #expect(stats.topLocations.first?.lastJumped == late)
        #expect(stats.hasAnyDate)
    }

    // MARK: lead line year handling

    @Test func leadAppendsYearWhenInstallYearDiffers() {
        let stats = UsageStats.make(
            records: [rec("/a", 5, .jump)],
            installDate: day("2025-03-03T00:00:00Z"),
            now: day("2026-06-07T00:00:00Z"),
            calendar: utc
        )
        let lead = stats.leadText(now: day("2026-06-07T00:00:00Z"), calendar: utc)
        #expect(lead.contains("2025"))
        #expect(lead.hasPrefix("Since "))
    }
}
