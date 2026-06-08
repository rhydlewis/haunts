import Foundation

/// Pure, unit-tested policy for the live `FinderTracker` (spike bf7).
///
/// Splitting the decisions out here keeps the testable logic AppKit-free and
/// deterministic: CI can verify the filter and normalisation even though the
/// Apple Events poll that feeds them needs a GUI + Finder + consent and can't
/// run headless.
public enum NavigationFilter {

    /// Clean the raw POSIX path Finder hands back: trim whitespace and drop the
    /// trailing slash it appends to folder paths, so `/a/b/` and `/a/b` dedupe as
    /// one place. Returns `nil` for empty or non-absolute input. Root stays "/".
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("/") else { return nil }
        if trimmed == "/" { return "/" }
        var path = trimmed
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Whether a navigated folder is worth learning from. We skip system and
    /// transient locations the ranking layer shouldn't be biased by: a system/app
    /// `Library` component (covers both `/Library` and `~/Library`), `/Applications`,
    /// and any hidden/dotfile component (`.git`, `.config`, …). The engine already
    /// down-weights transient dirs, but keeping this noise out of the store entirely
    /// keeps the learned signal clean. Expects an already-normalised absolute path.
    public static func shouldRecord(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/" else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }
        if components.contains(where: { $0.hasPrefix(".") }) { return false }
        if hasExcludedLibraryComponent(components) { return false }
        if components.first == "Applications" { return false }
        return true
    }

    /// Whether `components` contain a `Library` directory that's genuine system/app
    /// noise. macOS hides iCloud-synced files under `~/Library/Mobile Documents/`
    /// (iCloud Drive's `com~apple~CloudDocs`, plus app vaults like Obsidian's
    /// `iCloud~md~obsidian`) — those are real working folders, not noise. So a
    /// `Library` component only counts as excluded when it is NOT immediately
    /// followed by `Mobile Documents`. Shared by every ingestion layer (live
    /// navigation, shell-history, Spotlight metadata) so the carve-out is uniform.
    public static func hasExcludedLibraryComponent(_ components: [String]) -> Bool {
        for (i, c) in components.enumerated() where c == "Library" {
            let next = i + 1 < components.count ? components[i + 1] : nil
            if next != "Mobile Documents" { return true }
        }
        return false
    }

    /// Convenience overload: split an absolute path into components and apply
    /// `hasExcludedLibraryComponent`. For the substring-based callers that used to
    /// test `path.contains("/Library/")`.
    public static func hasExcludedLibraryComponent(path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return hasExcludedLibraryComponent(components)
    }
}
