// Spike 2 — z-for-finder ranking prototype (throwaway)
// Proves a tuned frecency ranking beats naive recency on real daily folders.
// Tuning applied (from Spike 1 learnings):
//   * frecency = sqrt(useCount) * recencyHalfLife(lastUsed)      — blend frequency + recency
//   * roll each file up to its nearest .git project root          — repo, not deep leaf
//   * down-weight transient dirs (Downloads/Desktop/Screenshots)  — they're noise, not workplaces
// Run: swift spikes/ranking-prototype.swift
import Foundation

let lookbackDays = 90.0
let halfLifeDays = 30.0                        // "places" are revisited over weeks
let downWeight = 0.08                           // multiplier for transient dirs
let cutoff = Date(timeIntervalSinceNow: -lookbackDays * 86_400)
let home = NSHomeDirectory()
let fm = FileManager.default

let transientRoots = ["/Downloads", "/Desktop", "/Screenshots", "/.Trash"].map { home + $0 }

// Cache: a directory -> its rollup target (nearest .git ancestor, else itself)
var rollupCache: [String: String] = [:]
func rollup(_ fileDir: String) -> String {
    if let hit = rollupCache[fileDir] { return hit }
    var cur = fileDir
    var found: String? = nil
    while cur.hasPrefix(home) && cur != home && cur != "/" {
        if fm.fileExists(atPath: cur + "/.git") { found = cur; break }
        cur = (cur as NSString).deletingLastPathComponent
    }
    let target = found ?? fileDir
    rollupCache[fileDir] = target
    return target
}

func isTransient(_ path: String) -> Bool { transientRoots.contains { path == $0 || path.hasPrefix($0 + "/") } }

let query = NSMetadataQuery()
query.predicate = NSPredicate(format: "kMDItemLastUsedDate >= %@", cutoff as NSDate)
query.searchScopes = [home]

struct Agg { var score = 0.0; var files = 0; var isRepo = false; var transient = false }
var agg: [String: Agg] = [:]

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
        let fileDir = (path as NSString).deletingLastPathComponent
        if fileDir.isEmpty || fileDir == home { continue }

        let last = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
        let ageDays = last.map { max(0, now.timeIntervalSince($0) / 86_400) } ?? lookbackDays
        let recency = pow(0.5, ageDays / halfLifeDays)
        let useCount = (item.value(forAttribute: "kMDItemUseCount") as? NSNumber)?.doubleValue ?? 1
        let frecency = sqrt(useCount) * recency

        let folder = rollup(fileDir)
        var a = agg[folder] ?? Agg()
        a.score += frecency
        a.files += 1
        a.isRepo = a.isRepo || (folder != fileDir) || fm.fileExists(atPath: folder + "/.git")
        a.transient = isTransient(folder)
        agg[folder] = a
    }
    query.stop()

    // apply transient down-weight
    let ranked = agg.map { (k, v) -> (String, Agg, Double) in
        (k, v, v.transient ? v.score * downWeight : v.score)
    }.sorted { $0.2 > $1.2 }.prefix(20)

    print("  rank  score  files  kind   folder")
    var r = 1
    for (folder, v, finalScore) in ranked {
        let kind = v.transient ? "trans" : (v.isRepo ? "repo " : "dir  ")
        let display = folder.replacingOccurrences(of: home, with: "~")
        print(String(format: "  %3d  %6.2f  %5d  %@  %@", r, finalScore, v.files, kind, display))
        r += 1
    }
    print("\n\(total) recently-used files → \(agg.count) candidate folders. Half-life \(Int(halfLifeDays))d, lookback \(Int(lookbackDays))d.")
    print("kind: repo = rolled up to a .git root · dir = plain folder · trans = transient (down-weighted ×\(downWeight))")
    CFRunLoopStop(CFRunLoopGetCurrent())
}

guard query.start() else {
    FileHandle.standardError.write(Data("Failed to start NSMetadataQuery\n".utf8)); exit(1)
}
let timeout = Timer(timeInterval: 60, repeats: false) { _ in
    print("Timed out."); CFRunLoopStop(CFRunLoopGetCurrent())
}
RunLoop.current.add(timeout, forMode: .common)
CFRunLoopRun()
