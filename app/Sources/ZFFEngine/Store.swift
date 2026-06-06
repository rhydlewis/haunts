import Foundation

/// A single frecency log entry. One entry is appended per navigation event;
/// `compact()` later deduplicates by path.
public struct PlaceRecord: Codable, Sendable, Equatable {
    public var path: String
    public var visitCount: Int
    public var lastVisitDate: Date

    public init(path: String, visitCount: Int, lastVisitDate: Date) {
        self.path = path
        self.visitCount = visitCount
        self.lastVisitDate = lastVisitDate
    }
}

/// Append-log frecency store backed by a JSON file at
/// `~/Library/Application Support/Haunts/frecency.json`.
///
/// Design: every `record()` call appends one entry (visitCount = 1).
/// `compact()` deduplicates by path, summing visitCounts and keeping the latest date.
/// Auto-compact fires when the raw entry count exceeds 500.
public struct Store: Sendable {
    public let fileURL: URL

    private static let autoCompactThreshold = 500

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default store at `~/Library/Application Support/Haunts/frecency.json`.
    public static func defaultStore() -> Store {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Haunts", isDirectory: true)
        return Store(fileURL: dir.appendingPathComponent("frecency.json"))
    }

    // MARK: - Load

    /// Read all records. Creates the parent directory and an empty file if absent.
    /// Returns `[]` on missing file or malformed JSON — never throws.
    public func load() -> [PlaceRecord] {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()

        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: fileURL.path) {
            try? "[]".data(using: .utf8)!.write(to: fileURL, options: .atomic)
            return []
        }

        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PlaceRecord].self, from: data)) ?? []
    }

    // MARK: - Record

    /// Append a new entry for `path` (visitCount = 1). Auto-compacts when the
    /// total raw entry count exceeds 500.
    public func record(path: URL, visitedAt: Date = Date()) {
        let entry = PlaceRecord(path: path.path, visitCount: 1, lastVisitDate: visitedAt)
        var records = load()
        records.append(entry)
        write(records)
        if records.count > Store.autoCompactThreshold {
            compact()
        }
    }

    // MARK: - Compact

    /// Deduplicate by path: sum visitCounts, keep latest lastVisitDate. Writes atomically.
    public func compact() {
        let records = load()
        var byPath: [String: PlaceRecord] = [:]
        for r in records {
            if var existing = byPath[r.path] {
                existing.visitCount += r.visitCount
                if r.lastVisitDate > existing.lastVisitDate {
                    existing.lastVisitDate = r.lastVisitDate
                }
                byPath[r.path] = existing
            } else {
                byPath[r.path] = r
            }
        }
        write(Array(byPath.values))
    }

    // MARK: - Merge (rebuild seed)

    /// Merge store records with freshly-discovered `[Place]` and return a ranked list.
    ///
    /// Formula: `combinedScore = max(storedScore, freshScore) + storedVisitBoost`
    ///
    /// - Parameters:
    ///   - discovered: Places found by the git/Spotlight scan (may be empty).
    ///   - subfolderFrecency: When `true`, subfolders that meet `minVisitCount` keep their
    ///     own path instead of collapsing to the git root.
    ///   - minVisitCount: Threshold for `Rollup.keepSubfolder`.
    ///   - repos: Set of git-root paths (injected for testability).
    ///   - home: Home directory string (injected for testability).
    public func mergePlaces(
        discovered: [Place],
        subfolderFrecency: Bool,
        minVisitCount: Int,
        repos: Set<String>,
        home: String
    ) -> [Place] {
        let records = load()

        // Aggregate per-path visit counts and latest date from the store.
        var visitCounts: [String: Int] = [:]
        var latestDates: [String: Date] = [:]
        for r in records {
            visitCounts[r.path, default: 0] += r.visitCount
            if let existing = latestDates[r.path] {
                if r.lastVisitDate > existing { latestDates[r.path] = r.lastVisitDate }
            } else {
                latestDates[r.path] = r.lastVisitDate
            }
        }

        // Seed with discovered places (keyed by path).
        var seed: [String: Place] = [:]
        for place in discovered {
            seed[place.path] = place
        }

        // Merge store records into seed.
        let now = Date()
        for (rawPath, visitCount) in visitCounts {
            let url = URL(fileURLWithPath: rawPath)
            let effectivePath: String

            if subfolderFrecency {
                effectivePath = Rollup.keepSubfolder(
                    url, repos: repos, home: home,
                    minVisitCount: minVisitCount, visitCount: visitCount
                ).path
            } else {
                effectivePath = Rollup.gitRoot(rawPath, repos: repos, home: home)
            }

            let freshScore = seed[effectivePath]?.score ?? 0.0

            let date = latestDates[rawPath] ?? Date(timeIntervalSince1970: 0)
            let ageDays = max(0, now.timeIntervalSince(date) / 86400)
            // storedScore: decay-weighted visit signal (mirrors Scoring.metaWeight but uses sqrt of raw count)
            let storedScore = Scoring.decay(ageDays) * sqrt(Double(visitCount))
            // storedVisitBoost: small flat bonus per accumulated visit — always non-zero when visitCount > 0
            let storedVisitBoost = Double(visitCount) * 0.1

            let combinedScore = max(storedScore, freshScore) + storedVisitBoost

            if var place = seed[effectivePath] {
                place.score = combinedScore
                place.sources.insert("store")
                // Preserve git decay from discovery; add store's use signal
                if place.decayComponent == 0 { place.decayComponent = storedScore }
                place.useComponent = Double(visitCount)
                seed[effectivePath] = place
            } else {
                seed[effectivePath] = Place(
                    path: effectivePath,
                    score: combinedScore,
                    sources: ["store"],
                    decayComponent: storedScore,
                    useComponent: Double(visitCount)
                )
            }
        }

        return seed.values.sorted(by: Ranker.rankOrder)
    }

    // MARK: - Private

    private func write(_ records: [PlaceRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
