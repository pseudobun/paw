import CoreGraphics

public typealias WindowID = UInt32

public enum Direction: String, Sendable, CaseIterable, Codable {
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

/// - bsp: new windows split the focused tile (wide tiles side by side).
/// - columns: every window a column of equal width.
/// - master: the first window on the left (62%), the rest stacked in rows on the right.
///   Tiles never get smaller than a minimum: when they don't fit, the tree grows past the
///   screen and the screen shows the branch around the focused window, following focus
///   (TrellisWM's canvas). "canvas" is another name for it.
/// - stack: every window in one stack.  - float: nothing tiled.
public enum LayoutKind: String, Sendable, Codable, CaseIterable {
    case bsp, columns, master, stack, float

    public init?(rawValue: String) {
        switch rawValue {
        case "bsp", "canvas": self = .bsp
        case "columns": self = .columns
        case "master": self = .master
        case "stack": self = .stack
        case "float": self = .float
        default: return nil
        }
    }

    /// Layouts that keep a tree of tiles (everything but stack and float).
    public var isTiled: Bool { self != .stack && self != .float }
}

/// A node of a workspace's layout tree: a split with any number of children sized by weight
/// (TrellisWM's fractal tree), or a tile with one window or several stacked on top of each
/// other (the one at `active` is shown).
public final class Node {
    public weak var parent: Node?
    // Split
    public var axis: Axis = .horizontal
    public private(set) var children: [Node] = []
    /// Relative sizes of `children` ([1, 3] → a quarter and three quarters).
    public var weights: [Double] = []
    // Tile
    public var windows: [WindowID] = []
    public var active = 0
    /// Which tile of a workspace preset this is (so its apps land here again).
    public var slot: Int?

    public var isTile: Bool { children.isEmpty }
    public var activeWindow: WindowID? { windows.indices.contains(active) ? windows[active] : windows.last }

    public init(windows: [WindowID] = []) { self.windows = windows }

    public init(axis: Axis, children: [Node], weights: [Double]? = nil) {
        self.axis = axis
        self.children = children
        self.weights = weights ?? Array(repeating: 1, count: children.count)
        for c in children { c.parent = self }
    }

    /// Children's share of this split, summing to 1.
    public var fractions: [Double] {
        let total = weights.reduce(0, +)
        return total > 0 ? weights.map { $0 / total } : weights.map { _ in 1 / Double(max(1, weights.count)) }
    }

    public func index(of child: Node) -> Int? { children.firstIndex { $0 === child } }

    func insertChild(_ n: Node, at i: Int, weight: Double) {
        children.insert(n, at: i)
        weights.insert(weight, at: i)
        n.parent = self
    }

    @discardableResult
    func removeChild(at i: Int) -> Double {
        children[i].parent = nil
        children.remove(at: i)
        return weights.remove(at: i)
    }

    func replaceChild(_ old: Node, with new: Node) {
        guard let i = index(of: old) else { return }
        children[i] = new
        new.parent = self
        if old.parent === self { old.parent = nil }
    }

    func reverseChildren() {
        children.reverse()
        weights.reverse()
    }

    public var tiles: [Node] { isTile ? [self] : children.flatMap(\.tiles) }

    /// Every window under this node.
    public var allWindows: [WindowID] { tiles.flatMap(\.windows) }

    func clampActive() {
        if windows.isEmpty { active = 0 } else { active = min(max(0, active), windows.count - 1) }
    }

    /// A deep copy (no parent).
    public func copy() -> Node {
        if isTile {
            let n = Node(windows: windows)
            n.active = active
            n.slot = slot
            return n
        }
        return Node(axis: axis, children: children.map { $0.copy() }, weights: weights)
    }
}

/// Where a dragged window lands in a workspace (TrellisWM's drop zones).
public enum DropTarget: Equatable {
    /// Next to a tile, on that side, splitting it.
    case split(tile: WindowID, side: Direction)
    /// Into the seam after child `index` of the split holding `before` and `after` (tiles on
    /// either side of the seam): a new child there, every sibling the same size.
    case seam(before: WindowID, after: WindowID, axis: Axis)
    /// Along an edge of the whole workspace, beside everything.
    case edge(Direction)
    /// On top of a tile's stack.
    case stack(tile: WindowID)
    /// Trade places with the tile's visible window.
    case swap(tile: WindowID)
}

/// Where a window was, so it can go back there (minimize, app quit, paw restart).
public struct Anchor: Codable, Equatable, Sendable {
    /// A window that stays in the tree next to where this one was.
    public var neighbor: WindowID
    public var axis: Axis
    /// The window sat before (west/north of) the neighbour's branch.
    public var before: Bool
    /// Its share of the split it was in.
    public var fraction: Double
    /// It was stacked with `neighbor` (at this index) instead of beside it.
    public var stackIndex: Int?
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
    /// The branch shown over the whole area (TrellisWM's camera, one level at a time);
    /// nil shows the whole tree. Windows outside it wait out of sight.
    public private(set) var view: Node?
    /// Only these children of the shown branch (a region picked in the overview: neighbours,
    /// not their whole parent). nil: all of them.
    private var range: ClosedRange<Int>?
    /// Smallest tile in bsp (`layout.minTileWidth/Height`); past it the screen follows focus.
    public var canvasMin = CGSize.zero
    /// Sizes windows refused to go below (paw learns them when an app clamps its window).
    public var windowMins: [WindowID: CGSize] = [:]

    /// The smallest a tile can be: `base`, or more when one of its windows needs more.
    public func tileMin(_ t: Node, base: CGSize) -> CGSize {
        t.windows.reduce(base) { m, w in
            guard let s = windowMins[w] else { return m }
            return CGSize(width: max(m.width, s.width), height: max(m.height, s.height))
        }
    }
    /// The shown branch was picked by hand (zoom in/out): a canvas keeps it while focus stays inside.
    private var pinned = false

    /// Smallest share a tile keeps when its neighbours grow.
    public static let minFraction = 0.05

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

    /// Every split node, root first.
    public var splits: [Node] {
        var out: [Node] = []
        func walk(_ n: Node) {
            guard !n.isTile else { return }
            out.append(n)
            n.children.forEach(walk)
        }
        if let root { walk(root) }
        return out
    }

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
        let new = Node(windows: [w])
        new.slot = slot
        switch layout {
        case .columns where root.isTile || root.axis == .horizontal:
            if root.isTile {
                self.root = Node(axis: .horizontal, children: [root, new])
            } else {
                root.insertChild(new, at: root.children.count, weight: 1)
                root.weights = root.weights.map { _ in 1 }
            }
            return
        case .master where root.isTile:
            self.root = Node(axis: .horizontal, children: [root, new], weights: [0.62, 0.38])
            return
        case .master where root.axis == .horizontal && root.children.count == 2:
            let right = root.children[1]
            if right.isTile {
                root.replaceChild(right, with: Node(axis: .vertical, children: [right, new]))
            } else if right.axis == .vertical {
                right.insertChild(new, at: right.children.count, weight: 1)
                right.weights = right.weights.map { _ in 1 }
            } else {
                break
            }
            return
        default:
            break
        }
        let target = focused.flatMap(tile(of:)) ?? tiles.last!
        let frames = TreeLayout.tileFrames(self, in: area, gap: 0, full: true)
        let f = frames[ObjectIdentifier(target)] ?? area
        split(target, with: new, axis: f.width >= f.height ? .horizontal : .vertical, newFirst: false)
    }

    /// Puts `new` beside `target`, taking `share` of its space. When `target`'s split already
    /// runs along `axis`, `new` becomes a sibling there instead of a nested split.
    func split(_ target: Node, with new: Node, axis: Axis, newFirst: Bool, share: Double = 0.5) {
        if let p = target.parent, p.axis == axis, let i = p.index(of: target) {
            let w = p.weights[i]
            p.weights[i] = w * (1 - share)
            p.insertChild(new, at: newFirst ? i : i + 1, weight: w * share)
            return
        }
        let parent = target.parent
        let placeholder = Node()
        if let parent { parent.replaceChild(target, with: placeholder) }
        let s = Node(axis: axis, children: newFirst ? [new, target] : [target, new],
                     weights: newFirst ? [share, 1 - share] : [1 - share, share])
        if let parent { parent.replaceChild(placeholder, with: s) } else { root = s; s.parent = nil }
    }

    /// Takes a window out of the workspace; empty tiles give their space to a neighbour.
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

    /// Removes a tile: its weight goes to the sibling before it (or after, when it was first),
    /// so the other siblings keep their size. A split left with one child collapses into it.
    func removeTile(_ t: Node) {
        guard let p = t.parent, let i = p.index(of: t) else {
            if root === t { root = nil }
            return
        }
        let w = p.removeChild(at: i)
        if !p.children.isEmpty { p.weights[max(0, i - 1)] += w }
        collapse(p)
    }

    /// A split with one child is replaced by that child (keeping the split's own weight).
    func collapse(_ p: Node) {
        guard p.children.count <= 1 else { return }
        guard let only = p.children.first else {
            if let gp = p.parent, let i = gp.index(of: p) { gp.removeChild(at: i); collapse(gp) } else if root === p { root = nil }
            return
        }
        p.removeChild(at: 0)
        if let gp = p.parent { gp.replaceChild(p, with: only) } else { root = only; only.parent = nil }
    }

    // MARK: Layout changes

    /// Switches the layout. A tiled layout again re-tiles from scratch: every window gets its own
    /// tile, stacks included.
    public func setLayout(_ kind: LayoutKind, area: CGRect) {
        guard kind != layout || kind.isTiled else { return }
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
        case .bsp, .columns, .master:
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
        for s in splits { s.weights = s.weights.map { _ in 1 } }
    }

    /// Rotates the tree by 90, 180 or 270 degrees clockwise (yabai's space --rotate).
    public func rotate(_ degrees: Int) {
        for n in splits {
            let swap: Bool
            switch ((degrees % 360) + 360) % 360 {
            case 90: swap = n.axis == .vertical; n.axis = n.axis.flipped
            case 270: swap = n.axis == .horizontal; n.axis = n.axis.flipped
            case 180: swap = true
            default: swap = false
            }
            if swap { n.reverseChildren() }
        }
    }

    // MARK: Zooming through the tree

    /// The branch actually shown: `view` while it is still in the tree.
    public var shownRoot: Node? {
        guard let v = view else { range = nil; return root }
        var n: Node? = v
        while let p = n?.parent { n = p }
        if n === root, !v.allWindows.isEmpty { return v }
        view = nil
        range = nil
        return root
    }

    /// The children of the shown branch that are on screen (nil: all).
    public var shownRange: ClosedRange<Int>? {
        guard let r = range, let s = shownRoot, !s.isTile, r.upperBound < s.children.count, r.count < s.children.count else {
            range = nil
            return nil
        }
        return r
    }

    /// Every window on screen (not outside the zoom or the picked region).
    public var shownWindows: Set<WindowID> {
        guard let s = shownRoot else { return [] }
        guard let r = shownRange else { return Set(s.allWindows) }
        return Set(s.children[r].flatMap(\.allWindows))
    }

    /// Whether `t` is on screen: under the shown branch, and in its range.
    func isShown(_ t: Node) -> Bool {
        guard let s = shownRoot else { return false }
        var n: Node = t
        while n !== s {
            guard let p = n.parent else { return false }
            if p === s, let r = shownRange, let i = p.index(of: n) { return r.contains(i) }
            n = p
        }
        return true
    }

    /// Steps in one level towards `w`: the child of the shown branch that holds it fills the
    /// area. Deepest: the window's own tile. False when there's nowhere further in.
    @discardableResult
    public func zoomIn(toward w: WindowID) -> Bool {
        guard layout.isTiled, let top = shownRoot, let t = tile(of: w), t !== top else { return false }
        var n = t
        while let p = n.parent, p !== top { n = p }
        guard n.parent === top else { return false }
        view = n
        range = nil
        pinned = true
        return true
    }

    /// Steps out one level; at the top the whole tree shows again. False when it already does.
    @discardableResult
    public func zoomOut() -> Bool {
        if shownRange != nil {
            // A picked region: first its whole branch.
            range = nil
            if view === root { view = nil }
            pinned = view != nil
            return true
        }
        guard let v = shownRoot, v !== root else { return false }
        view = v.parent === root ? nil : v.parent
        pinned = true
        return true
    }

    public func clearZoom() { view = nil; range = nil; pinned = false }

    /// Shows the smallest branch holding all of `ids` (a region picked in the overview).
    @discardableResult
    public func setView(containing ids: [WindowID]) -> Bool {
        let tiles = ids.compactMap(tile(of:))
        guard layout.isTiled, let first = tiles.first else { return false }
        var path: [Node] = [first]
        while let p = path.last?.parent { path.append(p) }
        // Lowest node that is an ancestor (or self) of every tile.
        var lca: Node = first
        for t in tiles.dropFirst() {
            var anc = Set<ObjectIdentifier>()
            var n: Node? = t
            while let x = n { anc.insert(ObjectIdentifier(x)); n = x.parent }
            while !anc.contains(ObjectIdentifier(lca)), let p = lca.parent { lca = p }
        }
        _ = path
        // Just the touched children of that branch, when that's not all of them.
        var lo = Int.max, hi = -1
        if !lca.isTile {
            for t in tiles {
                var n: Node = t
                while let p = n.parent, p !== lca { n = p }
                if let i = lca.index(of: n) { lo = min(lo, i); hi = max(hi, i) }
            }
        }
        if hi >= 0, hi - lo + 1 < lca.children.count {
            view = lca
            range = lo...hi
        } else {
            view = lca === root ? nil : lca
            range = nil
        }
        pinned = view != nil
        return true
    }

    /// Whether `n` fits in `area` with every tile at least `canvasMin`.
    public func fits(_ n: Node, in area: CGRect, gap: Double) -> Bool {
        let m = TreeLayout.minSize(n, min: canvasMin, gap: gap, ws: self)
        return m.width <= area.width + 0.5 && m.height <= area.height + 0.5
    }

    /// Makes sure `w` is on screen: a zoom that hides it ends; on a canvas the screen shows the
    /// largest branch around it whose tiles all keep their minimum size. True when that changed.
    @discardableResult
    public func frameCamera(on w: WindowID, area: CGRect, gap: Double) -> Bool {
        guard let t = tile(of: w), let root else { return false }
        let under = isShown(t)
        guard layout == .bsp else {
            if under { return false }
            view = nil
            range = nil
            return true
        }
        if under, pinned { return false }
        pinned = false
        var best: Node = t
        while let p = best.parent, fits(p, in: area, gap: gap) { best = p }
        let next: Node? = best === root ? nil : best
        guard next !== view || range != nil else { return false }
        view = next
        range = nil
        return true
    }

    /// How deep the shown branch is, and how deep `w`'s tile is (0 = the whole tree).
    public func zoomDepth(of w: WindowID) -> (level: Int, levels: Int) {
        func depth(_ n: Node?) -> Int {
            var d = 0, x = n
            while let p = x?.parent { d += 1; x = p }
            return d
        }
        return (depth(shownRoot), depth(tile(of: w)))
    }

    // MARK: Moving between tiles

    /// Swaps the window with the visible window of the tile in `dir`.
    @discardableResult
    public func swap(_ w: WindowID, _ dir: Direction, area: CGRect) -> Bool {
        guard let t = tile(of: w), let n = neighbor(of: t, dir, area: area) else { return false }
        return swap(w, with: n)
    }

    @discardableResult
    func swap(_ w: WindowID, with n: Node) -> Bool {
        guard let t = tile(of: w), t !== n, let i = t.windows.firstIndex(of: w), !n.windows.isEmpty else { return false }
        let j = n.windows.indices.contains(n.active) ? n.active : 0
        let other = n.windows[j]
        t.windows[i] = other
        n.windows[j] = w
        return true
    }

    /// Moves the window out of its tile and splits the tile in `dir` with it, on that side.
    @discardableResult
    public func warp(_ w: WindowID, _ dir: Direction, area: CGRect) -> Bool {
        guard let t = tile(of: w) else { return false }
        guard let n = neighbor(of: t, dir, area: area) else {
            // Nothing that way: a stacked window leaves its stack to that side (yabai's warp).
            return t.windows.count > 1 && unstack(w, area: area, toward: dir)
        }
        if t.windows.count == 1, t.parent === n.parent, t.parent?.axis == dir.axis {
            // Siblings: warping is a swap of places.
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
    public func unstack(_ w: WindowID, area: CGRect, toward dir: Direction? = nil) -> Bool {
        guard let t = tile(of: w), t.windows.count > 1 else { return false }
        if layout == .stack { layout = .bsp }
        let frames = TreeLayout.tileFrames(self, in: area, gap: 0, full: true)
        let f = frames[ObjectIdentifier(t)] ?? area
        t.windows.removeAll { $0 == w }
        t.clampActive()
        if let dir {
            split(t, with: Node(windows: [w]), axis: dir.axis, newFirst: dir.isFirst)
        } else {
            split(t, with: Node(windows: [w]), axis: f.width >= f.height ? .horizontal : .vertical, newFirst: false)
        }
        return true
    }

    /// Splits every window of the stack into its own tile.
    public func unstackAll(_ w: WindowID, area: CGRect) {
        while let t = tile(of: w), t.windows.count > 1, let other = t.windows.first(where: { $0 != w }) {
            unstack(other, area: area)
        }
    }

    /// The next window in `w`'s stack; at either end nil, or round to the other end with `wrap`.
    public func cycleStack(_ w: WindowID, by offset: Int, wrap: Bool = false) -> WindowID? {
        guard let t = tile(of: w), t.windows.count > 1, let i = t.windows.firstIndex(of: w) else { return nil }
        let n = t.windows.count
        guard wrap || t.windows.indices.contains(i + offset) else { return nil }
        t.active = ((i + offset) % n + n) % n
        return t.windows[t.active]
    }

    /// Moves `w` one place through its stack, keeping it the visible window; false at either end.
    @discardableResult
    public func moveInStack(_ w: WindowID, by offset: Int) -> Bool {
        guard let t = tile(of: w), let i = t.windows.firstIndex(of: w), t.windows.indices.contains(i + offset) else { return false }
        t.windows.swapAt(i, i + offset)
        t.active = i + offset
        return true
    }

    /// Makes `w` the visible window of its stack.
    public func activate(_ w: WindowID) {
        guard let t = tile(of: w), let i = t.windows.firstIndex(of: w) else { return }
        t.active = i
    }

    // MARK: Sizes

    /// Moves the edge of the window's tile in `dir` by `delta` points (positive grows the tile).
    /// Past a neighbour's minimum the next one gives way too.
    @discardableResult
    public func resize(_ w: WindowID, _ dir: Direction, by delta: Double, area: CGRect) -> Bool {
        guard var child = tile(of: w) else { return false }
        // Sizes as on screen when the split is shown, else on the whole canvas.
        let shown = TreeLayout.nodeFrames(self, in: area, gap: 0)
        let full = TreeLayout.nodeFrames(self, in: area, gap: 0, full: true)
        while let p = child.parent {
            if p.axis == dir.axis, let i = p.index(of: child), let f = shown[ObjectIdentifier(p)] ?? full[ObjectIdentifier(p)] {
                let seam = dir.isFirst ? i - 1 : i
                if p.children.indices.contains(seam), p.children.indices.contains(seam + 1) {
                    let size = dir.axis == .horizontal ? f.width : f.height
                    guard size > 0 else { return false }
                    // The seam moves away from the tile when it grows; it stops where a tile
                    // would get smaller than the minimum.
                    moveSeam(p, seam, by: (dir.isFirst ? -delta : delta) / size, floors: floors(p, length: size))
                    return true
                }
            }
            child = p
        }
        return false
    }

    /// Moves the seam after child `i` of `p` by `fraction` of the split (positive: towards the
    /// end, so child `i` grows). Children on the shrinking side give way one after another,
    /// each down to `minFraction`.
    public func moveSeam(_ p: Node, _ i: Int, by fraction: Double, floors: [Double]? = nil) {
        guard p.children.indices.contains(i), p.children.indices.contains(i + 1), fraction != 0 else { return }
        let floor = floors ?? Array(repeating: Self.minFraction, count: p.children.count)
        var f = p.fractions
        let grow = fraction > 0 ? i : i + 1
        let order = fraction > 0 ? Array((i + 1)..<f.count) : Array((0...i).reversed())
        var need = abs(fraction)
        for j in order where need > 0 {
            let take = min(need, max(0, f[j] - max(Self.minFraction, floor[j])))
            f[j] -= take
            f[grow] += take
            need -= take
        }
        p.weights = f
    }

    /// Puts the seam after child `i` of `p` at `position` (0…1 of the split), `length` points long.
    public func setSeam(_ p: Node, _ i: Int, at position: Double, length: Double? = nil) {
        let f = p.fractions
        guard f.indices.contains(i + 1) else { return }
        let current = f[0...i].reduce(0, +)
        moveSeam(p, i, by: position - current, floors: length.map { floors(p, length: $0) })
    }

    /// The smallest share each child of `p` can have at `length` points: its tiles at their
    /// minimum (`canvasMin`).
    func floors(_ p: Node, length: Double) -> [Double] {
        guard length > 0, canvasMin != .zero else { return p.children.map { _ in Self.minFraction } }
        return p.children.map { c in
            let m = TreeLayout.minSize(c, min: canvasMin, gap: 0)
            return min(0.95, (p.axis == .horizontal ? m.width : m.height) / length)
        }
    }

    /// Gives the two children around the seam after child `i` the same size.
    public func equalizeSeam(_ p: Node, _ i: Int) {
        guard p.weights.indices.contains(i + 1) else { return }
        let avg = (p.weights[i] + p.weights[i + 1]) / 2
        p.weights[i] = avg
        p.weights[i + 1] = avg
    }

    /// The tile that way in the whole tree, on screen or not (zoomed, or off a canvas).
    public func neighbor(of t: Node, _ dir: Direction, area: CGRect) -> Node? {
        let frames = TreeLayout.tileFrames(self, in: area, gap: 0, full: true)
        guard let from = frames[ObjectIdentifier(t)] else { return nil }
        let cands = tiles.compactMap { n -> (Node, CGRect)? in
            guard n !== t, let f = frames[ObjectIdentifier(n)] else { return nil }
            return (n, f)
        }
        return TreeLayout.nearest(from: from, dir, candidates: cands.map(\.1)).map { cands[$0].0 }
    }

    // MARK: Dropping

    /// Moves `w` (tiled, floating or not in this workspace yet) to `target`. False when the
    /// target makes no sense (dropping a window on itself).
    @discardableResult
    public func move(_ w: WindowID, to target: DropTarget, area: CGRect) -> Bool {
        switch target {
        case .swap(let anchor):
            guard anchor != w, let n = tile(of: anchor) else { return false }
            if tile(of: w) != nil { return swap(w, with: n) }
            // Not tiled here: it takes the place, the other one goes on top of it as a stack.
            floating.removeAll { $0 == w }
            n.windows.append(w)
            n.active = n.windows.count - 1
            return true
        case .stack(let anchor):
            guard let n = tile(of: anchor), !n.windows.contains(w) else { return false }
            detach(w)
            guard let n2 = tile(of: anchor) else { return false }
            n2.windows.append(w)
            n2.active = n2.windows.count - 1
            _ = n
            return true
        case .split(let anchor, let side):
            guard anchor != w || (tile(of: w)?.windows.count ?? 0) > 1 else { return false }
            detach(w)
            guard let n = tile(of: anchor) else { return false }
            if layout == .stack || layout == .float { layout = .bsp }
            split(n, with: Node(windows: [w]), axis: side.axis, newFirst: side.isFirst)
            return true
        case .seam(let a, let b, let axis):
            guard a != w || b != w else { return false }
            detach(w)
            guard let ta = tile(of: a), let tb = tile(of: b) else {
                if let t = tile(of: a == w ? b : a) { split(t, with: Node(windows: [w]), axis: axis, newFirst: a == w) }
                return true
            }
            // The split that holds both sides of the seam, along that axis.
            var pathA: [Node] = [ta]
            while let p = pathA.last?.parent { pathA.append(p) }
            var nb: Node? = tb
            while let n = nb {
                if let i = pathA.firstIndex(where: { $0 === n }), i > 0, n.axis == axis {
                    let childA = pathA[i - 1]
                    if let ia = n.index(of: childA) {
                        n.insertChild(Node(windows: [w]), at: ia + 1, weight: 1)
                        n.weights = n.weights.map { _ in 1 }
                        return true
                    }
                }
                nb = n.parent
            }
            split(ta, with: Node(windows: [w]), axis: axis, newFirst: false)
            return true
        case .edge(let side):
            view = nil
            detach(w)
            let new = Node(windows: [w])
            guard let root else { self.root = new; return true }
            if layout == .stack || layout == .float { layout = .bsp }
            if !root.isTile, root.axis == side.axis {
                let avg = root.weights.reduce(0, +) / Double(root.weights.count)
                root.insertChild(new, at: side.isFirst ? 0 : root.children.count, weight: avg)
            } else {
                let s = Node(axis: side.axis, children: side.isFirst ? [new, root] : [root, new],
                             weights: side.isFirst ? [1, 2] : [2, 1])
                self.root = s
                s.parent = nil
            }
            return true
        }
    }

    /// Takes `w` out of the tree or the floating list, keeping everything else.
    private func detach(_ w: WindowID) {
        floating.removeAll { $0 == w }
        if zoomed == w { zoomed = nil }
        guard let t = tile(of: w) else { return }
        t.windows.removeAll { $0 == w }
        t.clampActive()
        if t.windows.isEmpty { removeTile(t) }
    }

    // MARK: Remembering places

    /// Where `w` sits, relative to a window that stays when it leaves.
    public func anchor(of w: WindowID) -> Anchor? {
        guard let t = tile(of: w) else { return nil }
        if t.windows.count > 1, let i = t.windows.firstIndex(of: w), let other = t.windows.first(where: { $0 != w }) {
            return Anchor(neighbor: other, axis: .horizontal, before: false, fraction: 0, stackIndex: i)
        }
        var node = t
        while let p = node.parent, let i = p.index(of: node) {
            // The sibling that takes its space when it goes (see removeTile).
            let j = i > 0 ? i - 1 : i + 1
            if p.children.indices.contains(j) {
                let sib = p.children[j]
                let neighbor = j < i ? sib.allWindows.last : sib.allWindows.first
                if let neighbor {
                    return Anchor(neighbor: neighbor, axis: p.axis, before: i < j, fraction: p.fractions[i], stackIndex: nil)
                }
            }
            node = p
        }
        return nil
    }

    /// Puts `w` back where `anchor` says; false when its neighbour isn't here any more.
    @discardableResult
    public func insert(_ w: WindowID, at anchor: Anchor) -> Bool {
        guard !contains(w), layout.isTiled, let t = tile(of: anchor.neighbor) else { return false }
        if let i = anchor.stackIndex {
            t.windows.insert(w, at: min(i, t.windows.count))
            t.active = t.windows.firstIndex(of: w) ?? t.active
            return true
        }
        let new = Node(windows: [w])
        // The branch holding the neighbour, at the first split along the anchor's axis.
        var node = t
        while let p = node.parent, p.axis != anchor.axis { node = p }
        if let p = node.parent, let i = p.index(of: node) {
            // It takes its share back from the neighbour that got it.
            let f = min(0.9, max(Self.minFraction, anchor.fraction))
            let total = p.weights.reduce(0, +)
            let w = min(f * total, max(0, p.weights[i] - Self.minFraction * total))
            p.weights[i] -= w
            p.insertChild(new, at: anchor.before ? i : i + 1, weight: max(w, Self.minFraction * total))
            return true
        }
        split(node, with: new, axis: anchor.axis, newFirst: anchor.before, share: min(0.9, max(0.1, anchor.fraction)))
        return true
    }

    // MARK: Presets

    /// Builds the tree from a preset: one tile per entry, in a row (or column), sized by
    /// weights. Windows go to tiles by `assign`; the rest are inserted after.
    public func arrange(_ preset: WorkspacePreset, windows: [(id: WindowID, app: String)], area: CGRect) {
        arrange(preset, windows: windows.map { (id: $0.id, app: $0.app, title: "") }, area: area)
    }

    public func arrange(_ preset: WorkspacePreset, windows: [(id: WindowID, app: String, title: String)], area: CGRect) {
        let all = allWindows
        let focus = focused
        root = nil
        floating = floating.filter { all.contains($0) }
        let tiled = windows.filter { !floating.contains($0.id) }
        if let l = preset.layout { layout = l }
        var placed = Set<WindowID>()
        var nodes: [Node] = Array(repeating: Node(), count: 0)
        for (i, _) in preset.tiles.enumerated() {
            let n = Node()
            n.slot = i
            nodes.append(n)
        }
        // Windows go to the tile `slot(for:title:)` picks (titled tiles first), apps in tile order.
        for (i, t) in preset.tiles.enumerated() {
            for pattern in t.apps {
                for w in tiled where !placed.contains(w.id) && AppMatcher.matches(pattern, w.app)
                    && preset.slot(for: w.app, title: w.title) == i {
                    nodes[i].windows.append(w.id)
                    placed.insert(w.id)
                }
            }
        }
        if layout == .stack {
            let t = Node(windows: nodes.flatMap(\.windows))
            root = t.windows.isEmpty ? nil : t
        } else {
            // Empty preset tiles take no space until a window lands there.
            let filled = nodes.enumerated().filter { !$0.element.windows.isEmpty }
            let weights = filled.map { max(0.05, preset.tiles[$0.offset].size ?? 1) }
            switch filled.count {
            case 0: root = nil
            case 1: root = filled[0].element
            default: root = Node(axis: preset.axis, children: filled.map(\.element), weights: weights)
            }
        }
        for w in tiled where !placed.contains(w.id) {
            if let slot = preset.slot(for: w.app, title: w.title) { insert(w.id, area: area, slot: slot) } else { insert(w.id, area: area) }
        }
        focused = focus.flatMap { contains($0) ? $0 : nil } ?? tiledWindows.first
    }

    // MARK: Snapshots

    public func snapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(layout: layout, root: root.map(TreeSnapshot.init), floating: floating, focused: focused, zoomed: zoomed)
    }

    /// Puts the tree back as `s` had it. Windows no longer here are left out; windows here now
    /// that `s` didn't have are added the usual way.
    public func restore(_ s: WorkspaceSnapshot, area: CGRect) {
        let present = Set(allWindows)
        let floatingNow = Set(floating)
        layout = s.layout
        root = s.root.flatMap { $0.node(keeping: present) }
        root?.parent = nil
        // Collapse splits emptied by windows that are gone.
        for sp in splits.reversed() where sp.children.count < 2 { collapse(sp) }
        floating = s.floating.filter { present.contains($0) }
        let have = Set(allWindows)
        for w in present.subtracting(have).sorted() {
            insert(w, area: area, floating: floatingNow.contains(w))
        }
        focused = s.focused.flatMap { present.contains($0) ? $0 : nil } ?? focused.flatMap { present.contains($0) ? $0 : nil }
        zoomed = s.zoomed.flatMap { tile(of: $0) != nil ? $0 : nil }
    }

    /// A copy to try things on (drop previews).
    public func clone() -> Workspace {
        let w = Workspace(name: name, layout: layout)
        w.root = root?.copy()
        w.canvasMin = canvasMin
        w.windowMins = windowMins
        // The same branch shown in the copy, found by its path from the root.
        if let v = view {
            var path: [Int] = []
            var n = v
            while let p = n.parent, let i = p.index(of: n) { path.insert(i, at: 0); n = p }
            var c = w.root
            for i in path { c = c?.children[safe: i] }
            w.view = c
            w.range = range
        }
        w.floating = floating
        w.focused = focused
        w.zoomed = zoomed
        return w
    }
}

/// A workspace's tree as plain data: undo, and paw's state file across restarts.
public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public var layout: LayoutKind
    public var root: TreeSnapshot?
    public var floating: [WindowID]
    public var focused: WindowID?
    public var zoomed: WindowID?
}

public struct TreeSnapshot: Codable, Equatable, Sendable {
    public var axis: Axis?
    public var weights: [Double]?
    public var children: [TreeSnapshot]?
    public var windows: [WindowID]?
    public var active: Int?
    public var slot: Int?

    init(_ n: Node) {
        if n.isTile {
            windows = n.windows
            active = n.active
            slot = n.slot
        } else {
            axis = n.axis
            weights = n.weights
            children = n.children.map(TreeSnapshot.init)
        }
    }

    /// The node, without windows outside `keeping` and without tiles left empty.
    func node(keeping: Set<WindowID>) -> Node? {
        if let children, let axis {
            var kept: [(Node, Double)] = []
            for (i, c) in children.enumerated() {
                guard let n = c.node(keeping: keeping) else { continue }
                kept.append((n, weights?[safe: i] ?? 1))
            }
            switch kept.count {
            case 0: return nil
            case 1: return kept[0].0
            default: return Node(axis: axis, children: kept.map(\.0), weights: kept.map(\.1))
            }
        }
        let ws = (windows ?? []).filter { keeping.contains($0) }
        guard !ws.isEmpty else { return nil }
        let n = Node(windows: ws)
        n.slot = slot
        if let a = active, let w = windows?[safe: a], let i = ws.firstIndex(of: w) { n.active = i }
        return n
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
