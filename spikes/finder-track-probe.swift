// Spike (bf7) — can we reliably read Finder's current folder via Apple Events on Tahoe?
// Polls two signals every 2s and prints what each returns, so we can judge:
//   1. reliability (does it return a real path, or errors?)
//   2. which signal is better: `insertion location` vs `target of front window`
//   3. the permission UX (the FIRST call triggers the Automation consent dialog)
//
// Run: swift spikes/finder-track-probe.swift   (then navigate Finder around)
import Foundation
import AppKit

func runFinder(_ body: String) -> String {
    let src = "tell application \"Finder\"\n\(body)\nend tell"
    guard let script = NSAppleScript(source: src) else { return "<nil-script>" }
    var err: NSDictionary?
    let out = script.executeAndReturnError(&err)
    if let err {
        let n = err[NSAppleScript.errorNumber] as? Int ?? 0
        let m = err[NSAppleScript.errorMessage] as? String ?? "?"
        return "<ERR \(n): \(m)>"   // -1743 = not permitted (Automation denied)
    }
    return out.stringValue ?? "<no-string>"
}

let insertionScript = """
try
  return POSIX path of (insertion location as alias)
on error e number n
  return "ERR " & n & ": " & e
end try
"""

let frontWindowScript = """
try
  if (count of Finder windows) is 0 then return "<no-finder-window>"
  return POSIX path of (target of front Finder window as alias)
on error e number n
  return "ERR " & n & ": " & e
end try
"""

FileHandle.standardError.write(Data("probe: navigating Finder for ~60s; first tick should prompt for Automation consent\n".utf8))

var lastInsertion = ""
var lastFront = ""
for tick in 0..<20 {                       // ~40s (Ctrl-C early once you see it follow you)
    let insertion = runFinder(insertionScript)
    let front = runFinder(frontWindowScript)
    let insMark = insertion != lastInsertion ? " *changed*" : ""
    let frMark = front != lastFront ? " *changed*" : ""
    print("[\(tick)] insertion=\(insertion)\(insMark)")
    print("     front=\(front)\(frMark)")
    fflush(stdout)
    lastInsertion = insertion
    lastFront = front
    Thread.sleep(forTimeInterval: 2)
}
print("probe done.")
