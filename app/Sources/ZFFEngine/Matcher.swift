import Foundation

/// Separator-insensitive subsequence matching. `norm` is what makes
/// `z for` match `z-for-finder`: both collapse to alphanumerics only.
public enum Matcher {
    /// Lowercase and strip everything but alphanumerics.
    public static func norm(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Is `q` a (left-to-right) subsequence of `s`? Both should already be normalized.
    public static func isSubseq(_ q: String, _ s: String) -> Bool {
        var i = q.startIndex
        for c in s where i < q.endIndex && c == q[i] { i = q.index(after: i) }
        return i == q.endIndex
    }
}
