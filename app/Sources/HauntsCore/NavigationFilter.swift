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
    /// transient locations the ranking layer shouldn't be biased by: anything with
    /// a `Library` component (covers both `/Library` and `~/Library`), `/Applications`,
    /// and any hidden/dotfile component (`.git`, `.config`, …). The engine already
    /// down-weights transient dirs, but keeping this noise out of the store entirely
    /// keeps the learned signal clean. Expects an already-normalised absolute path.
    public static func shouldRecord(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/" else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return false }
        if components.contains(where: { $0.hasPrefix(".") }) { return false }
        if components.contains("Library") { return false }
        if components.first == "Applications" { return false }
        return true
    }
}
