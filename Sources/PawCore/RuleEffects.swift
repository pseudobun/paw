import Foundation

/// Why a window would float without any rule: what macOS says about it.
public enum NativeFloat: Sendable, Equatable {
    /// A standard, resizable window: tiled.
    case none
    /// A dialog, a panel or a window whose size can't be set: always floats.
    case kind
    /// Its app fixes its size (a greyed-out green button): floats unless a rule says `float: false`.
    case fixedSize
}

/// What `rules` decide for one window. One place, so a window paw takes on and a window paw
/// checks again after the rules changed come out the same.
extension PawConfig {
    /// The rules that apply to a window.
    public func rules(app: String, title: String) -> [Rule] {
        rules.filter { $0.matches(app: app, title: title) }
    }

    /// A rule with `manage: false` leaves the window alone.
    public func ignores(app: String, title: String) -> Bool {
        rules(app: app, title: title).contains { $0.manage == false }
    }

    /// Whether the window floats instead of tiling.
    public func floats(app: String, title: String, native: NativeFloat) -> Bool {
        let rules = rules(app: app, title: title)
        if rules.contains(where: { $0.float == true }) || native == .kind { return true }
        return native == .fixedSize && !rules.contains { $0.float == false }
    }

    /// The workspace a rule sends the window to, if any.
    public func ruleWorkspace(app: String, title: String) -> String? {
        rules(app: app, title: title).first { $0.workspace != nil }?.workspace
    }

    /// The workspace presets in effect with `setup` active: its own, else `workspaces`.
    public func presets(setup: String?) -> [String: WorkspacePreset] {
        setup.flatMap { setups[$0]?.workspaces } ?? workspaces
    }
}

/// What a reload that changed `rules` does to a window paw already manages. Only what the
/// change itself decides moves: a window floated by hand stays floating unless a rule about it
/// changed its answer.
public struct RuleChange: Equatable, Sendable {
    /// true: float it, false: tile it, nil: leave it.
    public var float: Bool?
    /// The workspace to move it to, nil: it stays.
    public var workspace: String?

    public init(float: Bool? = nil, workspace: String? = nil) {
        self.float = float
        self.workspace = workspace
    }

    public static func between(_ old: PawConfig, _ new: PawConfig, app: String, title: String, native: NativeFloat,
                               floating: Bool, on workspace: String) -> RuleChange {
        var change = RuleChange()
        let was = old.floats(app: app, title: title, native: native)
        let now = new.floats(app: app, title: title, native: native)
        if was != now, floating != now { change.float = now }
        if let to = new.ruleWorkspace(app: app, title: title), to != old.ruleWorkspace(app: app, title: title), to != workspace {
            change.workspace = to
        }
        return change
    }
}

extension PawConfig.Layout {
    /// Workspaces that go when `workspaces` is lowered: numbered above the new count, empty, and
    /// not kept for another reason (a preset, on screen).
    public func surplusWorkspaces(among names: [String], isEmpty: (String) -> Bool, keep: (String) -> Bool) -> [String] {
        names.compactMap { name in Int(name).map { (name, $0) } }
            .filter { $0.1 > max(1, workspaces) && isEmpty($0.0) && !keep($0.0) }
            .sorted { $0.1 < $1.1 }.map(\.0)
    }
}
