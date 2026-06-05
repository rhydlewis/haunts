// Spike 1 — z-for-finder
// Proves NSMetadataQuery (framework) can read kMDItemLastUsedDate and roll it
// up into a sane "places I work" ranking — the warm-bootstrap signal.
// Run: swift spikes/recency-probe.swift
import Foundation

let lookbackDays = 30.0
let halfLifeDays = 14.0                       // recency weighting half-life
let cutoff = Date(timeIntervalSinceNow: -lookbackDays * 86_400)
let home = NSHomeDirectory()

let query = NSMetadataQuery()
query.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@", cutoff as NSDate)
query.searchScopes = [home]

var score: [String: Double] = [:]
var count: [String: Int] = [:]

NotificationCenter.default.addObserver(
    forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
) { _ in
    query.disableUpdates()
    let now = Date()
    let total = query.resultCount
    for i in 0..<total {
        guard let item = query.result(at: i) as? NSMetadataItem,
              let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
        else { continue }
        if path.contains("/Library/") || path.contains("/.") || path.contains("/Applications/") { continue }
        let dir = (path as NSString).deletingLastPathComponent
        if dir.isEmpty || dir == home { continue }
        let last = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
        let ageDays = last.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? lookbackDays
        score[dir, default: 0] += pow(0.5, ageDays / halfLifeDays)
        count[dir, default: 0] += 1
    }
    query.stop()

    print("  score  files  folder")
    for (dir, s) in score.sorted(by: { $0.value > $1.value }).prefix(25) {
        let scoreStr = String(format: "%6.2f", s)
        let cStr = String(format: "%5d", count[dir] ?? 0)
        print("\(scoreStr)  \(cStr)  \(dir)")
    }
    print("\nNSMetadataQuery returned \(total) items with kMDItemLastUsedDate in last \(Int(lookbackDays))d.")
    let withDate = (0..<total).compactMap { query.result(at: $0) as? NSMetadataItem }
        .filter { $0.value(forAttribute: "kMDItemLastUsedDate") is Date }.count
    print("Of those, \(withDate) returned a readable kMDItemLastUsedDate value (gate: should be > 0).")
    CFRunLoopStop(CFRunLoopGetCurrent())
}

guard query.start() else {
    FileHandle.standardError.write(Data("Failed to start NSMetadataQuery\n".utf8)); exit(1)
}

let timeout = Timer(timeInterval: 60, repeats: false) { _ in
    print("Timed out waiting for query."); CFRunLoopStop(CFRunLoopGetCurrent())
}
RunLoop.current.add(timeout, forMode: .common)
CFRunLoopRun()
