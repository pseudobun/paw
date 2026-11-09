import Foundation

/// Scores how well a query matches a text: whole substrings beat scattered letters,
/// matches at word starts and at the beginning beat ones in the middle. Case and
/// diacritics are ignored ("cafe" finds "Café"). Every space-separated query word has to match.
public enum FuzzyMatcher {
    public static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// nil when the text doesn't match.
    public static func score(_ query: String, in text: String) -> Int? {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        let hay = Array(fold(text))
        guard !hay.isEmpty else { return nil }
        var total = 0
        for w in words {
            guard let s = wordScore(Array(w), hay) else { return nil }
            total += s
        }
        // Shorter texts are a tighter match for the same letters.
        return total - min(hay.count, 60) / 4
    }

    static func isBoundary(_ hay: [Character], _ i: Int) -> Bool {
        if i == 0 { return true }
        let prev = hay[i - 1], cur = hay[i]
        if !prev.isLetter && !prev.isNumber { return true }
        return prev.isLowercase && cur.isUppercase
    }

    static func wordScore(_ needle: [Character], _ hay: [Character]) -> Int? {
        guard needle.count <= hay.count else { return nil }
        // Substring: best at a word boundary, earliest otherwise.
        var best: Int? = nil
        var i = 0
        while i + needle.count <= hay.count {
            if hay[i] == needle[0], Array(hay[i..<(i + needle.count)]) == needle {
                var s = 100 + needle.count * 12
                if i == 0 { s += 60 } else if isBoundary(hay, i) { s += 40 }
                if needle.count == hay.count { s += 80 }
                s -= min(i, 30)
                best = max(best ?? s, s)
            }
            i += 1
        }
        if let best { return best }
        // Subsequence: every letter in order, rewarding runs and word starts.
        var s = 0, h = 0, run = 0
        var first: Int? = nil
        for c in needle {
            var found: Int? = nil
            // Prefer the next word start that has this letter, if it comes before a long gap.
            var j = h
            while j < hay.count {
                if hay[j] == c { found = found ?? j; if isBoundary(hay, j) { if j - h < 12 { found = j }; break } }
                j += 1
            }
            guard let at = found else { return nil }
            if first == nil { first = at }
            if at == h, h > 0 { run += 1; s += 8 * run } else { run = 0; s -= min(at - h, 10) }
            if isBoundary(hay, at) { s += 12 }
            s += 6
            h = at + 1
        }
        return s - min(first ?? 0, 20)
    }

    /// Best weighted score over several fields (title, description, value…).
    public static func best(_ query: String, fields: [(text: String?, weight: Double)]) -> Int? {
        var best: Int? = nil
        for f in fields {
            guard let t = f.text, !t.isEmpty, let s = score(query, in: t) else { continue }
            let w = Int((Double(s) * f.weight).rounded())
            best = max(best ?? w, w)
        }
        return best
    }
}
