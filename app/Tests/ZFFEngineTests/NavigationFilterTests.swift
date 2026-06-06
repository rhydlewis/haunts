import Testing
import Foundation
@testable import HauntsCore

// Pure policy for the live FinderTracker (bead jrc / bf7): which navigated paths
// are worth recording, and how to normalise the raw POSIX path Finder returns.
// CI can exercise these even though the Apple Events poll itself cannot run headless.
struct NavigationFilterTests {

    // MARK: normalize — strip the trailing slash Finder appends to folder paths

    @Test func normalizeStripsTrailingSlash() {
        #expect(NavigationFilter.normalize("/Users/rhyd/code/") == "/Users/rhyd/code")
    }

    @Test func normalizeLeavesCleanPathUntouched() {
        #expect(NavigationFilter.normalize("/Users/rhyd/code") == "/Users/rhyd/code")
    }

    @Test func normalizeRejectsEmpty() {
        #expect(NavigationFilter.normalize("") == nil)
        #expect(NavigationFilter.normalize("   ") == nil)
    }

    @Test func normalizeRejectsRelative() {
        #expect(NavigationFilter.normalize("relative/path") == nil)
    }

    @Test func normalizeKeepsRootAsSingleSlash() {
        // "/" normalises to "/" (not empty); shouldRecord then drops it.
        #expect(NavigationFilter.normalize("/") == "/")
    }

    @Test func normalizeTrimsWhitespace() {
        #expect(NavigationFilter.normalize("  /Users/rhyd/code/  ") == "/Users/rhyd/code")
    }

    // MARK: shouldRecord — keep real working folders, drop system/transient noise

    @Test func recordsOrdinaryFolder() {
        #expect(NavigationFilter.shouldRecord("/Users/rhyd/code/z-for-finder"))
        #expect(NavigationFilter.shouldRecord("/Users/rhyd/Documents"))
        #expect(NavigationFilter.shouldRecord("/Volumes/Work/project"))
    }

    @Test func skipsApplications() {
        #expect(!NavigationFilter.shouldRecord("/Applications"))
        #expect(!NavigationFilter.shouldRecord("/Applications/Utilities"))
    }

    @Test func skipsSystemLibrary() {
        #expect(!NavigationFilter.shouldRecord("/Library"))
        #expect(!NavigationFilter.shouldRecord("/Library/Fonts"))
    }

    @Test func skipsUserLibrary() {
        // ~/Library has a "Library" component too — both should be skipped.
        #expect(!NavigationFilter.shouldRecord("/Users/rhyd/Library/Application Support"))
    }

    @Test func skipsDotfileComponents() {
        #expect(!NavigationFilter.shouldRecord("/Users/rhyd/.config"))
        #expect(!NavigationFilter.shouldRecord("/Users/rhyd/.config/nvim"))
        #expect(!NavigationFilter.shouldRecord("/Users/rhyd/code/.git"))
    }

    @Test func skipsRootAndEmpty() {
        #expect(!NavigationFilter.shouldRecord("/"))
        #expect(!NavigationFilter.shouldRecord(""))
    }

    @Test func skipsRelative() {
        #expect(!NavigationFilter.shouldRecord("relative/path"))
    }
}
