import CoreGraphics

/// Where a tiled window dropped at a point lands (TrellisWM-style zones): the band along the
/// workspace's edge docks beside everything, the gap between tiles makes room there, a tile's
/// outer 28% splits it on that side, its middle swaps (or stacks).
public enum DropZones {
    /// Share of a tile, from each edge, that splits it instead of swapping.
    public static let edgeShare = 0.28
    /// How far either side of a seam still counts as the seam.
    public static let seamSlop = 10.0
    /// How far inside the workspace's edge still docks beside everything.
    public static let edgeBand = 6.0

    /// `full`: `area` holds the whole tree (the overview's canvas), not just what's on screen.
    public static func target(at p: CGPoint, in ws: Workspace, area: CGRect, gap: Double, dragging id: WindowID,
                              stack: Bool, full: Bool = false) -> DropTarget? {
        guard ws.root != nil else { return .edge(.east) }
        let inner = area.insetBy(dx: edgeBand, dy: edgeBand)
        if !inner.contains(p), area.insetBy(dx: -80, dy: -80).contains(p) {
            let d: [(Direction, Double)] = [(.west, p.x - area.minX), (.east, area.maxX - p.x),
                                            (.north, p.y - area.minY), (.south, area.maxY - p.y)]
            return .edge(d.min { $0.1 < $1.1 }!.0)
        }
        let frames = TreeLayout.nodeFrames(ws, in: area, gap: gap, full: full)
        for s in TreeLayout.seams(ws, in: area, gap: gap, full: full) {
            let hit = s.axis == .horizontal ? s.frame.insetBy(dx: -seamSlop, dy: 0) : s.frame.insetBy(dx: 0, dy: -seamSlop)
            guard hit.contains(p), let node = ws.splits.first(where: { ObjectIdentifier($0) == s.split }) else { continue }
            let before = node.children[s.index], after = node.children[s.index + 1]
            // Next to its own lone tile the seam is where the window already is.
            if before.isTile && before.windows == [id] || after.isTile && after.windows == [id] { return nil }
            guard let a = before.allWindows.last, let b = after.allWindows.first else { continue }
            return .seam(before: a, after: b, axis: s.axis)
        }
        guard let t = ws.tiles.first(where: { frames[ObjectIdentifier($0)]?.contains(p) == true }),
              let f = frames[ObjectIdentifier(t)], f.width > 0, f.height > 0 else { return nil }
        let own = t.windows.contains(id)
        if own && t.windows.count == 1 { return nil }
        guard let anchor = own ? t.windows.first(where: { $0 != id }) : t.activeWindow else { return nil }
        let fx = (p.x - f.minX) / f.width, fy = (p.y - f.minY) / f.height
        let edges: [(Direction, Double)] = [(.west, fx), (.east, 1 - fx), (.north, fy), (.south, 1 - fy)]
        let nearest = edges.min { $0.1 < $1.1 }!
        if nearest.1 < edgeShare { return .split(tile: anchor, side: nearest.0) }
        if own { return nil }
        return stack ? .stack(tile: anchor) : .swap(tile: anchor)
    }

    /// The frame the window would get, tried on a copy of the workspace.
    public static func preview(_ target: DropTarget, in ws: Workspace, area: CGRect, gap: Double, dragging id: WindowID,
                               full: Bool = false) -> CGRect? {
        let copy = ws.clone()
        if !copy.contains(id) { copy.floating.append(id) }
        guard copy.move(id, to: target, area: area) else { return nil }
        return TreeLayout.windowFrames(copy, in: area, gap: gap, full: full)[id]
    }
}
