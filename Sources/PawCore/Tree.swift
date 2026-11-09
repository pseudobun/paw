import CoreGraphics

public typealias WindowID = UInt32

public enum Direction: String, Sendable, CaseIterable {
    case west, east, north, south

    public init?(_ s: String) {
        switch s.lowercased() {
        case "west", "left", "w", "h": self = .west
        case "east", "right", "e", "l": self = .east
        case "north", "up", "n", "k": self = .north
        case "south", "down", "s", "j": self = .south
        default: return nil
        }
    }

    public var axis: Axis { self == .west || self == .east ? .horizontal : .vertical }
    /// West and north come first in a split.
    public var isFirst: Bool { self == .west || self == .north }
}

/// `.horizontal` lays children side by side, `.vertical` one above the other.
public enum Axis: String, Sendable, Codable {
    case horizontal, vertical
    public var flipped: Axis { self == .horizontal ? .vertical : .horizontal }
}

public enum LayoutKind: String, Sendable, Codable, CaseIterable {
    case bsp, stack, float
}

/// A node of a workspace's layout tree: a split with two children, or a tile with one window
/// or several stacked on top of each other (the one at `active` is shown).
public final class Node {
    public weak var parent: Node?
    // Split
    public var axis: Axis = .horizontal
    public var ratio: Double = 0.5
    public private(set) var first: Node?
    public private(set) var second: Node?
    // Tile
    public var windows: [WindowID] = []
    public var active = 0
    /// Which tile of a workspace preset this is (so its apps land here again).
    public var slot: Int?

    public var isTile: Bool { first == nil }
    public var activeWindow: WindowID? { windows.indices.contains(active) ? windows[active] : windows.last }

    public init(windows: [WindowID] = []) { self.windows = windows }

    public init(axis: Axis, ratio: Double = 0.5, first: Node, second: Node) {
        self.axis = axis
        self.ratio = ratio
        setChildren(first, second)
    }

    func setChildren(_ a: Node, _ b: Node) {
        first = a
        second = b
        a.parent = self
        b.parent = self
    }

    func replaceChild(_ old: Node, with new: Node) {
        if first === old { first = new } else if second === old { second = new }
        new.parent = self
    }

    public var tiles: [Node] {
        isTile ? [self] : (first?.tiles ?? []) + (second?.tiles ?? [])
    }

    func clampActive() {
        if windows.isEmpty { active = 0 } else { active = min(max(0, active), windows.count - 1) }
    }
}

/// A workspace: its tree of tiled windows plus floating ones, and which window has focus.
public final class Workspace {
    public let name: String
    public var layout: LayoutKind
    public private(set) var root: Node?
    public var floating: [WindowID] = []
    public var focused: WindowID?
    /// Shows one window over the whole area (yabai's zoom-fullscreen).
    public var zoomed: WindowID?

    public init(name: String, layout: LayoutKind = .bsp) {
        self.name = name
        self.layout = layout
    }

    // MARK: Queries

    public var tiles: [Node] { root?.tiles ?? [] }
    public var tiledWindows: [WindowID] { tiles.flatMap(\.windows) }
    public var allWindows: [WindowID] { tiledWindows + floating }
    public var isEmpty: Bool { allWindows.isEmpty }

    public func tile(of w: WindowID) -> Node? { tiles.first { $0.windows.contains(w) } }
    public func contains(_ w: WindowID) -> Bool { allWindows.contains(w) }
    public func isFloating(_ w: WindowID) -> Bool { floating.contains(w) }

    // MARK: Adding and removing

    /// Adds a window next to the focused one. `area` decides the split direction (yabai's
    /// split_type auto: wide tiles split side by side).
    public func insert(_ w: WindowID, area: CGRect, floating float: Bool = false, slot: Int? = nil) {
        guard !contains(w) else { return }
        if float || layout == .float {
            floating.append(w)
            return
        }
        guard let root else {
            let t = Node(windows: [w])
            t.slot = slot
            self.root = t
            return
        }
        if layout == .stack {
            let t = root.isTile ? root : tiles[0]
            t.windows.append(w)
            t.active = t.windows.count - 1
            return
        }
        if let slot, let t = tiles.first(where: { $0.slot == slot }) {
            t.windows.append(w)
            t.active = t.windows.count - 1
            return
        }
        let target = focused.flatMap(tile(of:)) ?? tiles.last!
        let frames = TreeLayout.tileFrames(self, in: area, gap: 0)
        let f = frames[ObjectIdentifier(target)] ?? area
        split(target, with: Node(windows: [w]), axis: f.width >= f.height ? .horizontal : .vertical, newFirst: false)
    }

    /// Replaces `target` with a split of `target` and `new`.
    func split(_ target: Node, with new: Node, axis: Axis, newFirst: Bool, ratio: Double = 0.5) {
        let parent = target.parent
        let s = Node(axis: axis, ratio: ratio, first: newFirst ? new : target, second: newFirst ? target : new)
        if let parent { parent.replaceChild(target, with: s) } else { root = s; s.parent = nil }
    }

    /// Takes a window out of the workspace; empty tiles collapse into their sibling.
    public func remove(_ w: WindowID) {
        floating.removeAll { $0 == w }
        if zoomed == w { zoomed = nil }
        if let t = tile(of: w) {
            t.windows.removeAll { $0 == w }
            t.clampActive()
            if t.windows.isEmpty { removeTile(t) }
        }
        if focused == w { focused = tiledWindows.first ?? floating.first }
    }

    func removeTile(_ t: Node) {
        guard let parent = t.parent else { root = nil; return }
        let sibling = parent.first === t ? parent.second! : parent.first!
        if let grand = parent.parent { grand.replaceChild(parent, with: sibling) } else { root = sibling; sibling.parent = nil }
    }

    // MARK: Layout changes

    /// bsp ↔ stack ↔ float, keeping the window order.
    public func setLayout(_ kind: LayoutKind, area: CGRect) {
        guard kind != layout else { return }
        let order = tiledWindows + (layout == .float ? floating : [])
        let keepFloating = layout == .float ? [] : floating
        let focus = focused
        layout = kind
        root = nil
        floating = keepFloating
        zoomed = nil
        switch kind {
        case .float:
            floating += order
        case .stack:
            if !order.isEmpty {
                let t = Node(windows: order)
                t.active = focus.flatMap { order.firstIndex(of: $0) } ?? 0
                root = t
            }
        case .bsp:
            for w in order {
                insert(w, area: area)
                focused = w
            }
        }
        focused = focus
    }

    public func toggleFloat(_ w: WindowID, area: CGRect) {
        if isFloating(w) {
            floating.removeAll { $0 == w }
            if layout == .float { layout = .bsp }
            insert(w, area: area)
        } else if tile(of: w) != nil {
            remove(w)
            floating.append(w)
            focused = w
        }
    }

    public func toggleZoom(_ w: WindowID) {
        zoomed = zoomed == w ? nil : (tile(of: w) != nil ? w : nil)
    }

    /// Flips the split the window's tile sits in.
    public func toggleSplit(_ w: WindowID) {
        tile(of: w)?.parent?.axis = tile(of: w)?.parent?.axis.flipped ?? .horizontal
    }

    public func balance() {
        func walk(_ n: Node?) {
            guard let n, !n.isTile else { return }
            n.ratio = 0.5
            walk(n.first)
            walk(n.second)
        }
        walk(root)
    }

    /// Rotates the tree by 90, 180 or 270 degrees clockwise (yabai's space --rotate).
    public func rotate(_ degrees: Int) {
        func walk(_ n: Node?) {
            guard let n, !n.isTile, let a = n.first, let b = n.second else { return }
            let swap: Bool
            switch ((degrees % 360) + 360) % 360 {
            case 90: swap = n.axis == .vertical; n.axis = n.axis.flipped
            case 270: swap = n.axis == .horizontal; n.axis = n.axis.flipped
            case 180: swap = true
            default: swap = false
            }
            if swap {
                n.setChildren(b, a)
                n.ratio = 1 - n.ratio
            }
            walk(n.first)
            walk(n.second)
        }
        walk(root)
    }

    // MARK: Moving between tiles

    /// Swaps the window with the visible window of the tile in `dir`.
    @discardableResult
    public func swap(_ w: WindowID, _ dir: Direction, area: CGRect) -> Bool {
        guard let t = tile(of: w), let n = neighbor(of: t, dir, area: area), let i = t.windows.firstIndex(of: w) else { return false }
        let j = n.windows.indices.contains(n.active) ? n.active : 0
        let other = n.windows[j]
        t.windows[i] = other
        n.windows[j] = w
        return true
    }

    /// Moves the window out of its tile and splits the tile in `dir` with it, on that side.
    @discardableResult
    public func warp(_ w: WindowID, _ dir: Direction, area: CGRect) -> Bool {
        guard let t = tile(of: w), let n = neighbor(of: t, dir, area: area) else { return false }
        if t.windows.count == 1, t.parent === n.parent, t.parent?.axis == dir.axis {
            // Two siblings: warping is a swap of places.
            return swap(w, dir, area: area)
        }
        let slot = t.slot
        t.windows.removeAll { $0 == w }
        t.clampActive()
        if t.windows.isEmpty { removeTile(t) }
        let new = Node(windows: [w])
        new.slot = slot
        split(n, with: new, axis: dir.axis, newFirst: dir.isFirst)
        return true
    }

    /// Puts the window into the stack of the tile in `dir` (merging stacks).
    @discardableResult
    public func stack(_ w: WindowID, _ dir: Direction, area: CGRect) -> Bool {
        guard let t = tile(of: w), let n = neighbor(of: t, dir, area: area) else { return false }
        t.windows.removeAll { $0 == w }
        t.clampActive()
        if t.windows.isEmpty { removeTile(t) }
        n.windows.append(w)
        n.active = n.windows.count - 1
        return true
    }

    /// Takes the window out of its stack into its own tile next to it.
    @discardableResult
    public func unstack(_ w: WindowID, area: CGRect) -> Bool {
        guard let t = tile(of: w), t.windows.count > 1 else { return false }
        if layout == .stack { layout = .bsp }
        t.windows.removeAll { $0 == w }
        t.clampActive()
        let frames = TreeLayout.tileFrames(self, in: area, gap: 0)
        let f = frames[ObjectIdentifier(t)] ?? area
        split(t, with: Node(windows: [w]), axis: f.width >= f.height ? .horizontal : .vertical, newFirst: false)
        return true
    }

    /// Splits every window of the stack into its own tile.
    public func unstackAll(_ w: WindowID, area: CGRect) {
        while let t = tile(of: w), t.windows.count > 1, let other = t.windows.first(where: { $0 != w }) {
            unstack(other, area: area)
        }
    }

    /// The window `offset` places further in its stack (wrapping), and makes it the visible one.
    public func cycleStack(_ w: WindowID, by offset: Int) -> WindowID? {
        guard let t = tile(of: w), t.windows.count > 1, let i = t.windows.firstIndex(of: w) else { return nil }
        let n = t.windows.count
        t.active = ((i + offset) % n + n) % n
        return t.windows[t.active]
    }

    /// Makes `w` the visible window of its stack.
    public func activate(_ w: WindowID) {
        guard let t = tile(of: w), let i = t.windows.firstIndex(of: w) else { return }
        t.active = i
    }

    /// Moves the edge of the window's tile in `dir` by `delta` points (positive grows the tile).
    @discardableResult
    public func resize(_ w: WindowID, _ dir: Direction, by delta: Double, area: CGRect) -> Bool {
        guard var child = tile(of: w) else { return false }
        let frames = TreeLayout.nodeFrames(self, in: area, gap: 0)
        while let p = child.parent {
            // The split whose divider is on that side of the tile.
            if p.axis == dir.axis, (p.first === child) != dir.isFirst, let f = frames[ObjectIdentifier(p)] {
                let size = dir.axis == .horizontal ? f.width : f.height
                guard size > 0 else { return false }
                let d = delta / size
                p.ratio = min(0.9, max(0.1, p.ratio + (dir.isFirst ? -d : d)))
                return true
            }
            child = p
        }
        return false
    }

    public func neighbor(of t: Node, _ dir: Direction, area: CGRect) -> Node? {
        let frames = TreeLayout.tileFrames(self, in: area, gap: 0)
        guard let from = frames[ObjectIdentifier(t)] else { return nil }
        let cands = tiles.compactMap { n -> (Node, CGRect)? in
            guard n !== t, let f = frames[ObjectIdentifier(n)] else { return nil }
            return (n, f)
        }
        return TreeLayout.nearest(from: from, dir, candidates: cands.map(\.1)).map { cands[$0].0 }
    }

    /// Builds the tree from a preset: one tile per entry, in a row (or column), sized by
    /// weights. Windows go to tiles by `assign`; the rest are inserted after.
    public func arrange(_ preset: WorkspacePreset, windows: [(id: WindowID, app: String)], area: CGRect) {
        let all = allWindows
        let focus = focused
        root = nil
        floating = floating.filter { all.contains($0) }
        let tiled = windows.filter { !floating.contains($0.id) }
        layout = preset.layout
        var placed = Set<WindowID>()
        var nodes: [Node] = []
        for (i, t) in preset.tiles.enumerated() {
            let n = Node()
            n.slot = i
            for pattern in t.apps {
                for w in tiled where !placed.contains(w.id) && AppMatcher.matches(pattern, w.app) {
                    n.windows.append(w.id)
                    placed.insert(w.id)
                }
            }
            nodes.append(n)
        }
        if preset.layout == .stack {
            let t = Node(windows: nodes.flatMap(\.windows))
            root = t.windows.isEmpty ? nil : t
        } else {
            // Empty preset tiles take no space until a window lands there.
            let filled = nodes.enumerated().filter { !$0.element.windows.isEmpty }
            let weights = filled.map { preset.tiles[$0.offset].size ?? 1 }
            root = Self.chain(filled.map(\.element), weights: weights, axis: preset.axis)
        }
        for w in tiled where !placed.contains(w.id) {
            if let slot = preset.slot(for: w.app) { insert(w.id, area: area, slot: slot) } else { insert(w.id, area: area) }
        }
        focused = focus.flatMap { contains($0) ? $0 : nil } ?? tiledWindows.first
    }

    static func chain(_ nodes: [Node], weights: [Double], axis: Axis) -> Node? {
        guard let head = nodes.first else { return nil }
        guard nodes.count > 1 else { return head }
        let rest = chain(Array(nodes.dropFirst()), weights: Array(weights.dropFirst()), axis: axis)!
        let total = weights.reduce(0, +)
        let ratio = total > 0 ? weights[0] / total : 1 / Double(nodes.count)
        return Node(axis: axis, ratio: min(0.95, max(0.05, ratio)), first: head, second: rest)
    }
}

/// How windows sit in a workspace preset (`workspaces` in the config).
public struct WorkspacePreset: Codable, Equatable, Sendable {
    public struct Tile: Codable, Equatable, Sendable {
        /// App names (or /regex/) whose windows stack in this tile, in order.
        public var apps: [String]
        /// Relative size against the other tiles (default 1).
        public var size: Double?
        public init(apps: [String], size: Double? = nil) {
            self.apps = apps
            self.size = size
        }
    }

    public var layout: LayoutKind = .bsp
    public var axis: Axis = .horizontal
    public var tiles: [Tile] = []
    /// Display this workspace opens on: "main", "secondary" or a 1-based index.
    public var display: String?

    public init(layout: LayoutKind = .bsp, axis: Axis = .horizontal, tiles: [Tile] = [], display: String? = nil) {
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

    public func slot(for app: String) -> Int? {
        tiles.firstIndex { $0.apps.contains { AppMatcher.matches($0, app) } }
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
