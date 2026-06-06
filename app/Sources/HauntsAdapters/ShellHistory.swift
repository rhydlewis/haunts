import Foundation

/// Shell-history signal source. The PARSE (text → paths+counts) is pure and
/// unit-tested; only `read()` touches the filesystem.
///
/// Ported from `spikes/seed-prototype.py` (`harvest_paths_from_text` + the fish/zsh
/// loops): from each command we harvest an explicit `cd`/`z`/`j`/`pushd` target plus
/// any absolute or `~`-relative path token, and from fish's `paths:` blocks the
/// listed entries. Output is raw path string → occurrence count; expansion of `~`,
/// directory resolution, and git-root rollup happen in the impure caller.
public enum ShellHistory {
    /// Harvest candidate path tokens from a single command line.
    /// Mirrors the prototype: the `cd`-family argument (whole rest of line, quotes
    /// stripped) plus every `~?/…` token not broken by whitespace/quotes/`|;&`.
    static func harvest(from command: String) -> [String] {
        var out: [String] = []
        if let m = command.range(of: #"^\s*(?:cd|z|j|pushd)\s+(.+)"#, options: .regularExpression) {
            // Capture group 1 is everything after the verb; re-extract it.
            let tail = String(command[m]).replacingOccurrences(
                of: #"^\s*(?:cd|z|j|pushd)\s+"#, with: "", options: .regularExpression)
            let trimmed = tail.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        let tokenPattern = #"~?/[^\s'"|;&]+"#
        let ns = command as NSString
        if let re = try? NSRegularExpression(pattern: tokenPattern) {
            for m in re.matches(in: command, range: NSRange(location: 0, length: ns.length)) {
                out.append(ns.substring(with: m.range))
            }
        }
        return out
    }

    /// Parse fish_history (its YAML-ish format): `- cmd:` lines feed `harvest`, and
    /// indented `- /path` entries (the `paths:` lists) are taken verbatim.
    public static func parseFish(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let r = line.range(of: #"^- cmd:\s+"#, options: .regularExpression) {
                for p in harvest(from: String(line[r.upperBound...])) { counts[p, default: 0] += 1 }
            } else if let r = line.range(of: #"^\s+- "#, options: .regularExpression) {
                let p = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !p.isEmpty { counts[p, default: 0] += 1 }
            }
        }
        return counts
    }

    /// Parse a zsh history file. Lines may carry an extended-history prefix
    /// (`: <start>:<elapsed>;<cmd>`) which we strip before harvesting.
    public static func parseZsh(_ text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let cmd = String(raw).replacingOccurrences(
                of: #"^: \d+:\d+;"#, with: "", options: .regularExpression)
            for p in harvest(from: cmd) { counts[p, default: 0] += 1 }
        }
        return counts
    }
}

/// Impure shell-history reader. Reads fish + zsh history if present, parses them
/// (pure), expands `~`, and returns raw absolute-path → count. Directory
/// resolution and git-root rollup are left to `AppState`.
public struct ShellHistorySource: Sendable {
    public let fishURL: URL
    public let zshURL: URL

    public init(home: String = NSHomeDirectory()) {
        let h = URL(fileURLWithPath: home)
        self.fishURL = h.appendingPathComponent(".local/share/fish/fish_history")
        self.zshURL = h.appendingPathComponent(".zsh_history")
    }

    public init(fishURL: URL, zshURL: URL) {
        self.fishURL = fishURL
        self.zshURL = zshURL
    }

    /// Read whatever history files exist and return raw path → occurrence count.
    /// `~`-prefixed tokens are expanded to `home`. Missing/unreadable files are skipped.
    public func paths(home: String = NSHomeDirectory()) -> [String: Int] {
        var combined: [String: Int] = [:]
        func merge(_ counts: [String: Int]) {
            for (raw, c) in counts {
                let expanded = raw.hasPrefix("~") ? home + raw.dropFirst(1) : raw
                combined[String(expanded), default: 0] += c
            }
        }
        if let t = try? String(contentsOf: fishURL, encoding: .utf8) { merge(ShellHistory.parseFish(t)) }
        if let t = try? String(contentsOf: zshURL, encoding: .utf8) { merge(ShellHistory.parseZsh(t)) }
        return combined
    }
}
