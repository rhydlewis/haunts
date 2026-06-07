import Foundation

/// How a visit entered the frecency store.
///
/// - `nav`: passive observation by the Finder tracker (opt-in "Learn from
///   navigation"), or any legacy/imported record with no recorded origin.
/// - `jump`: an explicit palette activation (return / ⌘-return / ⌃-return) — the
///   user's strongest frecency signal and the only origin the Usage tab counts.
public enum PlaceOrigin: String, Codable, Sendable, Equatable {
    case nav
    case jump
}

/// A single frecency log entry. One entry is appended per navigation event;
/// `compact()` later deduplicates by (path, origin).
public struct PlaceRecord: Codable, Sendable, Equatable {
    public var path: String
    public var visitCount: Int
    public var lastVisitDate: Date
    /// Defaults to `.nav` so records written before this field existed (and any
    /// future record created without an explicit origin) decode/construct as
    /// passive navigation — a safe migration that never breaks learned data.
    public var origin: PlaceOrigin

    public init(path: String, visitCount: Int, lastVisitDate: Date, origin: PlaceOrigin = .nav) {
        self.path = path
        self.visitCount = visitCount
        self.lastVisitDate = lastVisitDate
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey { case path, visitCount, lastVisitDate, origin }

    // Custom decode (encode stays synthesized): the synthesized decoder treats a
    // missing key as an error, so we decode `origin` leniently — absent ⇒ `.nav`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        visitCount = try c.decode(Int.self, forKey: .visitCount)
        lastVisitDate = try c.decode(Date.self, forKey: .lastVisitDate)
        origin = try c.decodeIfPresent(PlaceOrigin.self, forKey: .origin) ?? .nav
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
    /// total raw entry count exceeds 500. `origin` distinguishes an explicit jump
    /// from passive navigation; it defaults to `.nav`.
    public func record(path: URL, visitedAt: Date = Date(), origin: PlaceOrigin = .nav) {
        let entry = PlaceRecord(path: path.path, visitCount: 1, lastVisitDate: visitedAt, origin: origin)
        var records = load()
        records.append(entry)
        write(records)
        if records.count > Store.autoCompactThreshold {
            compact()
        }
    }

    // MARK: - Compact

    /// Deduplicate by (path, origin): sum visitCounts, keep latest lastVisitDate.
    /// Writes atomically.
    ///
    /// Origin is part of the key — not collapsed away — so a folder reached by both
    /// passive navigation and explicit jumps keeps one row per origin. Ranking sums
    /// across both (see `Frecency.blend`), while the Usage tab can still count jumps
    /// truthfully (`Store.totalJumps` / `jumpCounts`). Collapsing to a single origin
    /// would force a lossy choice that over- or under-counts explicit jumps.
    public func compact() {
        let records = load()
        struct Key: Hashable { let path: String; let origin: PlaceOrigin }
        var byKey: [Key: PlaceRecord] = [:]
        for r in records {
            let key = Key(path: r.path, origin: r.origin)
            if var existing = byKey[key] {
                existing.visitCount += r.visitCount
                if r.lastVisitDate > existing.lastVisitDate {
                    existing.lastVisitDate = r.lastVisitDate
                }
                byKey[key] = existing
            } else {
                byKey[key] = r
            }
        }
        write(Array(byKey.values))
    }

    // MARK: - Usage aggregation (pure)

    /// A folder's explicit-jump tally, for the Usage tab's top locations.
    public struct JumpCount: Equatable, Sendable {
        public let path: String
        public let count: Int
        public init(path: String, count: Int) {
            self.path = path
            self.count = count
        }
    }

    /// Total explicit jumps = sum of `visitCount` across `.jump` records only.
    /// Passive navigation and imported scores never count. Pure.
    public static func totalJumps(_ records: [PlaceRecord]) -> Int {
        records.lazy.filter { $0.origin == .jump }.reduce(0) { $0 + $1.visitCount }
    }

    /// Per-folder explicit-jump counts, highest first (ties broken by path for a
    /// stable order). `.jump` records only. Pure — backs the Usage tab's top-N.
    public static func jumpCounts(_ records: [PlaceRecord]) -> [JumpCount] {
        var byPath: [String: Int] = [:]
        for r in records where r.origin == .jump {
            byPath[r.path, default: 0] += r.visitCount
        }
        return byPath
            .map { JumpCount(path: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.path < $1.path }
    }

    // MARK: - Reset

    /// Forget every recorded visit: overwrite the store with an empty list.
    /// Used by "Reset Learned Data…" in Preferences. Never throws.
    public func reset() {
        write([])
    }

    /// Forget a single folder: drop every record at `path` AND under it (so visits
    /// to subfolders that rolled up into a row are forgotten too). Backs the palette's
    /// ⌘⌫ "forget this folder" shortcut. Never throws.
    public func forget(path: String) {
        let prefix = path + "/"
        let kept = load().filter { $0.path != path && !$0.path.hasPrefix(prefix) }
        write(kept)
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
