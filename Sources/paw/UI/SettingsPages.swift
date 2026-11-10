import AppKit
import PawCore

/// Reads and writes one part of a `PawConfig`.
struct Lens<T> {
    let get: (PawConfig) -> T
    let set: (inout PawConfig, T) -> Void

    init(get: @escaping (PawConfig) -> T, set: @escaping (inout PawConfig, T) -> Void) {
        self.get = get
        self.set = set
    }

    init(_ path: WritableKeyPath<PawConfig, T>) {
        get = { $0[keyPath: path] }
        set = { $0[keyPath: path] = $1 }
    }
}

/// One editable config key in the Settings window. `key` is its dotted path in `config.json5`
/// (for search); `value` reads and writes it as Bool, String, [String], Double or ARGB.
struct SettingsField {
    enum Kind {
        case toggle
        case text(placeholder: String = "")
        /// A long single line (a shell command, a path) across the row, under its label.
        case wide(placeholder: String = "")
        /// Comma-separated in the field, a JSON array in the file.
        case list(placeholder: String = "")
        case number(min: Double, max: Double, step: Double = 1, unit: String = "")
        case choice([(value: String, label: String)])
        case color
    }

    let key: String
    let label: String
    var help: String?
    let kind: Kind
    let value: Lens<Any>
}

/// A row that is not a config value: a button, or a note.
struct SettingsInfo {
    let label: String
    var help: String?
    let button: String
    let action: SettingsAction
}

enum SettingsAction {
    case openConfig, revealConfig, reloadConfig
}

/// Config collections, edited in rows of their own.
enum SettingsEditor {
    /// Workspace presets: layout, axis, display and the tiles' apps, size, title and launch.
    case presets(Lens<[String: WorkspacePreset]>)
    case setups
    case rules
    /// Key → value text, e.g. bindings (`check` marks keys or values paw can't read).
    case map(Lens<[String: String]>, key: String, value: String, check: MapCheck = .none)
    case modes
    case gestures
    case iconColors

    enum MapCheck { case none, bindings }

    /// Search words for the rows it shows.
    var haystack: String {
        switch self {
        case .presets: "workspace preset tiles apps size title launch display layout axis"
        case .setups: "setups displays arrangement focus workspace presets"
        case .rules: "rules app title unless float ignore manage workspace"
        case .map(_, let key, let value, _): "\(key) \(value)"
        case .modes: "modes mode keys"
        case .gestures: "gestures mouse button direction middle back forward click command"
        case .iconColors: "icon colours colors app"
        }
    }
}

enum SettingsRow {
    case field(SettingsField)
    case info(SettingsInfo)
    case note(String)
}

struct SettingsSection {
    enum Content {
        case rows([SettingsRow])
        case editor(SettingsEditor)
    }

    var title: String?
    var content: Content

    init(_ title: String, _ rows: [SettingsRow]) {
        self.title = title
        content = .rows(rows)
    }

    init(_ rows: [SettingsRow]) { content = .rows(rows) }

    init(_ title: String? = nil, editor: SettingsEditor) {
        self.title = title
        content = .editor(editor)
    }
}

struct SettingsPage {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let color: NSColor
    /// The page's `enabled` key: off greys out the rest of the page.
    var gate: String?
    let sections: [SettingsSection]

    var fields: [SettingsField] {
        sections.flatMap { section -> [SettingsField] in
            guard case .rows(let rows) = section.content else { return [] }
            return rows.compactMap { if case .field(let f) = $0 { f } else { nil } }
        }
    }

    /// Search text: the page, its labels, help and keys.
    var haystack: String {
        var words = [title, subtitle]
        for section in sections {
            words.append(section.title ?? "")
            switch section.content {
            case .rows(let rows):
                for row in rows {
                    switch row {
                    case .field(let f): words += [f.label, f.help ?? "", f.key]
                    case .info(let i): words += [i.label, i.help ?? ""]
                    case .note(let n): words.append(n)
                    }
                }
            case .editor(let e): words.append(e.haystack)
            }
        }
        return words.joined(separator: " ").lowercased()
    }
}

struct SettingsGroup {
    let title: String
    let pages: [SettingsPage]
}

// MARK: - The pages

enum SettingsCatalog {
    private static func f<T>(_ path: WritableKeyPath<PawConfig, T>, _ key: String, _ label: String,
                             _ kind: SettingsField.Kind, _ help: String? = nil) -> SettingsRow {
        .field(SettingsField(key: key, label: label, help: help, kind: kind,
                             value: Lens(get: { $0[keyPath: path] }, set: { c, v in if let v = v as? T { c[keyPath: path] = v } })))
    }

    /// An Int key shown as a number.
    private static func f(_ path: WritableKeyPath<PawConfig, Int>, _ key: String, _ label: String,
                          _ kind: SettingsField.Kind, _ help: String? = nil) -> SettingsRow {
        .field(SettingsField(key: key, label: label, help: help, kind: kind,
                             value: Lens(get: { Double($0[keyPath: path]) },
                                         set: { c, v in if let v = v as? Double { c[keyPath: path] = Int(v) } })))
    }

    /// A String-backed enum key shown as a choice of its raw values.
    private static func e<E: RawRepresentable & CaseIterable>(_ path: WritableKeyPath<PawConfig, E>, _ key: String,
                                                              _ label: String, _ help: String? = nil) -> SettingsRow
        where E.RawValue == String {
        .field(SettingsField(key: key, label: label, help: help, kind: choices(E.allCases.map(\.rawValue)),
                             value: Lens(get: { $0[keyPath: path].rawValue },
                                         set: { c, v in if let v = v as? String, let e = E(rawValue: v) { c[keyPath: path] = e } })))
    }

    static func choices(_ values: [String]) -> SettingsField.Kind { .choice(options(values)) }

    /// Raw values, labelled with a capital first letter.
    static func options(_ values: [String]) -> [(value: String, label: String)] {
        values.map { (value: $0, label: $0.prefix(1).uppercased() + $0.dropFirst()) }
    }

    private static let modifiers = ["alt", "cmd", "ctrl", "shift"]

    static var groups: [SettingsGroup] {
        [
            SettingsGroup(title: "paw", pages: [general, layout, focus, animation]),
            SettingsGroup(title: "Workspaces", pages: [workspaces, setups, rules, initiate]),
            SettingsGroup(title: "Input", pages: [keys, mouse]),
            SettingsGroup(title: "Look", pages: [indicators, appearance, icons, border, overview]),
            SettingsGroup(title: "Advanced", pages: [hooks]),
        ]
    }

    static var pages: [SettingsPage] { groups.flatMap(\.pages) }

    static var general: SettingsPage {
        SettingsPage(id: "general", title: "General", subtitle: "Startup, updates and the config file.",
                     symbol: "gearshape.fill", color: Theme.neutral, sections: [
            SettingsSection("Startup", [
                f(\.openAtLogin, "openAtLogin", "Open at login", .toggle, "Only for the installed paw.app."),
            ]),
            SettingsSection("Updates", [
                f(\.updates.check, "updates.check", "Check for updates", .toggle, "Once a day; offers new versions from GitHub."),
                f(\.updates.automatic, "updates.automatic", "Install automatically", .toggle, "Without asking; paw relaunches."),
            ]),
            SettingsSection("Config file", [
                .info(SettingsInfo(label: "Open in editor", help: "Everything here is saved to config.json5 at once; edits there apply here too.",
                                   button: "Open Config", action: .openConfig)),
                .info(SettingsInfo(label: "Show in Finder", button: "Reveal", action: .revealConfig)),
                .info(SettingsInfo(label: "Read the file again", button: "Reload", action: .reloadConfig)),
            ]),
        ])
    }

    static var layout: SettingsPage {
        SettingsPage(id: "layout", title: "Layout", subtitle: "How tiles fill a workspace.",
                     symbol: "rectangle.split.3x1.fill", color: Theme.chart3, sections: [
            SettingsSection([
                e(\.layout.default, "layout.default", "New workspaces", "Layout of a workspace no preset sets."),
                f(\.layout.gap, "layout.gap", "Gap", .number(min: 0, max: 200, unit: "pt"), "Between tiles."),
                f(\.layout.workspaces, "layout.workspaces", "Workspaces", .number(min: 1, max: 20),
                  "Workspaces 1…N exist from the start; `workspace new` adds more."),
                f(\.layout.unassignedWorkspace, "layout.unassignedWorkspace", "Unplaced apps go to", .text(placeholder: "stay"),
                  "Where initiate and setup switches put windows no preset or rule places; empty leaves them."),
            ]),
            SettingsSection("Smallest tile", [
                f(\.layout.minTileWidth, "layout.minTileWidth", "Width", .number(min: 0, max: 10_000, step: 10, unit: "pt"),
                  "bsp: tiles never get smaller; the tree grows past the screen instead. 0: off."),
                f(\.layout.minTileHeight, "layout.minTileHeight", "Height", .number(min: 0, max: 10_000, step: 10, unit: "pt")),
            ]),
            SettingsSection("Windows that won't shrink", [
                f(\.layout.placeholders, "layout.placeholders", "Placeholders", .toggle,
                  "A placeholder takes the tile while the window waits out of sight. Off: the window sticks out over its neighbours."),
                f(\.layout.placeholderMinWidth, "layout.placeholderMinWidth", "Smallest width", .number(min: 0, max: 2_000, step: 10, unit: "pt"),
                  "Resizing stops before a placeholder gets smaller."),
                f(\.layout.placeholderMinHeight, "layout.placeholderMinHeight", "Smallest height", .number(min: 0, max: 2_000, step: 10, unit: "pt")),
            ]),
            SettingsSection("Padding", [
                f(\.layout.padding.top, "layout.padding.top", "Top", .number(min: 0, max: 1_000, unit: "pt")),
                f(\.layout.padding.bottom, "layout.padding.bottom", "Bottom", .number(min: 0, max: 1_000, unit: "pt")),
                f(\.layout.padding.left, "layout.padding.left", "Left", .number(min: 0, max: 1_000, unit: "pt")),
                f(\.layout.padding.right, "layout.padding.right", "Right", .number(min: 0, max: 1_000, unit: "pt")),
            ]),
            SettingsSection("Status bar", [
                f(\.layout.barTop, "layout.barTop", "Room at the top", .number(min: 0, max: 500, unit: "pt"),
                  "For a bar such as sketchybar (41 for a 40 pt bar); the menu bar and Dock are left out already."),
                f(\.layout.barBottom, "layout.barBottom", "Room at the bottom", .number(min: 0, max: 500, unit: "pt")),
            ]),
        ])
    }

    static var focus: SettingsPage {
        SettingsPage(id: "focus", title: "Focus", subtitle: "Where focus and the pointer go.",
                     symbol: "scope", color: Theme.info, sections: [
            SettingsSection([
                f(\.focus.mouseFollowsFocus, "focus.mouseFollowsFocus", "Mouse follows focus", .toggle,
                  "The pointer moves to the middle of a window focused from the keyboard."),
                f(\.focus.focusFollowsMouse, "focus.focusFollowsMouse", "Focus follows mouse", .toggle,
                  "Focus the window under the pointer when it moves."),
                f(\.focus.wrapStacks, "focus.wrapStacks", "Stacks wrap around", .toggle,
                  "focus stack.next/prev go from the last window to the first; off: they stop."),
            ]),
        ])
    }

    static var animation: SettingsPage {
        SettingsPage(id: "animation", title: "Animation", subtitle: "Windows gliding into place.",
                     symbol: "sparkles", color: Theme.chart5, gate: "animation.enabled", sections: [
            SettingsSection([
                f(\.animation.enabled, "animation.enabled", "Animate window moves", .toggle),
                f(\.animation.durationMs, "animation.durationMs", "Duration", .number(min: 0, max: 2_000, step: 10, unit: "ms")),
                e(\.animation.curve, "animation.curve", "Curve"),
                f(\.animation.resize, "animation.resize", "Size changes", .choice([
                    ("start", "Start (smooth)"), ("animate", "Animate"), ("end", "End"),
                ]), "Start: final size first, then glide. Animate: every frame (apps redraw a lot). End: size at the end."),
                f(\.animation.maxWindows, "animation.maxWindows", "Animate at most", .number(min: 1, max: 50, unit: "windows"),
                  "More windows than this at once are just placed."),
            ]),
        ])
    }

    static var workspaces: SettingsPage {
        SettingsPage(id: "workspaces", title: "Workspaces", subtitle: "Presets: each workspace's layout and the apps in its tiles.",
                     symbol: "square.grid.2x2.fill", color: Theme.chart1, sections: [
            SettingsSection([
                .note("Used when no setup matches the displays. A tile stacks its apps (first on top); size is relative to the other tiles; title keeps only windows whose title matches; launch is the shell command `initiate` runs instead of opening the app. Display: main, secondary or a number."),
            ]),
            SettingsSection(editor: .presets(Lens(\.workspaces))),
        ])
    }

    static var setups: SettingsPage {
        SettingsPage(id: "setups", title: "Setups", subtitle: "Presets per display arrangement.",
                     symbol: "display.2", color: Theme.chart2, sections: [
            SettingsSection([
                .note("The first setup whose displays match the connected ones replaces the default workspaces; paw switches by itself when displays come and go. Displays: builtin, external, main, secondary, or part of a name (DELL)."),
            ]),
            SettingsSection(editor: .setups),
        ])
    }

    static var rules: SettingsPage {
        SettingsPage(id: "rules", title: "Rules", subtitle: "Windows paw floats, ignores or sends to a workspace.",
                     symbol: "list.bullet.rectangle.fill", color: Theme.chart4, sections: [
            SettingsSection([
                .note("App: a name or /regex/. Title and unless title: a substring or /regex/. Workspace: where new windows of the app open. Ignore: paw never touches them."),
            ]),
            SettingsSection(editor: .rules),
        ])
    }

    static var initiate: SettingsPage {
        SettingsPage(id: "initiate", title: "Initiate", subtitle: "`paw initiate`: open the preset apps and arrange every workspace.",
                     symbol: "play.rectangle.fill", color: Theme.good, sections: [
            SettingsSection([
                f(\.initiate.apps, "initiate.apps", "Apps to open", .list(placeholder: "every app in the presets"),
                  "Names as in /Applications, comma-separated; empty: every plain app name in the presets."),
                f(\.initiate.focus, "initiate.focus", "Then show", .text(placeholder: "stay"), "Workspace to show when done; empty stays."),
                f(\.initiate.timeout, "initiate.timeout", "Wait for windows", .number(min: 0, max: 600, unit: "s"),
                  "Then arrange anyway."),
            ]),
        ])
    }

    static var keys: SettingsPage {
        SettingsPage(id: "keys", title: "Keys", subtitle: "Key bindings and modes.",
                     symbol: "command", color: Theme.info, sections: [
            SettingsSection([
                .note("Keys: cmd ctrl alt shift fn hyper meh, lalt/ralt…, then a key name (left, return, a, 1) or a 0x keycode. Commands are the same as `paw <command>`; chain them with ;."),
            ]),
            SettingsSection("Bindings", editor: .map(Lens(\.bindings), key: "keys", value: "command", check: .bindings)),
            SettingsSection(editor: .modes),
        ])
    }

    static var mouse: SettingsPage {
        SettingsPage(id: "mouse", title: "Mouse", subtitle: "Dragging windows, seams and mouse-button gestures.",
                     symbol: "computermouse.fill", color: Theme.chart3, sections: [
            SettingsSection("Dragging", [
                f(\.mouse.dropZones, "mouse.dropZones", "Drop zones", .toggle,
                  "Drop a dragged tiled window on a tile's edge to split, a seam to make room, the middle to swap."),
                f(\.mouse.stackModifier, "mouse.stackModifier", "Hold to stack", choices(modifiers),
                  "Held while dropping in a tile's middle: stack instead of swap."),
                f(\.mouse.seamHandles, "mouse.seamHandles", "Drag seams", .toggle,
                  "Drag the gap between tiles to resize both sides; double-click it to even them out."),
                f(\.mouse.zoomModifier, "mouse.zoomModifier", "Hold to zoom", choices(modifiers + ["off"]),
                  "Hold and scroll (or pinch) over a window to zoom through the tree towards it."),
            ]),
            SettingsSection("Gestures", editor: .gestures),
            SettingsSection([
                f(\.mouse.gestureIgnoreApps, "mouse.gestureIgnoreApps", "No gestures in", .list(placeholder: "FreeCAD, /Fusion/"),
                  "Apps (name or /regex/) that keep their own middle-button drags."),
            ]),
        ])
    }

    static var indicators: SettingsPage {
        SettingsPage(id: "indicators", title: "Indicators", subtitle: "The islands that show a stack's windows.",
                     symbol: "square.stack.3d.up.fill", color: Theme.chart5, sections: [
            SettingsSection([
                e(\.indicator.side, "indicator.side", "Side", "Auto: outside, on the side nearer the screen edge."),
                f(\.indicator.titles, "indicator.titles", "Titles", .choice([("hover", "On hover"), ("never", "Never")]),
                  "An island with the window's title next to the hovered icon."),
                f(\.indicator.clickToFocus, "indicator.clickToFocus", "Click to focus", .toggle),
                f(\.indicator.scrollToCycle, "indicator.scrollToCycle", "Scroll through the stack", .toggle),
            ]),
            SettingsSection("Size", [
                f(\.indicator.width, "indicator.width", "Width", .number(min: 1, max: 200, unit: "pt")),
                f(\.indicator.cellHeight, "indicator.cellHeight", "Cell height", .number(min: 1, max: 200, unit: "pt")),
                f(\.indicator.gap, "indicator.gap", "Gap", .number(min: 0, max: 50, unit: "pt")),
                f(\.indicator.padding, "indicator.padding", "Padding", .number(min: 0, max: 50, unit: "pt")),
                f(\.indicator.offsetX, "indicator.offsetX", "Offset x", .number(min: -200, max: 200, unit: "pt")),
                f(\.indicator.offsetY, "indicator.offsetY", "Offset y", .number(min: -200, max: 200, unit: "pt")),
            ]),
            SettingsSection("Fade", [
                f(\.indicator.unfocusedOpacity, "indicator.unfocusedOpacity", "Unfocused opacity", .number(min: 0, max: 1, step: 0.05),
                  "Of stacks that don't have focus."),
                f(\.indicator.fadeMs, "indicator.fadeMs", "Fade", .number(min: 0, max: 2_000, step: 10, unit: "ms")),
            ]),
        ])
    }

    static var appearance: SettingsPage {
        func color(_ path: WritableKeyPath<PawConfig.Colors, ARGB>, _ key: String, _ label: String, _ help: String? = nil) -> SettingsRow {
            f((\PawConfig.appearance.colors).appending(path: path), "appearance.colors.\(key)", label, .color, help)
        }
        return SettingsPage(id: "appearance", title: "Appearance", subtitle: "Fonts, shape and colours of indicators and islands.",
                            symbol: "paintpalette.fill", color: Theme.chart2, sections: [
            SettingsSection("Fonts", [
                f(\.appearance.font, "appearance.font", "Font", .text(placeholder: "GeistMono Nerd Font"), "Titles; falls back to SF Mono."),
                f(\.appearance.fontSize, "appearance.fontSize", "Font size", .number(min: 6, max: 48, unit: "pt")),
                f(\.appearance.appFont, "appearance.appFont", "App icon font", .text(placeholder: "sketchybar-app-font"),
                  "Ligatures, like the bar; without it cells show the app's initial."),
                f(\.appearance.appIconSize, "appearance.appIconSize", "Icon size", .number(min: 6, max: 48, unit: "pt")),
            ]),
            SettingsSection("Shape", [
                f(\.appearance.radius, "appearance.radius", "Island radius", .number(min: 0, max: 40, unit: "pt")),
                f(\.appearance.cellRadius, "appearance.cellRadius", "Cell radius", .number(min: 0, max: 40, unit: "pt")),
                f(\.appearance.borderWidth, "appearance.borderWidth", "Border", .number(min: 0, max: 10, step: 0.5, unit: "pt")),
                f(\.appearance.shadow, "appearance.shadow", "Shadow", .toggle),
            ]),
            SettingsSection("Colours", [
                color(\.island, "island", "Island"),
                color(\.islandHi, "islandHi", "Highlighted cell"),
                color(\.border, "border", "Border"),
                color(\.fg, "fg", "Text"),
                color(\.muted, "muted", "Muted"),
                color(\.dim, "dim", "Dim"),
                color(\.accent, "accent", "Accent", "The focused window's icon."),
                color(\.wave, "wave", "Wave"),
                color(\.good, "good", "Good"),
                color(\.bad, "bad", "Bad"),
            ]),
        ])
    }

    static var icons: SettingsPage {
        SettingsPage(id: "icons", title: "Icons", subtitle: "App glyphs and their colours.",
                     symbol: "square.grid.3x3.fill", color: Theme.chart1, sections: [
            SettingsSection([
                f(\.icons.brandColors, "icons.brandColors", "Brand colours", .toggle, "Each icon in its app's own colour, taken from its app icon."),
                f(\.icons.map, "icons.map", "Icon map", .wide(placeholder: "~/.config/sketchybar/helpers/app_icons.lua"),
                  "sketchybar's app_icons.lua; the copy built into paw is used when it is missing."),
            ]),
            SettingsSection("Colours", editor: .iconColors),
            SettingsSection("Glyphs", editor: .map(Lens(\.icons.overrides), key: "app", value: ":ligature:")),
        ])
    }

    static var border: SettingsPage {
        SettingsPage(id: "border", title: "Border", subtitle: "A line around the focused window.",
                     symbol: "square.dashed", color: Theme.chart1, gate: "border.enabled", sections: [
            SettingsSection([
                f(\.border.enabled, "border.enabled", "Focus border", .toggle),
                f(\.border.color, "border.color", "Colour", .color),
                f(\.border.width, "border.width", "Width", .number(min: 0, max: 20, step: 0.5, unit: "pt")),
                f(\.border.radius, "border.radius", "Radius", .number(min: 0, max: 60, unit: "pt"), "macOS 26 windows are about 16."),
                f(\.border.offset, "border.offset", "Offset", .number(min: -20, max: 20, step: 0.5, unit: "pt"),
                  "How far outside the window the line sits."),
            ]),
        ])
    }

    static var overview: SettingsPage {
        SettingsPage(id: "overview", title: "Overview & HUD", subtitle: "The overview of every workspace and the workspace flash.",
                     symbol: "rectangle.grid.2x2.fill", color: Theme.chart4, sections: [
            SettingsSection("Overview", [
                f(\.overview.thumbnails, "overview.thumbnails", "Window pictures", .choice([
                    ("auto", "When allowed"), ("on", "On"), ("off", "Off"),
                ]), "On asks for Screen Recording; off shows app icons only."),
            ]),
            SettingsSection("Workspace HUD", [
                f(\.hud.workspace, "hud.workspace", "Flash the workspace", .toggle, "Its number and apps, when it changes."),
                f(\.hud.durationMs, "hud.durationMs", "Show for", .number(min: 0, max: 10_000, step: 50, unit: "ms")),
            ]),
        ])
    }

    static var hooks: SettingsPage {
        SettingsPage(id: "hooks", title: "Hooks", subtitle: "Shell commands paw runs on events.",
                     symbol: "terminal.fill", color: Theme.neutral, sections: [
            SettingsSection([
                .note("E.g. sketchybar --trigger paw_workspace_change. Variables: $PAW_WORKSPACE, $PAW_PREV_WORKSPACE, $PAW_APP, $PAW_WINDOW, $PAW_MODE, $PAW_DISPLAYS."),
            ]),
            SettingsSection([
                f(\.hooks.workspaceChanged, "hooks.workspaceChanged", "Workspace changed", .wide(), "$PAW_WORKSPACE, $PAW_PREV_WORKSPACE."),
                f(\.hooks.windowsChanged, "hooks.windowsChanged", "Windows changed", .wide(),
                  "Windows open, close or move, or workspaces come and go (debounced)."),
                f(\.hooks.windowFocused, "hooks.windowFocused", "Window focused", .wide(), "$PAW_APP, $PAW_WINDOW."),
                f(\.hooks.modeChanged, "hooks.modeChanged", "Mode changed", .wide(), "$PAW_MODE, empty when it's off."),
                f(\.hooks.displaysChanged, "hooks.displaysChanged", "Displays changed", .wide(), "After paw has retiled; $PAW_DISPLAYS."),
            ]),
        ])
    }
}
