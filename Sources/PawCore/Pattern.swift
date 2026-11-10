import Foundation

/// `/…/` patterns from the config, matched against text other apps control (window titles, app
/// names). A pattern like `^(a+)+$` backtracks exponentially, and the matches run on the main
/// thread, so each one is compiled once and stopped at a deadline instead of freezing paw.
public enum Pattern {
    /// Longest text a pattern is matched against; titles can be whole chat messages or URLs.
    public static let maxInput = 1024
    /// How long one match may run before it counts as no match.
    public static let deadline: TimeInterval = 0.02

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression?] = [:]

    /// The pattern inside `/…/`, or nil when `pattern` is plain text.
    public static func regexBody(_ pattern: String) -> String? {
        guard pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") else { return nil }
        return String(pattern.dropFirst().dropLast())
    }

    /// The compiled, case-insensitive expression; nil when it does not compile.
    public static func compiled(_ body: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[body] { return hit }
        if cache.count > 512 { cache.removeAll() }
        let re = try? NSRegularExpression(pattern: body, options: [.caseInsensitive])
        cache[body] = re
        return re
    }

    /// Whether `body` matches somewhere in `text`. A pattern that does not compile, or runs past
    /// the deadline, does not match.
    public static func matches(_ body: String, _ text: String) -> Bool {
        guard let re = compiled(body) else { return false }
        let s = text.count > maxInput ? String(text.prefix(maxInput)) : text
        let ns = s as NSString
        let end = Date().addingTimeInterval(deadline)
        var found = false
        re.enumerateMatches(in: s, options: [.reportProgress], range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            if m != nil {
                found = true
                stop.pointee = true
            } else if Date() > end {
                stop.pointee = true
            }
        }
        return found
    }
}

extension Int {
    /// `Int(d)` without the trap: NaN is 0 and values outside Int's range are clamped.
    public init(saturating d: Double) {
        if d.isNaN { self = 0 } else if d >= 9.2e18 { self = .max } else if d <= -9.2e18 { self = .min } else { self = Int(d) }
    }
}
