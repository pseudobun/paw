import Foundation

/// App name → sketchybar-app-font ligature (":safari:"), read from sketchybar's own
/// `helpers/app_icons.lua` so paw and the bar show the same glyph for every app.
public struct AppIconMap: Sendable, Equatable {
    public var exact: [String: String]
    public var prefix: [(String, String)]
    public var fallback: String

    public init(exact: [String: String] = [:], prefix: [(String, String)] = [], fallback: String = ":default:") {
        self.exact = exact
        self.prefix = prefix
        self.fallback = fallback
    }

    public static func == (a: AppIconMap, b: AppIconMap) -> Bool {
        a.exact == b.exact && a.fallback == b.fallback && a.prefix.map(\.0) == b.prefix.map(\.0)
            && a.prefix.map(\.1) == b.prefix.map(\.1)
    }

    /// Same lookup as `app_icons.get` in Lua: exact name, then name prefix, then the default.
    public func glyph(for app: String) -> String {
        mapped(app) ?? fallback
    }

    /// The app's own glyph, or nil when only the default one would show.
    public func mapped(_ app: String) -> String? {
        if let g = exact[app] { return g }
        for (p, g) in prefix where app.hasPrefix(p) { return g }
        return nil
    }

    /// Entries in `overrides` win over the map.
    public func merging(_ overrides: [String: String]) -> AppIconMap {
        var m = self
        for (k, v) in overrides { m.exact[k] = v }
        return m
    }

    /// Parses the generated Lua table: `["Name"] = ":glyph:",`, `{ "Prefix", ":glyph:" },`
    /// and `default = ":default:"`.
    public static func parse(lua: String) -> AppIconMap {
        var map = AppIconMap()
        var inPrefix = false
        for raw in lua.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.contains("prefix = {") { inPrefix = true }
            if let d = line.range(of: "default = \"") {
                let rest = line[d.upperBound...]
                if let end = rest.firstIndex(of: "\"") { map.fallback = String(rest[..<end]) }
            }
            let strings = quoted(line)
            if line.hasPrefix("[\""), strings.count >= 2 {
                if map.exact[strings[0]] == nil { map.exact[strings[0]] = strings[1] }
            } else if inPrefix, line.hasPrefix("{"), strings.count >= 2 {
                map.prefix.append((strings[0], strings[1]))
            }
        }
        return map
    }

    /// Lua double-quoted strings in a line, with `\"` and `\\` unescaped.
    static func quoted(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inside = false
        var escape = false
        for c in line {
            if inside {
                if escape { current.append(c); escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { out.append(current); current = ""; inside = false }
                else { current.append(c) }
            } else if c == "\"" {
                inside = true
            }
        }
        return out
    }

    /// The copy of sketchybar's map that ships with paw (`just icons` refreshes it).
    public static let bundled: AppIconMap = parse(lua: BundledAppIcons.lua)
}
