import Foundation

/// `~/.config/paw/config.json5`. Every key is optional; a missing key keeps its default.
public struct PawConfig: Codable, Equatable, Sendable {
    public var yabai = Yabai()
    public var indicator = Indicator()
    public var appearance = Appearance()
    public var icons = Icons()
    /// Apps (names) whose windows never get an indicator cell.
    public var excludedApps: [String] = []
    /// Start paw when you log in (only for the installed paw.app).
    public var openAtLogin = false

    public init() {}

    public struct Yabai: Codable, Equatable, Sendable {
        public var path = "/opt/homebrew/bin/yabai"
        /// Add yabai signals (label paw_*) that run `paw refresh` on window and space changes.
        public var signals = true
        /// Also refresh every N seconds as a safety net; 0 = only on signals.
        public var pollSeconds = 5.0
        /// Window frames within this many points count as the same stack.
        public var fuzz = 30.0
        public init() {}
    }

    public struct Indicator: Codable, Equatable, Sendable {
        /// "auto" (outside, on the side nearer the screen edge, like stackline), "left", "right",
        /// "insideLeft", "insideRight".
        public var side = IndicatorLayout.Side.auto
        public var offsetX = 4.0
        public var offsetY = 2.0
        public var width = 28.0
        public var cellHeight = 22.0
        public var gap = 2.0
        public var padding = 3.0
        /// Island with the window's title next to the hovered icon: "hover" or "never".
        public var titles = "hover"
        /// Click an icon to focus its window.
        public var clickToFocus = true
        /// Scroll over the indicator to go through the stack.
        public var scrollToCycle = true
        /// Opacity of indicators of stacks that don't have focus.
        public var unfocusedOpacity = 0.6
        public var fadeMs = 150.0
        public init() {}

        public var metrics: IndicatorLayout.Metrics {
            .init(width: width, cellHeight: cellHeight, gap: gap, padding: padding, offsetX: offsetX, offsetY: offsetY)
        }
    }

    public struct Appearance: Codable, Equatable, Sendable {
        /// Titles; falls back to SF Mono.
        public var font = "GeistMono Nerd Font"
        public var fontSize = 12.0
        /// App icons: sketchybar-app-font ligatures, like the bar.
        public var appFont = "sketchybar-app-font"
        public var appIconSize = 14.0
        /// Island corners (sketchybar islands: 9) and the highlighted cell (sketchybar spaces: 7).
        public var radius = 9.0
        public var cellRadius = 7.0
        public var borderWidth = 1.0
        public var shadow = true
        public var colors = Colors()
        public init() {}
    }

    /// sketchybar palette (~/.config/sketchybar/colors.lua), shared with olympus-dashboard and hop.
    public struct Colors: Codable, Equatable, Sendable {
        public var island = ARGB(0xeb1d_1d16)
        public var islandHi = ARGB(0xff2b_2b22)
        public var border = ARGB(0x1aff_ffff)
        public var fg = ARGB(0xfffb_fbf9)
        public var muted = ARGB(0xffab_ab9c)
        public var dim = ARGB(0xff5f_5f52)
        /// The focused window's icon.
        public var accent = ARGB(0xffea_d186)
        public var wave = ARGB(0xff86_98eb)
        public var good = ARGB(0xff43_d58f)
        public var bad = ARGB(0xffff_6467)
        public init() {}
    }

    public struct Icons: Codable, Equatable, Sendable {
        /// sketchybar's icon map; the copy built into paw is used when it is missing.
        public var map = "~/.config/sketchybar/helpers/app_icons.lua"
        /// App name → ligature, e.g. { "MyApp": ":code:" }.
        public var overrides: [String: String] = [:]
        public init() {}
    }
}

// MARK: - Decoding with defaults

/// Decodes `key` if present, otherwise keeps the default.
struct Fields<K: CodingKey> {
    let c: KeyedDecodingContainer<K>
    func callAsFunction<T: Decodable>(_ key: K, _ value: inout T) throws {
        if let v = try c.decodeIfPresent(T.self, forKey: key) { value = v }
    }
}

extension PawConfig {
    enum CodingKeys: String, CodingKey, CaseIterable { case yabai, indicator, appearance, icons, excludedApps, openAtLogin }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.yabai, &yabai); try f(.indicator, &indicator); try f(.appearance, &appearance)
        try f(.icons, &icons); try f(.excludedApps, &excludedApps); try f(.openAtLogin, &openAtLogin)
    }
}

extension PawConfig.Yabai {
    enum CodingKeys: String, CodingKey, CaseIterable { case path, signals, pollSeconds, fuzz }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.path, &path); try f(.signals, &signals); try f(.pollSeconds, &pollSeconds); try f(.fuzz, &fuzz)
    }
}

extension PawConfig.Indicator {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case side, offsetX, offsetY, width, cellHeight, gap, padding, titles, clickToFocus, scrollToCycle, unfocusedOpacity, fadeMs
    }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.side, &side); try f(.offsetX, &offsetX); try f(.offsetY, &offsetY); try f(.width, &width)
        try f(.cellHeight, &cellHeight); try f(.gap, &gap); try f(.padding, &padding); try f(.titles, &titles)
        try f(.clickToFocus, &clickToFocus); try f(.scrollToCycle, &scrollToCycle)
        try f(.unfocusedOpacity, &unfocusedOpacity); try f(.fadeMs, &fadeMs)
    }
}

extension PawConfig.Appearance {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case font, fontSize, appFont, appIconSize, radius, cellRadius, borderWidth, shadow, colors
    }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.font, &font); try f(.fontSize, &fontSize); try f(.appFont, &appFont); try f(.appIconSize, &appIconSize)
        try f(.radius, &radius); try f(.cellRadius, &cellRadius); try f(.borderWidth, &borderWidth); try f(.shadow, &shadow)
        try f(.colors, &colors)
    }
}

extension PawConfig.Colors {
    enum CodingKeys: String, CodingKey, CaseIterable { case island, islandHi, border, fg, muted, dim, accent, wave, good, bad }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.island, &island); try f(.islandHi, &islandHi); try f(.border, &border); try f(.fg, &fg); try f(.muted, &muted)
        try f(.dim, &dim); try f(.accent, &accent); try f(.wave, &wave); try f(.good, &good); try f(.bad, &bad)
    }
}

extension PawConfig.Icons {
    enum CodingKeys: String, CodingKey, CaseIterable { case map, overrides }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.map, &map); try f(.overrides, &overrides)
    }
}

extension IndicatorLayout.Side {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        let key = s.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").lowercased()
        guard let v = Self.allCases.first(where: { $0.rawValue.lowercased() == key }) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "“\(s)” is not auto, left, right, insideLeft or insideRight")
        }
        self = v
    }
}

// MARK: - Loading and checking

public struct ConfigProblem: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum ConfigLoader {
    public static func decode(_ data: Data) throws -> PawConfig {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0a || $0 == 0x09 || $0 == 0x0d }) { return PawConfig() }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        do {
            return try decoder.decode(PawConfig.self, from: data)
        } catch let DecodingError.dataCorrupted(ctx) {
            throw ConfigProblem(describe(ctx, fallback: "not valid JSON5"))
        } catch let DecodingError.typeMismatch(type, ctx) {
            throw ConfigProblem(describe(ctx, fallback: "expected \(type)"))
        } catch let DecodingError.valueNotFound(type, ctx) {
            throw ConfigProblem(describe(ctx, fallback: "missing \(type)"))
        } catch {
            throw ConfigProblem(error.localizedDescription)
        }
    }

    static func describe(_ ctx: DecodingError.Context, fallback: String) -> String {
        let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
        var detail = ctx.debugDescription
        if let underlying = ctx.underlyingError as NSError?, let d = underlying.userInfo[NSDebugDescriptionErrorKey] as? String {
            detail = d
        }
        if detail.isEmpty || detail.hasPrefix("The given data was not valid JSON") { detail = fallback }
        return path.isEmpty ? detail : "\(path): \(detail)"
    }

    /// Keys paw doesn't know (typos), as dotted paths.
    public static func unknownKeys(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] else { return [] }
        var out: [String] = []
        let sections: [String: Set<String>] = [
            "yabai": Set(PawConfig.Yabai.CodingKeys.allCases.map(\.rawValue)),
            "indicator": Set(PawConfig.Indicator.CodingKeys.allCases.map(\.rawValue)),
            "appearance": Set(PawConfig.Appearance.CodingKeys.allCases.map(\.rawValue)),
            "icons": Set(PawConfig.Icons.CodingKeys.allCases.map(\.rawValue)),
        ]
        let top = Set(PawConfig.CodingKeys.allCases.map(\.rawValue))
        let colorKeys = Set(PawConfig.Colors.CodingKeys.allCases.map(\.rawValue))
        for (k, v) in root.sorted(by: { $0.key < $1.key }) {
            guard top.contains(k) else { out.append(k); continue }
            guard let known = sections[k], let dict = v as? [String: Any] else { continue }
            for (sk, sv) in dict.sorted(by: { $0.key < $1.key }) {
                if !known.contains(sk) { out.append("\(k).\(sk)"); continue }
                if k == "appearance", sk == "colors", let colors = sv as? [String: Any] {
                    for ck in colors.keys.sorted() where !colorKeys.contains(ck) { out.append("appearance.colors.\(ck)") }
                }
            }
        }
        return out
    }

    /// Problems a valid file can still have.
    public static func warnings(_ c: PawConfig) -> [String] {
        var w: [String] = []
        if !["hover", "never"].contains(c.indicator.titles) { w.append("indicator.titles: “\(c.indicator.titles)” is not hover or never") }
        if c.indicator.width < 8 || c.indicator.cellHeight < 8 { w.append("indicator.width and cellHeight need at least 8") }
        if !FileManager.default.isExecutableFile(atPath: (c.yabai.path as NSString).expandingTildeInPath) {
            w.append("yabai.path: \(c.yabai.path) is not executable")
        }
        return w
    }
}
