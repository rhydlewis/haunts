import Testing
import Foundation
@testable import HauntsAdapters

struct JumpDatabasesParseTests {

    // zoxide: "  NNN.N /abs/path" — leading score, whitespace, path.
    @Test func parsesZoxideScoreAndPath() {
        let text = """
          142.5 /Users/x/code/proj
        9.0 /Users/x/work
        """
        let out = JumpDatabases.parseZoxide(text)
        #expect(out["/Users/x/code/proj"] == 142.5)
        #expect(out["/Users/x/work"] == 9.0)
    }

    // zoxide: a path containing spaces keeps them; the score is only the first field.
    @Test func parsesZoxidePathWithSpaces() {
        let out = JumpDatabases.parseZoxide("  3.2 /Users/x/My Project")
        #expect(out["/Users/x/My Project"] == 3.2)
    }

    // zoxide: blank lines, non-numeric scores, and relative/non-absolute paths are skipped.
    @Test func zoxideSkipsMalformedLines() {
        let text = """

        notanumber /Users/x/a
        12.0 relative/path
        7.0 /Users/x/ok
        garbage-with-no-space
        """
        let out = JumpDatabases.parseZoxide(text)
        #expect(out == ["/Users/x/ok": 7.0])
    }

    // z (rupa): "path|rank|last_access_epoch" — rank is the score.
    @Test func parsesZPipeFormat() {
        let text = """
        /Users/x/code/proj|18.5|1698595797
        /Users/x/work|3|1698595803
        """
        let out = JumpDatabases.parseZ(text)
        #expect(out["/Users/x/code/proj"] == 18.5)
        #expect(out["/Users/x/work"] == 3)
    }

    // z: lines without enough fields, bad ranks, or non-absolute paths are skipped.
    @Test func zSkipsMalformedLines() {
        let text = """
        /Users/x/nofields
        relative|5|1
        /Users/x/badrank|notanumber|1
        /Users/x/ok|9.0|123

        """
        let out = JumpDatabases.parseZ(text)
        #expect(out == ["/Users/x/ok": 9.0])
    }

    // autojump: "weight\tpath" (tab-delimited).
    @Test func parsesAutojumpTabFormat() {
        let text = "10.5\t/Users/x/code/proj\n2.0\t/Users/x/work"
        let out = JumpDatabases.parseAutojump(text)
        #expect(out["/Users/x/code/proj"] == 10.5)
        #expect(out["/Users/x/work"] == 2.0)
    }

    // autojump: no-tab lines, bad weights, and non-absolute paths are skipped.
    @Test func autojumpSkipsMalformedLines() {
        let text = """
        notabhere /Users/x/a
        bad\t/Users/x/b
        5.0\trelative/path
        8.0\t/Users/x/ok

        """
        let out = JumpDatabases.parseAutojump(text)
        #expect(out == ["/Users/x/ok": 8.0])
    }

    // Empty input is stable for all three parsers.
    @Test func emptyInputIsStable() {
        #expect(JumpDatabases.parseZoxide("").isEmpty)
        #expect(JumpDatabases.parseZ("").isEmpty)
        #expect(JumpDatabases.parseAutojump("").isEmpty)
    }
}

struct JumpSourceTests {
    private func tempFile(_ contents: String, _ name: String) -> (URL, () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("JumpDB-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? contents.data(using: .utf8)!.write(to: url)
        return (url, { try? FileManager.default.removeItem(at: dir) })
    }

    // $_Z_DATA overrides the default ~/.z location.
    @Test func honorsZDataEnvOverride() {
        let src = JumpSource(env: ["_Z_DATA": "/custom/z/data"], home: "/Users/x")
        #expect(src.zURL.path == "/custom/z/data")
    }

    // $_ZO_DATA_DIR is captured and (functionally) passed through to the zoxide CLI.
    @Test func honorsZoxideDataDirEnvOverride() {
        let src = JumpSource(env: ["_ZO_DATA_DIR": "/custom/zo"], home: "/Users/x")
        #expect(src.zoxideDataDir == "/custom/zo")
    }

    // With no env overrides, paths default under home; empty env vars are ignored.
    @Test func defaultsUnderHomeWhenNoOverride() {
        let src = JumpSource(env: ["_Z_DATA": "", "_ZO_DATA_DIR": ""], home: "/Users/x")
        #expect(src.zURL.path == "/Users/x/.z")
        #expect(src.autojumpURL.path == "/Users/x/.local/share/autojump/autojump.txt")
        #expect(src.zoxideDataDir == nil)
    }

    // Reads both text DBs and sums their per-path scores.
    @Test func readsAndMergesZAndAutojump() {
        let (z, c1) = tempFile("/Users/x/code/proj|4.0|1\n", "z")
        defer { c1() }
        let (aj, c2) = tempFile("6.0\t/Users/x/code/proj\n1.0\t/Users/x/other\n", "autojump.txt")
        defer { c2() }
        let src = JumpSource(zURL: z, autojumpURL: aj)
        let w = src.weights()
        #expect(w["/Users/x/code/proj"] == 10.0)  // 4.0 (z) + 6.0 (autojump)
        #expect(w["/Users/x/other"] == 1.0)
    }

    // Missing files yield empty weights without throwing.
    @Test func missingFilesYieldEmpty() {
        let src = JumpSource(
            zURL: URL(fileURLWithPath: "/nonexistent/z"),
            autojumpURL: URL(fileURLWithPath: "/nonexistent/autojump.txt"))
        #expect(src.weights().isEmpty)
    }
}
