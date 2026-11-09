/// Hint labels: the shortest codes over a charset in which no code is a prefix of another,
/// so typing a full code always picks exactly one element. Leaves of a breadth-first tree:
/// with 10 keys, 10 elements get one letter each; 11 to 100 mix one- and two-letter codes.
public enum LabelGenerator {
    public static func labels(count: Int, charset: [Character]) -> [String] {
        let keys = uniqueKeys(charset)
        guard count > 0, keys.count >= 2 else { return [] }
        var codes = [""]
        var offset = 0
        // Expand the oldest (shortest) leaf until there are enough leaves.
        while codes.count - offset < count {
            let parent = codes[offset]
            offset += 1
            for k in keys { codes.append(parent + String(k)) }
        }
        return Array(codes[offset..<(offset + count)])
    }

    public static func labels(count: Int, charset: String) -> [String] {
        labels(count: count, charset: Array(charset))
    }

    /// Lowercased, in order, without repeats or whitespace.
    public static func uniqueKeys(_ charset: [Character]) -> [Character] {
        var seen = Set<Character>()
        var out: [Character] = []
        for c in charset {
            let l = Character(c.lowercased())
            if l.isWhitespace || seen.contains(l) { continue }
            seen.insert(l)
            out.append(l)
        }
        return out
    }
}

/// Typing state over a set of labels: each key narrows the visible ones, a complete code picks one.
public struct HintMatcher: Sendable {
    public enum Result: Equatable, Sendable {
        /// The prefix grew; these indices still match.
        case narrowed([Int])
        /// A whole label was typed.
        case matched(Int)
        /// No label starts with the prefix plus this key; the prefix is unchanged.
        case noMatch
    }

    public let labels: [String]
    public private(set) var typed = ""

    public init(labels: [String]) { self.labels = labels }

    public mutating func type(_ key: Character) -> Result {
        let candidate = typed + String(key).lowercased()
        let hits = labels.indices.filter { labels[$0].hasPrefix(candidate) }
        guard !hits.isEmpty else { return .noMatch }
        typed = candidate
        if hits.count == 1, labels[hits[0]] == candidate { return .matched(hits[0]) }
        return .narrowed(hits)
    }

    /// Removes the last typed key; returns the indices that match again.
    public mutating func backspace() -> [Int] {
        if !typed.isEmpty { typed.removeLast() }
        return visible
    }

    public mutating func reset() { typed = "" }

    public var visible: [Int] { labels.indices.filter { labels[$0].hasPrefix(typed) } }
}
