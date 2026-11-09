import Foundation

/// `~/.config/paw/config.json5`. Every key is optional; a missing key keeps its default,
/// so a config can be as small as `{ hint: { charset: "fjdksla" } }`.
public struct PawConfig: Codable, Equatable, Sendable {
    public var hint = Hint()
    public var search = Search()
    public var scroll = Scroll()
    public var appearance = Appearance()
    public var icons = Icons()
    /// Bundle ids or app names where paw's hotkeys do nothing.
    public var excludedApps: [String] = []
    /// Start paw when you log in (only for the installed paw.app).
    public var openAtLogin = false
    /// Seconds paw waits for an app's accessibility answer before skipping it.
    public var axTimeout = 0.25

    public init() {}

    public struct Hint: Codable, Equatable, Sendable {
        public var hotkey = "cmd+shift+space"
        /// Keys labels are made of, best keys first (home row by default).
        public var charset = "asdfghjkl;"
        /// Label the frontmost app's menu bar: "auto" (unless the menu bar hides), "on", "off".
        public var menuBar = Toggle.auto
        /// Label status items on the right of the menu bar.
        public var menuBarExtras = Toggle.off
        /// Label the Dock: "auto" (unless it hides), "on", "off".
        public var dock = Toggle.auto
        /// Typing the last key again within this many ms turns the click into a double click.
        public var doubleTapMs = 250
        /// Put the pointer back after a synthesized click.
        public var restoreCursor = true
        /// Upper bound on labels per activation.
        public var maxElements = 800
        /// Chromium browsers only expose web content with AXEnhancedUserInterface on, which
        /// can make window managers (yabai) skip animating their windows.
        public var enhancedUI = true
        public init() {}
    }

    public struct Search: Codable, Equatable, Sendable {
        public var hotkey = "cmd+shift+alt+space"
        /// Width of the search island in points.
        public var width = 440.0
        /// Labels shown for at most this many matches.
        public var maxResults = 40
        public init() {}
    }

    public struct Scroll: Codable, Equatable, Sendable {
        public var hotkey = "cmd+shift+j"
        /// Pixels per millisecond while a key is held.
        public var speed = 1.6
        /// Shift multiplies the speed ("dash").
        public var fastMultiplier = 3.0
        /// Milliseconds to reach full speed after a key goes down.
        public var rampMs = 140.0
        /// Seconds without a key before scroll mode closes; 0 keeps it open.
        public var idleTimeout = 5.0
        /// Flip directions if j scrolls up on your machine.
        public var invert = false
        public init() {}
    }

    public struct Appearance: Codable, Equatable, Sendable {
        public var font = "GeistMono Nerd Font"
        /// App icons: sketchybar-app-font ligatures.
        public var appFont = "sketchybar-app-font"
        public var fontSize = 11.0
        /// "regular", "medium", "semibold", "bold", "heavy".
        public var fontWeight = "bold"
        public var labelHeight = 18.0
        public var labelRadius = 6.0
        public var labelPaddingX = 5.0
        /// Where a label sits on its element: "topLeft", "left", "center".
        public var labelAnchor = LabelAnchor.topLeft
        public var islandHeight = 28.0
        public var islandRadius = 9.0
        /// Distance of the search/mode island from the top of the screen (below a 40 pt bar).
        public var islandTop = 46.0
        public var islandFontSize = 12.0
        public var appIconSize = 14.0
        public var borderWidth = 1.0
        public var shadow = true
        /// Fade of labels that stop matching, in ms.
        public var fadeMs = 80.0
        /// Opacity non-matching labels fade to (0 hides them).
        public var unmatchedOpacity = 0.0
        /// Show the island with the app icon and mode at the top while labels are up.
        public var appIsland = true
        public var colors = Colors()
        public init() {}
    }

    /// sketchybar palette (~/.config/sketchybar/colors.lua).
    public struct Colors: Codable, Equatable, Sendable {
        public var island = ARGB(0xeb1d_1d16)
        public var islandHi = ARGB(0xff2b_2b22)
        public var border = ARGB(0x1aff_ffff)
        public var fg = ARGB(0xfffb_fbf9)
        public var muted = ARGB(0xffab_ab9c)
        public var dim = ARGB(0xff5f_5f52)
        /// Typed prefix, app icon, selected match.
        public var accent = ARGB(0xffea_d186)
        /// Scroll area numbers.
        public var wave = ARGB(0xff86_98eb)
        public var good = ARGB(0xff43_d58f)
        /// No match, missing permission.
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

    public enum Toggle: String, Codable, Sendable {
        case auto, on, off

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = b ? .on : .off; return }
            let s = try c.decode(String.self).lowercased()
            switch s {
            case "auto": self = .auto
            case "on", "true", "yes": self = .on
            case "off", "false", "no": self = .off
            default: throw DecodingError.dataCorruptedError(in: c, debugDescription: "“\(s)” is not auto, on or off")
            }
        }
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
    enum CodingKeys: String, CodingKey, CaseIterable { case hint, search, scroll, appearance, icons, excludedApps, openAtLogin, axTimeout }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.hint, &hint); try f(.search, &search); try f(.scroll, &scroll); try f(.appearance, &appearance)
        try f(.icons, &icons); try f(.excludedApps, &excludedApps); try f(.openAtLogin, &openAtLogin); try f(.axTimeout, &axTimeout)
    }
}

extension PawConfig.Hint {
    enum CodingKeys: String, CodingKey, CaseIterable { case hotkey, charset, menuBar, menuBarExtras, dock, doubleTapMs, restoreCursor, maxElements, enhancedUI }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.hotkey, &hotkey); try f(.charset, &charset); try f(.menuBar, &menuBar); try f(.menuBarExtras, &menuBarExtras)
        try f(.dock, &dock); try f(.doubleTapMs, &doubleTapMs); try f(.restoreCursor, &restoreCursor); try f(.maxElements, &maxElements)
        try f(.enhancedUI, &enhancedUI)
    }
}

extension PawConfig.Search {
    enum CodingKeys: String, CodingKey, CaseIterable { case hotkey, width, maxResults }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.hotkey, &hotkey); try f(.width, &width); try f(.maxResults, &maxResults)
    }
}

extension PawConfig.Scroll {
    enum CodingKeys: String, CodingKey, CaseIterable { case hotkey, speed, fastMultiplier, rampMs, idleTimeout, invert }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.hotkey, &hotkey); try f(.speed, &speed); try f(.fastMultiplier, &fastMultiplier); try f(.rampMs, &rampMs)
        try f(.idleTimeout, &idleTimeout); try f(.invert, &invert)
    }
}

extension PawConfig.Appearance {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case font, appFont, fontSize, fontWeight, labelHeight, labelRadius, labelPaddingX, labelAnchor, islandHeight, islandRadius
        case islandTop, islandFontSize, appIconSize, borderWidth, shadow, fadeMs, unmatchedOpacity, appIsland, colors
    }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.font, &font); try f(.appFont, &appFont); try f(.fontSize, &fontSize); try f(.fontWeight, &fontWeight)
        try f(.labelHeight, &labelHeight); try f(.labelRadius, &labelRadius); try f(.labelPaddingX, &labelPaddingX)
        try f(.labelAnchor, &labelAnchor); try f(.islandHeight, &islandHeight); try f(.islandRadius, &islandRadius)
        try f(.islandTop, &islandTop); try f(.islandFontSize, &islandFontSize); try f(.appIconSize, &appIconSize)
        try f(.borderWidth, &borderWidth); try f(.shadow, &shadow); try f(.fadeMs, &fadeMs)
        try f(.unmatchedOpacity, &unmatchedOpacity); try f(.appIsland, &appIsland); try f(.colors, &colors)
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

    /// Keys paw doesn't know (typos), as dotted paths. Overrides and excludedApps take any key.
    public static func unknownKeys(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any] else { return [] }
        var out: [String] = []
        let sections: [String: Set<String>] = [
            "hint": Set(PawConfig.Hint.CodingKeys.allCases.map(\.rawValue)),
            "search": Set(PawConfig.Search.CodingKeys.allCases.map(\.rawValue)),
            "scroll": Set(PawConfig.Scroll.CodingKeys.allCases.map(\.rawValue)),
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

    /// Problems a valid file can still have: a hotkey that doesn't parse, too few label keys.
    public static func warnings(_ c: PawConfig) -> [String] {
        var w: [String] = []
        for (name, hk) in [("hint.hotkey", c.hint.hotkey), ("search.hotkey", c.search.hotkey), ("scroll.hotkey", c.scroll.hotkey)]
        where !hk.isEmpty && HotkeySpec.parse(hk) == nil {
            w.append("\(name): “\(hk)” is not a hotkey")
        }
        let specs = [c.hint.hotkey, c.search.hotkey, c.scroll.hotkey].compactMap(HotkeySpec.parse)
        if Set(specs).count != specs.count { w.append("two modes share the same hotkey") }
        if LabelGenerator.uniqueKeys(Array(c.hint.charset)).count < 2 { w.append("hint.charset needs at least two different keys") }
        return w
    }
}
