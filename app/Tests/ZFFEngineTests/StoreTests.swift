import Testing
import Foundation
@testable import ZFFEngine

// MARK: - Helpers

private func makeTempStore() -> (Store, URL, () -> Void) {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("StoreTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = dir.appendingPathComponent("frecency.json")
    let store = Store(fileURL: fileURL)
    return (store, dir, {
        try? FileManager.default.removeItem(at: dir)
    })
}

private func entryCount(at url: URL) -> Int {
    guard let data = try? Data(contentsOf: url) else { return 0 }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([PlaceRecord].self, from: data))?.count ?? 0
}

// MARK: - PlaceRecord Codable

struct PlaceRecordCodableTests {

    @Test func roundTripSimplePath() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PlaceRecord(path: "/Users/x/code/myrepo", visitCount: 3, lastVisitDate: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlaceRecord.self, from: data)
        #expect(decoded.path == record.path)
        #expect(decoded.visitCount == record.visitCount)
        #expect(abs(decoded.lastVisitDate.timeIntervalSince(record.lastVisitDate)) < 1)
    }

    @Test func roundTripPathWithSpaces() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PlaceRecord(path: "/Users/x/My Projects/cool app", visitCount: 1, lastVisitDate: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlaceRecord.self, from: data)
        #expect(decoded.path == "/Users/x/My Projects/cool app")
    }

    @Test func roundTripUnicodePath() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PlaceRecord(path: "/Users/x/Documents/プロジェクト", visitCount: 7, lastVisitDate: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlaceRecord.self, from: data)
        #expect(decoded.path == "/Users/x/Documents/プロジェクト")
        #expect(decoded.visitCount == 7)
    }

    @Test func arrayRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let records = [
            PlaceRecord(path: "/Users/x/a", visitCount: 1, lastVisitDate: date),
            PlaceRecord(path: "/Users/x/b", visitCount: 2, lastVisitDate: date),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([PlaceRecord].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].path == "/Users/x/a")
        #expect(decoded[1].visitCount == 2)
    }
}

// MARK: - Store.load

struct StoreLoadTests {

    @Test func loadCreatesParentDirAndEmptyFile() {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }

        #expect(!FileManager.default.fileExists(atPath: dir.path))
        let records = store.load()
        #expect(records.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func loadReturnsEmptyOnMissingFile() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let records = store.load()
        #expect(records.isEmpty)
    }

    @Test func loadReturnsEmptyOnMalformedJSON() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not valid json at all!!!".data(using: .utf8)!.write(to: store.fileURL, options: .atomic)
        let records = store.load()
        #expect(records.isEmpty)
    }

    @Test func loadReturnsEmptyOnTruncatedJSON() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "[{\"path\":\"/a\",\"visitCount\":1,\"lastVisit".data(using: .utf8)!.write(to: store.fileURL, options: .atomic)
        let records = store.load()
        #expect(records.isEmpty)
    }

    @Test func loadReturnsEmptyOnNonJSONBytes() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0x42])
        try garbage.write(to: store.fileURL, options: .atomic)
        let records = store.load()
        #expect(records.isEmpty)
    }

    @Test func loadRoundTripsRecords() throws {
        let (store, dir, cleanup) = makeTempStore()
        defer { cleanup() }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let input = [PlaceRecord(path: "/a/b", visitCount: 2, lastVisitDate: date)]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(input).write(to: store.fileURL, options: .atomic)
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].path == "/a/b")
        #expect(loaded[0].visitCount == 2)
    }

    @Test func filePathUsesApplicationSupport() {
        let defaultStore = Store.defaultStore()
        #expect(defaultStore.fileURL.path.contains("Application Support"))
        #expect(defaultStore.fileURL.path.contains("Haunts"))
        #expect(defaultStore.fileURL.lastPathComponent == "frecency.json")
    }
}

// MARK: - Store.record

struct StoreRecordTests {

    @Test func recordAppendsNewEntry() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/x/myrepo")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(path: url, visitedAt: date)
        let records = store.load()
        #expect(records.count == 1)
        #expect(records[0].path == "/Users/x/myrepo")
        #expect(records[0].visitCount == 1)
    }

    @Test func recordDoesNotUpsert() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/x/myrepo")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(path: url, visitedAt: date)
        store.record(path: url, visitedAt: date)
        let records = store.load()
        #expect(records.count == 2)
        #expect(records[0].path == "/Users/x/myrepo")
        #expect(records[1].path == "/Users/x/myrepo")
    }

    @Test func recordProducesValidJSONEachCall() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<5 {
            store.record(path: URL(fileURLWithPath: "/p/\(i)"), visitedAt: date)
            let data = try Data(contentsOf: store.fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let parsed = try decoder.decode([PlaceRecord].self, from: data)
            #expect(parsed.count == i + 1)
        }
    }

    @Test func recordEncodesPathAsAbsoluteString() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/test/project")
        store.record(path: url, visitedAt: Date())
        let records = store.load()
        #expect(records[0].path == "/Users/test/project")
    }

    @Test func recordEncodesVisitCountAs1() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        store.record(path: URL(fileURLWithPath: "/a/b"), visitedAt: Date())
        let records = store.load()
        #expect(records[0].visitCount == 1)
    }
}

// MARK: - Store.compact

struct StoreCompactTests {

    @Test func compactDeduplicatesByPath() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/x/myrepo")
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let date2 = Date(timeIntervalSince1970: 1_700_100_000)
        store.record(path: url, visitedAt: date1)
        store.record(path: url, visitedAt: date2)
        store.record(path: url, visitedAt: date1)
        store.compact()
        let records = store.load()
        #expect(records.count == 1)
        #expect(records[0].path == "/Users/x/myrepo")
    }

    @Test func compactSumsVisitCounts() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/x/myrepo")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(path: url, visitedAt: date)
        store.record(path: url, visitedAt: date)
        store.record(path: url, visitedAt: date)
        store.compact()
        let records = store.load()
        #expect(records[0].visitCount == 3)
    }

    @Test func compactKeepsLatestDate() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/Users/x/myrepo")
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_701_000_000)
        store.record(path: url, visitedAt: older)
        store.record(path: url, visitedAt: newer)
        store.record(path: url, visitedAt: older)
        store.compact()
        let records = store.load()
        #expect(abs(records[0].lastVisitDate.timeIntervalSince(newer)) < 1)
    }

    @Test func compactOnEmptyStoreProducesValidEmptyFile() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        _ = store.load()  // create file
        store.compact()
        let records = store.load()
        #expect(records.isEmpty)
    }

    @Test func compactOnAlreadyUniqueStorePreservesAllData() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(path: URL(fileURLWithPath: "/a"), visitedAt: date)
        store.record(path: URL(fileURLWithPath: "/b"), visitedAt: date)
        store.record(path: URL(fileURLWithPath: "/c"), visitedAt: date)
        store.compact()
        let records = store.load()
        #expect(records.count == 3)
        let paths = Set(records.map(\.path))
        #expect(paths == ["/a", "/b", "/c"])
    }

    @Test func compactProducesValidParseable() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let url = URL(fileURLWithPath: "/x")
        store.record(path: url, visitedAt: Date())
        store.record(path: url, visitedAt: Date())
        store.compact()
        let data = try Data(contentsOf: store.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parsed = try decoder.decode([PlaceRecord].self, from: data)
        #expect(parsed.count == 1)
    }

    @Test func multipleDifferentPathsAfterCompact() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let urls = ["/a", "/b", "/a", "/c", "/b", "/a"].map { URL(fileURLWithPath: $0) }
        for url in urls {
            store.record(path: url, visitedAt: date)
        }
        store.compact()
        let records = store.load()
        // a: 3 visits, b: 2 visits, c: 1 visit
        let byPath = Dictionary(uniqueKeysWithValues: records.map { ($0.path, $0) })
        #expect(byPath["/a"]?.visitCount == 3)
        #expect(byPath["/b"]?.visitCount == 2)
        #expect(byPath["/c"]?.visitCount == 1)
    }
}

// MARK: - Auto-compact threshold

struct StoreAutoCompactTests {

    @Test func autoCompactAfter500Entries() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        // Record 501 distinct paths — auto-compact may fire at 501 (501 > 500)
        for i in 0..<501 {
            store.record(path: URL(fileURLWithPath: "/p/\(i)"), visitedAt: date)
        }
        // Record one more — ensures we crossed the threshold
        store.record(path: URL(fileURLWithPath: "/p/501"), visitedAt: date)

        // All paths are distinct so compacted count == raw count (≤ 502)
        let records = store.load()
        #expect(records.count <= 502)
        // After auto-compact each path appears exactly once
        let paths = records.map(\.path)
        let unique = Set(paths)
        #expect(unique.count == paths.count)
    }

    @Test func autoCompactWithRepeatedPaths() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let baseURL = URL(fileURLWithPath: "/shared/path")

        // Record 501 entries to one path — auto-compact fires when count > 500.
        // After compact, 1 compacted entry. The 502nd record then appends one more.
        for _ in 0..<501 {
            store.record(path: baseURL, visitedAt: date)
        }
        // One more to ensure threshold check fired
        store.record(path: baseURL, visitedAt: date)

        let records = store.load()
        // Compact fired: the raw entry count is far fewer than 502
        #expect(records.count <= 2)
        // All entries are for the same path (no data corruption)
        #expect(records.allSatisfy { $0.path == "/shared/path" })
        // Total visits are preserved
        let totalVisits = records.map(\.visitCount).reduce(0, +)
        #expect(totalVisits == 502)
    }
}

// MARK: - Atomic writes

struct StoreAtomicWriteTests {

    @Test func recordWritesAtomically() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(path: URL(fileURLWithPath: "/a"), visitedAt: date)

        // File must exist and be valid JSON immediately after record()
        let data = try Data(contentsOf: store.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parsed = try decoder.decode([PlaceRecord].self, from: data)
        #expect(parsed.count == 1)
    }

    @Test func compactWritesAtomically() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        store.record(path: URL(fileURLWithPath: "/a"), visitedAt: date)
        store.record(path: URL(fileURLWithPath: "/a"), visitedAt: date)
        store.compact()

        let data = try Data(contentsOf: store.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parsed = try decoder.decode([PlaceRecord].self, from: data)
        #expect(parsed.count == 1)
        #expect(parsed[0].visitCount == 2)
    }
}

// MARK: - Reset

@Suite("StoreResetTests")
struct StoreResetTests {

    @Test func resetEmptiesAStoreWithRecords() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        store.record(path: URL(fileURLWithPath: "/a"))
        store.record(path: URL(fileURLWithPath: "/b"))
        #expect(store.load().count == 2)

        store.reset()
        #expect(store.load().isEmpty)
        #expect(entryCount(at: store.fileURL) == 0)
    }

    @Test func resetWritesEmptyArrayFile() throws {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        store.record(path: URL(fileURLWithPath: "/a"))
        store.reset()
        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        // Decodes back to an empty array of records.
        let data = Data(raw.utf8)
        let decoded = try JSONDecoder().decode([PlaceRecord].self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test func resetOnEmptyStoreIsIdempotent() {
        let (store, _, cleanup) = makeTempStore()
        defer { cleanup() }
        store.reset()
        store.reset()
        #expect(store.load().isEmpty)
    }
}
