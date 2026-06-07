import Foundation

/// Jump-database signal source (zoxide / z / autojump). These tools already keep a
/// curated, frecency-ranked map of the directories you actually visit — a far higher
/// signal-to-noise warm seed than re-parsing raw shell history, and a direct match
/// for Haunts' own frecency model.
///
/// As with `ShellHistory`, the PARSE (text → path+score) is pure and unit-tested;
/// only `JumpSource` touches the filesystem / shells out. All three formats are
/// plain text:
///   - zoxide:   `zoxide query --list --score` → "  NNN.N /abs/path" (score, path).
///   - z (rupa): "path|rank|last_access_epoch" (pipe-delimited; rank = score).
///   - autojump: "weight\tpath" (tab-delimited).
/// Every parser is never-throw and fail-silent: malformed/blank lines are skipped,
/// non-absolute paths are ignored.
public enum JumpDatabases {
    /// Parse `zoxide query --list --score` output. Each line is leading whitespace,
    /// a float score, a run of whitespace, then the absolute path (which may itself
    /// contain spaces). Output: path → score.
    public static func parseZoxide(_ text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let sp = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            guard let score = Double(line[..<sp]) else { continue }
            let path = String(line[sp...]).trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/") else { continue }
            out[path] = score
        }
        return out
    }

    /// Parse a rupa/z data file: "path|rank|last_access_epoch" (pipe-delimited).
    /// `rank` is the frecency score. Output: path → rank.
    public static func parseZ(_ text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = String(raw).components(separatedBy: "|")
            guard parts.count >= 2 else { continue }
            let path = parts[0]
            guard path.hasPrefix("/"), let rank = Double(parts[1]) else { continue }
            out[path] = rank
        }
        return out
    }

    /// Parse an autojump data file: "weight\tpath" (tab-delimited). `weight` is the
    /// score. Output: path → weight.
    public static func parseAutojump(_ text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            guard let tab = line.firstIndex(of: "\t") else { continue }
            guard let weight = Double(line[..<tab]) else { continue }
            let path = String(line[line.index(after: tab)...])
            guard path.hasPrefix("/") else { continue }
            out[path] = weight
        }
        return out
    }
}

/// Impure jump-database reader. Locates whichever of the z/autojump text files exist
/// and (best-effort, off the launch hot path) shells out to the `zoxide` CLI, parses
/// them (pure), and returns raw absolute-path → score. Directory resolution and
/// git-root rollup are left to `AppState`. Reads local files only; nothing leaves the
/// Mac. Fail-silent on missing files / absent CLI.
public struct JumpSource: Sendable {
    /// rupa/z data file (`$_Z_DATA`, default `~/.z`).
    public let zURL: URL
    /// autojump data file (default `~/.local/share/autojump/autojump.txt`).
    public let autojumpURL: URL
    /// zoxide data dir (`$_ZO_DATA_DIR`); passed through to the `zoxide` subprocess so
    /// its CLI reads the same DB. nil → zoxide uses its own default.
    public let zoxideDataDir: String?

    public init(env: [String: String] = ProcessInfo.processInfo.environment,
                home: String = NSHomeDirectory()) {
        let h = URL(fileURLWithPath: home)
        if let z = env["_Z_DATA"], !z.isEmpty {
            self.zURL = URL(fileURLWithPath: z)
        } else {
            self.zURL = h.appendingPathComponent(".z")
        }
        self.autojumpURL = h.appendingPathComponent(".local/share/autojump/autojump.txt")
        let zo = env["_ZO_DATA_DIR"]
        self.zoxideDataDir = (zo?.isEmpty == false) ? zo : nil
    }

    /// Test/explicit seam.
    public init(zURL: URL, autojumpURL: URL, zoxideDataDir: String? = nil) {
        self.zURL = zURL
        self.autojumpURL = autojumpURL
        self.zoxideDataDir = zoxideDataDir
    }

    /// Synchronous warm-seed weights from the plain-text DBs (z + autojump). Missing
    /// or unreadable files are skipped; scores from both are summed per path. The
    /// zoxide CLI is read separately via `zoxideWeights()` so it never blocks launch.
    public func weights() -> [String: Double] {
        var combined: [String: Double] = [:]
        func merge(_ d: [String: Double]) { for (p, w) in d { combined[p, default: 0] += w } }
        if let t = try? String(contentsOf: zURL, encoding: .utf8) { merge(JumpDatabases.parseZ(t)) }
        if let t = try? String(contentsOf: autojumpURL, encoding: .utf8) { merge(JumpDatabases.parseAutojump(t)) }
        return combined
    }

    /// Best-effort zoxide read via its public CLI (`zoxide query --list --score`).
    /// Guarded behind CLI existence; returns empty if zoxide isn't installed or the
    /// invocation fails. Blocking (runs a subprocess) — call OFF the main actor, like
    /// Spotlight's async enrichment.
    public func zoxideWeights() -> [String: Double] {
        guard let exe = Self.locateZoxide() else { return [:] }
        let p = Process()
        p.executableURL = exe
        p.arguments = ["query", "--list", "--score"]
        var env = ProcessInfo.processInfo.environment
        if let d = zoxideDataDir { env["_ZO_DATA_DIR"] = d }
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0, let s = String(data: data, encoding: .utf8) else { return [:] }
            return JumpDatabases.parseZoxide(s)
        } catch {
            return [:]
        }
    }

    /// Locate the `zoxide` executable. GUI apps launched by launchd inherit a minimal
    /// PATH, so probe the usual install locations rather than relying on `env`.
    static func locateZoxide() -> URL? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/zoxide", "/usr/local/bin/zoxide",
            NSHomeDirectory() + "/.cargo/bin/zoxide", "/usr/bin/zoxide",
        ]
        for c in candidates where fm.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        return nil
    }
}
