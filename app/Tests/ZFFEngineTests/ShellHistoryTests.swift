import Testing
import Foundation
@testable import HauntsAdapters

struct ShellHistoryParseTests {

    // A `cd` target is harvested (and the token regex sees it too → counted twice,
    // matching the prototype; relative scale is normalized away downstream).
    @Test func harvestsCdTarget() {
        let out = ShellHistory.harvest(from: "cd ~/code/foo")
        #expect(out.contains("~/code/foo"))
    }

    // Bare path tokens in any command are harvested.
    @Test func harvestsBarePathTokens() {
        let out = ShellHistory.harvest(from: "ls -la /Users/x/projects && cat ~/notes.md")
        #expect(out.contains("/Users/x/projects"))
        #expect(out.contains("~/notes.md"))
    }

    // Tokens stop at shell separators so we don't capture trailing junk.
    @Test func tokensStopAtSeparators() {
        let out = ShellHistory.harvest(from: "cat /a/b.txt|grep x")
        #expect(out.contains("/a/b.txt"))
        #expect(!out.contains { $0.contains("|") })
    }

    // Commands with no paths yield nothing.
    @Test func noPathsYieldsEmpty() {
        #expect(ShellHistory.harvest(from: "brew install pyenv").isEmpty)
    }

    // Fish format: cmd lines + a `paths:` list entry, with counts accumulating.
    @Test func parsesFishHistory() {
        let fish = """
        - cmd: cd ~/code/proj
          when: 1698595797
        - cmd: brew install x
          when: 1698595803
        - cmd: fish_add_path /opt/homebrew/bin
          when: 1698596046
          paths:
            - /opt/homebrew/bin
        - cmd: cd ~/code/proj
          when: 1698596055
        """
        let counts = ShellHistory.parseFish(fish)
        // ~/code/proj appears in two `cd` commands; each command counts it twice
        // (cd-target + token branch) → 4.
        #expect(counts["~/code/proj"] == 4)
        // /opt/homebrew/bin: once as a token in the fish_add_path command, once as the
        // paths: list entry → 2.
        #expect(counts["/opt/homebrew/bin"] == 2)
    }

    // Zsh extended-history prefix is stripped before harvesting.
    @Test func parsesZshHistoryStrippingPrefix() {
        let zsh = """
        : 1698595797:0;cd /Users/x/work
        brew
        : 1698595803:0;ls ~/Documents
        """
        let counts = ShellHistory.parseZsh(zsh)
        #expect(counts["/Users/x/work"] == 2)   // cd-target + token
        #expect(counts["~/Documents"] == 1)
    }

    // Bash: one command per line, harvested directly (no prefix).
    @Test func parsesBashHistoryPlainLines() {
        let bash = """
        cd /Users/x/work
        brew install pyenv
        ls ~/Documents
        """
        let counts = ShellHistory.parseBash(bash)
        #expect(counts["/Users/x/work"] == 2)   // cd-target + token
        #expect(counts["~/Documents"] == 1)
    }

    // Bash with HISTTIMEFORMAT set: each command is preceded by a `#<epoch>`
    // comment line, which must be skipped (never harvested as a path).
    @Test func parsesBashHistorySkippingEpochComments() {
        let bash = """
        #1698595797
        cd /Users/x/work
        #1698595803
        ls ~/Documents
        """
        let counts = ShellHistory.parseBash(bash)
        #expect(counts["/Users/x/work"] == 2)
        #expect(counts["~/Documents"] == 1)
        // The epoch comment lines contribute nothing.
        #expect(counts.keys.allSatisfy { !$0.contains("#") })
        #expect(counts.keys.allSatisfy { !$0.contains("1698595797") })
    }

    // Empty input is stable.
    @Test func emptyInputIsStable() {
        #expect(ShellHistory.parseFish("").isEmpty)
        #expect(ShellHistory.parseZsh("").isEmpty)
        #expect(ShellHistory.parseBash("").isEmpty)
    }
}

struct ShellHistorySourceTests {
    private func tempFile(_ contents: String, _ name: String) -> (URL, () -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ShellHist-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? contents.data(using: .utf8)!.write(to: url)
        return (url, { try? FileManager.default.removeItem(at: dir) })
    }

    // Reads both files, expands ~ to home, sums counts across them.
    @Test func readsAndExpandsTilde() {
        let (fish, c1) = tempFile("- cmd: cd ~/code/proj\n  when: 1\n", "fish_history")
        defer { c1() }
        let (zsh, c2) = tempFile("cd ~/code/proj\n", "zsh_history")
        defer { c2() }
        let src = ShellHistorySource(fishURL: fish, zshURL: zsh)
        let paths = src.paths(home: "/Users/x")
        // fish: 2 (cd+token), zsh: 2 (cd+token) → 4, all expanded.
        #expect(paths["/Users/x/code/proj"] == 4)
        #expect(paths.keys.allSatisfy { !$0.hasPrefix("~") })
    }

    // Missing files are skipped without crashing.
    @Test func missingFilesYieldEmpty() {
        let src = ShellHistorySource(
            fishURL: URL(fileURLWithPath: "/nonexistent/fish"),
            zshURL: URL(fileURLWithPath: "/nonexistent/zsh"))
        #expect(src.paths(home: "/Users/x").isEmpty)
    }

    // A wired bashURL contributes paths to the combined result, with ~ expanded.
    @Test func readsBashHistory() {
        let (fish, c1) = tempFile("- cmd: cd ~/code/proj\n  when: 1\n", "fish_history")
        defer { c1() }
        let (zsh, c2) = tempFile("", "zsh_history")
        defer { c2() }
        let (bash, c3) = tempFile("#1698595797\ncd ~/code/proj\n", "bash_history")
        defer { c3() }
        let src = ShellHistorySource(fishURL: fish, zshURL: zsh, bashURL: bash)
        let paths = src.paths(home: "/Users/x")
        // fish: 2 (cd+token), bash: 2 (cd+token) → 4; the #epoch line adds nothing.
        #expect(paths["/Users/x/code/proj"] == 4)
        #expect(paths.keys.allSatisfy { !$0.hasPrefix("~") })
    }
}
