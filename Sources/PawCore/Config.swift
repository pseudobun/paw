import Foundation

/// `~/.config/paw/config.json5`. Every key is optional; a missing key keeps its default.
public struct PawConfig: Codable, Equatable, Sendable {
    public var layout = Layout()
    public var focus = Focus()
    public var animation = Animation()
    /// Key → command(s), e.g. "ctrl+left": "focus west". Replaces the defaults when set.
    public var bindings: [String: String] = Defaults.bindings
    /// Key maps for modes: while `mode <name>` is on, its keys come first ("escape": "mode exit").
    public var modes: [String: [String: String]] = Defaults.modes
    /// Workspace presets by name: layout and which apps go in which tile. Used when no setup in
    /// `setups` matches the connected displays.
    public var workspaces: [String: WorkspacePreset] = [:]
    /// Presets per display arrangement ("home": laptop + DELL + Gigabyte). The first setup whose
    /// `displays` match the connected displays replaces `workspaces`; paw switches by itself
    /// when displays come and go.
    public var setups: [String: Setup] = [:]
    public var rules: [Rule] = Defaults.rules
    public var indicator = Indicator()
    public var appearance = Appearance()
    public var icons = Icons()
    public var hooks = Hooks()
    /// `paw initiate`: open the preset apps and arrange every workspace.
    public var initiate = Initiate()
    /// Start paw when you log in (only for the installed paw.app).
    public var openAtLogin = false

    public init() {}

    public struct Layout: Codable, Equatable, Sendable {
        /// Layout of new workspaces: "bsp", "stack" or "float".
        public var `default` = LayoutKind.stack
        public var gap = 10.0
        public var padding = Padding()
        /// Extra space kept free at the top/bottom for a status bar such as sketchybar (like
        /// yabai's external_bar); the menu bar and Dock are already left out.
        public var barTop = 0.0
        public var barBottom = 0.0
        /// How many workspaces exist from the start (1…N); more come with `workspace new`.
        public var workspaces = 10
        /// Where `initiate` and setup switches put windows of apps no preset or rule places:
        /// a workspace name, or "" to leave them on the workspace they're on.
        public var unassignedWorkspace = ""
        public init() {}
    }

    public struct Focus: Codable, Equatable, Sendable {
        /// Move the pointer to the middle of a window focused from the keyboard.
        public var mouseFollowsFocus = true
        /// Focus the window under the pointer when it moves.
        public var focusFollowsMouse = false
        /// focus stack.next/prev go round from the last window to the first (false: they stop).
        public var wrapStacks = false
        public init() {}
    }

    public struct Animation: Codable, Equatable, Sendable {
        public var enabled = true
        public var durationMs = 180.0
        public var curve = Easing.easeOutCubic
        /// "start": windows take their final size first and glide into place (smooth);
        /// "animate": size changes every frame (apps redraw a lot); "end": size at the end.
        public var resize = "start"
        /// Skip animating more windows than this at once (just place them).
        public var maxWindows = 12
        public init() {}
    }

    /// Which windows paw leaves alone or treats specially.
    public struct Rule: Codable, Equatable, Sendable {
        /// App name, or /regex/.
        public var app: String
        /// Window title /regex/ (or plain substring) the rule needs.
        public var title: String?
        /// The rule doesn't apply when the title matches this.
        public var unlessTitle: String?
        /// false: paw never touches these windows.
        public var manage: Bool?
        /// true: floating instead of tiled.
        public var float: Bool?
        /// Workspace new windows of the app go to.
        public var workspace: String?

        public init(app: String, title: String? = nil, unlessTitle: String? = nil, manage: Bool? = nil, float: Bool? = nil,
                    workspace: String? = nil) {
            self.app = app
            self.title = title
            self.unlessTitle = unlessTitle
            self.manage = manage
            self.float = float
            self.workspace = workspace
        }

        public func matches(app a: String, title t: String) -> Bool {
            guard AppMatcher.matches(app, a) else { return false }
            if let title, !Self.text(title, t) { return false }
            if let unlessTitle, Self.text(unlessTitle, t) { return false }
            return true
        }

        static func text(_ pattern: String, _ s: String) -> Bool {
            if pattern.count > 2, pattern.hasPrefix("/"), pattern.hasSuffix("/") {
                return s.range(of: String(pattern.dropFirst().dropLast()), options: [.regularExpression, .caseInsensitive]) != nil
            }
            return s.localizedCaseInsensitiveContains(pattern)
        }
    }

    public struct Setup: Codable, Equatable, Sendable {
        /// One entry per display: "builtin", "external", "main", or (part of) its name ("DELL").
        public var displays: [String] = []
        /// Presets as in `workspaces`; `display` pins a workspace to one of these displays.
        public var workspaces: [String: WorkspacePreset] = [:]
        /// Workspace to focus after switching to this setup; "" keeps `initiate.focus`.
        public var focus = ""
        public init(displays: [String] = [], workspaces: [String: WorkspacePreset] = [:], focus: String = "") {
            self.displays = displays
            self.workspaces = workspaces
            self.focus = focus
        }

        /// Whether these displays (names, built-in or not) are exactly the ones `displays` asks for.
        public func matches(_ connected: [(name: String, builtin: Bool)]) -> Bool {
            guard connected.count == displays.count else { return false }
            var free = Array(connected.indices)
            // Specific names first, so "external" doesn't take the display "DELL" needs.
            let generic: Set<String> = ["builtin", "internal", "laptop", "external", "main", "primary", "secondary"]
            for spec in displays.sorted(by: { !generic.contains($0.lowercased()) && generic.contains($1.lowercased()) }) {
                guard let k = free.firstIndex(where: { Self.spec(spec, matches: connected[$0], index: $0) }) else { return false }
                free.remove(at: k)
            }
            return true
        }

        static func spec(_ spec: String, matches d: (name: String, builtin: Bool), index: Int) -> Bool {
            switch spec.lowercased() {
            case "builtin", "internal", "laptop": return d.builtin
            case "external": return !d.builtin
            case "main", "primary": return index == 0
            case "secondary": return index == 1
            default: return d.name.localizedCaseInsensitiveContains(spec)
            }
        }
    }

    /// The setup for these displays, if one matches.
    public func setup(for connected: [(name: String, builtin: Bool)]) -> (name: String, setup: Setup)? {
        setups.sorted { $0.key < $1.key }.first { $0.value.matches(connected) }.map { ($0.key, $0.value) }
    }

    public struct Initiate: Codable, Equatable, Sendable {
        /// Apps to open (names as in /Applications). Empty: every plain (non-/regex/) app name
        /// in the workspace presets.
        public var apps: [String] = []
        /// Workspace to show when done; "" stays where you are.
        public var focus = ""
        /// Seconds to wait for the apps' windows before arranging anyway.
        public var timeout = 15.0
        public init() {}

        /// The apps `initiate` opens for these presets.
        public func appsToOpen(_ presets: [String: WorkspacePreset]) -> [String] {
            if !apps.isEmpty { return apps }
            var out: [String] = []
            for name in presets.keys.sorted(by: { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }) {
                for t in presets[name]!.tiles {
                    for a in t.apps where !(a.hasPrefix("/") && a.hasSuffix("/") && a.count > 1) && !out.contains(a) { out.append(a) }
                }
            }
            return out
        }
    }

    /// Shell commands paw runs on events, with PAW_* variables set.
    public struct Hooks: Codable, Equatable, Sendable {
        /// After the focused workspace changes ($PAW_WORKSPACE, $PAW_PREV_WORKSPACE).
        public var workspaceChanged = ""
        /// After focus moves to another window ($PAW_APP, $PAW_WINDOW).
        public var windowFocused = ""
        /// After a mode turns on or off ($PAW_MODE, "" when it's off).
        public var modeChanged = ""
        /// After windows open, close or move between workspaces, or workspaces come and go
        /// (debounced; for a bar's app icons: read `paw query --json`).
        public var windowsChanged = ""
        /// After displays are plugged in, unplugged or rearranged and paw has retiled
        /// ($PAW_DISPLAYS: how many are connected).
        public var displaysChanged = ""
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

    /// Indicator colours (a dark sketchybar-style palette by default).
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
        /// Colour each app's icon with its own colour, taken from its app icon.
        public var brandColors = true
        /// App name → colour when the picked one is wrong, e.g. { "Brave Browser": "#fb542b" }.
        public var colors: [String: ARGB] = [:]
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
    enum CodingKeys: String, CodingKey, CaseIterable {
        case layout, focus, animation, bindings, modes, workspaces, setups, rules, indicator, appearance, icons, hooks, initiate, openAtLogin
    }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.layout, &layout); try f(.focus, &focus); try f(.animation, &animation); try f(.bindings, &bindings); try f(.modes, &modes)
        try f(.workspaces, &workspaces); try f(.setups, &setups); try f(.rules, &rules); try f(.indicator, &indicator); try f(.appearance, &appearance)
        try f(.icons, &icons); try f(.hooks, &hooks); try f(.initiate, &initiate); try f(.openAtLogin, &openAtLogin)
    }
}

extension PawConfig.Layout {
    enum CodingKeys: String, CodingKey, CaseIterable { case `default`, gap, padding, barTop, barBottom, workspaces, unassignedWorkspace }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.default, &`default`); try f(.gap, &gap); try f(.padding, &padding); try f(.barTop, &barTop)
        try f(.barBottom, &barBottom); try f(.workspaces, &workspaces); try f(.unassignedWorkspace, &unassignedWorkspace)
    }
}

extension PawConfig.Focus {
    enum CodingKeys: String, CodingKey, CaseIterable { case mouseFollowsFocus, focusFollowsMouse, wrapStacks }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.mouseFollowsFocus, &mouseFollowsFocus); try f(.focusFollowsMouse, &focusFollowsMouse); try f(.wrapStacks, &wrapStacks)
    }
}

extension PawConfig.Animation {
    enum CodingKeys: String, CodingKey, CaseIterable { case enabled, durationMs, curve, resize, maxWindows }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.enabled, &enabled); try f(.durationMs, &durationMs); try f(.curve, &curve); try f(.resize, &resize)
        try f(.maxWindows, &maxWindows)
    }
}

extension PawConfig.Setup {
    enum CodingKeys: String, CodingKey, CaseIterable { case displays, workspaces, focus }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.displays, &displays); try f(.workspaces, &workspaces); try f(.focus, &focus)
    }
}

extension PawConfig.Initiate {
    enum CodingKeys: String, CodingKey, CaseIterable { case apps, focus, timeout }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.apps, &apps); try f(.focus, &focus); try f(.timeout, &timeout)
    }
}

extension PawConfig.Hooks {
    enum CodingKeys: String, CodingKey, CaseIterable { case workspaceChanged, windowFocused, windowsChanged, modeChanged, displaysChanged }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.workspaceChanged, &workspaceChanged); try f(.windowFocused, &windowFocused)
        try f(.windowsChanged, &windowsChanged); try f(.modeChanged, &modeChanged)
        try f(.displaysChanged, &displaysChanged)
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
    enum CodingKeys: String, CodingKey, CaseIterable { case map, overrides, brandColors, colors }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.map, &map); try f(.overrides, &overrides); try f(.brandColors, &brandColors); try f(.colors, &colors)
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
            "layout": Set(PawConfig.Layout.CodingKeys.allCases.map(\.rawValue)),
            "focus": Set(PawConfig.Focus.CodingKeys.allCases.map(\.rawValue)),
            "animation": Set(PawConfig.Animation.CodingKeys.allCases.map(\.rawValue)),
            "hooks": Set(PawConfig.Hooks.CodingKeys.allCases.map(\.rawValue)),
            "initiate": Set(PawConfig.Initiate.CodingKeys.allCases.map(\.rawValue)),
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

    /// Problems a valid file can still have: bindings that don't parse, two keys on one binding.
    public static func warnings(_ c: PawConfig) -> [String] {
        var w: [String] = []
        var seen: [KeySpec: String] = [:]
        for (key, cmd) in c.bindings.sorted(by: { $0.key < $1.key }) {
            guard let spec = KeySpec.parse(key) else { w.append("bindings: “\(key)” is not a key"); continue }
            if let other = seen[spec] { w.append("bindings: “\(key)” and “\(other)” are the same key") }
            seen[spec] = key
            do { _ = try Command.parseAll(cmd) } catch { w.append("bindings.\(key): \(error)") }
        }
        for (name, p) in c.workspaces.sorted(by: { $0.key < $1.key }) where p.tiles.isEmpty && p.layout != .float {
            w.append("workspaces.\(name): no tiles")
        }
        if !["hover", "never"].contains(c.indicator.titles) { w.append("indicator.titles: “\(c.indicator.titles)” is not hover or never") }
        if !["start", "animate", "end"].contains(c.animation.resize) { w.append("animation.resize: start, animate or end") }
        return w
    }
}
