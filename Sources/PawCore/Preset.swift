import Foundation

/// How windows sit in a workspace preset (`workspaces` in the config).
public struct WorkspacePreset: Codable, Equatable, Sendable {
    public struct Tile: Codable, Equatable, Sendable {
        /// App names (or /regex/) whose windows stack in this tile, in order.
        public var apps: [String]
        /// Relative size against the other tiles (default 1).
        public var size: Double?
        /// Only windows whose title contains this (or matches /regex/) land here.
        public var title: String?
        /// Shell command `initiate` runs when no window matches (instead of opening the app),
        /// e.g. `open -na Ghostty --args --working-directory=~/repos/paw`.
        public var launch: String?

        public init(apps: [String], size: Double? = nil, title: String? = nil, launch: String? = nil) {
            self.apps = apps
            self.size = size
            self.title = title
            self.launch = launch
        }

        enum CodingKeys: String, CodingKey, CaseIterable { case apps, size, title, launch }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
            size = try c.decodeIfPresent(Double.self, forKey: .size)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            launch = try c.decodeIfPresent(String.self, forKey: .launch)
        }

        public func matches(app: String, title t: String) -> Bool {
            guard apps.contains(where: { AppMatcher.matches($0, app) }) else { return false }
            if let title, !title.isEmpty { return PawConfig.Rule.text(title, t) }
            return true
        }
    }

    /// nil: the workspace keeps its layout (`layout.default` for a new one).
    public var layout: LayoutKind?
    public var axis: Axis = .horizontal
    public var tiles: [Tile] = []
    /// Display this workspace opens on: "main", "secondary" or a 1-based index.
    public var display: String?

    public init(layout: LayoutKind? = .bsp, axis: Axis = .horizontal, tiles: [Tile] = [], display: String? = nil) {
        self.layout = layout
        self.axis = axis
        self.tiles = tiles
        self.display = display
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case layout, axis, tiles, display }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.layout, &layout); try f(.axis, &axis); try f(.tiles, &tiles); try f(.display, &display)
    }

    /// The tile a window of `app` titled `title` belongs in. Tiles with a title come first, so
    /// `{ apps: ["Ghostty"], title: "paw" }` wins over a plain `{ apps: ["Ghostty"] }`.
    public func slot(for app: String, title: String = "") -> Int? {
        if let i = tiles.firstIndex(where: { $0.title?.isEmpty == false && $0.matches(app: app, title: title) }) { return i }
        return tiles.firstIndex { ($0.title ?? "").isEmpty && $0.matches(app: app, title: title) }
    }
}

/// App names in the config: plain names match exactly (any case), `/…/` is a regular expression.
public enum AppMatcher {
    public static func matches(_ pattern: String, _ app: String) -> Bool {
        if pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
            let re = String(pattern.dropFirst().dropLast())
            return app.range(of: re, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return pattern.caseInsensitiveCompare(app) == .orderedSame
    }
}

extension WorkspacePreset {
    /// The tiles as one line for a text field: tiles split by " | ", apps in a tile by ", ", a
    /// size as " *2" after the tile: `Brave Browser *2 | T3 Code (Beta)`.
    public var tilesText: String {
        get {
            tiles.map { t in
                t.apps.joined(separator: ", ") + (t.size.map { " *" + ($0 == $0.rounded() ? String(Int($0)) : String($0)) } ?? "")
            }.joined(separator: " | ")
        }
        set {
            // Keep title/launch of tiles whose apps didn't change.
            let old = tiles
            tiles = Self.parseTiles(newValue).map { t in
                var t = t
                if let o = old.first(where: { $0.apps == t.apps }) { t.title = o.title; t.launch = o.launch }
                return t
            }
        }
    }

    public static func parseTiles(_ text: String) -> [Tile] {
        text.split(separator: "|").compactMap { part in
            var s = part.trimmingCharacters(in: .whitespaces)
            var size: Double?
            if let star = s.lastIndex(of: "*"), let v = Double(s[s.index(after: star)...].trimmingCharacters(in: .whitespaces)) {
                size = v
                s = String(s[..<star]).trimmingCharacters(in: .whitespaces)
            }
            let apps = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return apps.isEmpty ? nil : Tile(apps: apps, size: size)
        }
    }
}
