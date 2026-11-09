import CoreGraphics

/// Turns a workspace tree into frames (top-left origin) and finds neighbours by geometry.
public enum TreeLayout {
    /// Frame of every node.
    public static func nodeFrames(_ ws: Workspace, in area: CGRect, gap: Double) -> [ObjectIdentifier: CGRect] {
        var out: [ObjectIdentifier: CGRect] = [:]
        func walk(_ n: Node, _ r: CGRect) {
            out[ObjectIdentifier(n)] = r
            guard !n.isTile, let a = n.first, let b = n.second else { return }
            if n.axis == .horizontal {
                let w = ((r.width - gap) * n.ratio).rounded()
                walk(a, CGRect(x: r.minX, y: r.minY, width: w, height: r.height))
                walk(b, CGRect(x: r.minX + w + gap, y: r.minY, width: r.width - w - gap, height: r.height))
            } else {
                let h = ((r.height - gap) * n.ratio).rounded()
                walk(a, CGRect(x: r.minX, y: r.minY, width: r.width, height: h))
                walk(b, CGRect(x: r.minX, y: r.minY + h + gap, width: r.width, height: r.height - h - gap))
            }
        }
        if let root = ws.root { walk(root, area) }
        return out
    }

    public static func tileFrames(_ ws: Workspace, in area: CGRect, gap: Double) -> [ObjectIdentifier: CGRect] {
        let all = nodeFrames(ws, in: area, gap: gap)
        var out: [ObjectIdentifier: CGRect] = [:]
        for t in ws.tiles { out[ObjectIdentifier(t)] = all[ObjectIdentifier(t)] }
        return out
    }

    /// Where every tiled window goes. Stacked windows share their tile's frame; a zoomed
    /// window takes the whole area.
    public static func windowFrames(_ ws: Workspace, in area: CGRect, gap: Double) -> [WindowID: CGRect] {
        var out: [WindowID: CGRect] = [:]
        let frames = tileFrames(ws, in: area, gap: gap)
        for t in ws.tiles {
            guard let f = frames[ObjectIdentifier(t)] else { continue }
            for w in t.windows { out[w] = f }
        }
        if let z = ws.zoomed, out[z] != nil { out[z] = area }
        return out
    }

    /// Index of the candidate nearest to `from` in `dir`: it must lie on that side and overlap
    /// on the other axis; closest edge wins, then the larger overlap, then the closer centre.
    public static func nearest(from: CGRect, _ dir: Direction, candidates: [CGRect]) -> Int? {
        let eps: CGFloat = 1
        var best: (i: Int, dist: CGFloat, overlap: CGFloat, centre: CGFloat)?
        for (i, c) in candidates.enumerated() {
            let dist: CGFloat, overlap: CGFloat
            switch dir {
            case .west:
                guard c.maxX <= from.minX + eps else { continue }
                dist = from.minX - c.maxX
                overlap = min(from.maxY, c.maxY) - max(from.minY, c.minY)
            case .east:
                guard c.minX >= from.maxX - eps else { continue }
                dist = c.minX - from.maxX
                overlap = min(from.maxY, c.maxY) - max(from.minY, c.minY)
            case .north:
                guard c.maxY <= from.minY + eps else { continue }
                dist = from.minY - c.maxY
                overlap = min(from.maxX, c.maxX) - max(from.minX, c.minX)
            case .south:
                guard c.minY >= from.maxY - eps else { continue }
                dist = c.minY - from.maxY
                overlap = min(from.maxX, c.maxX) - max(from.minX, c.minX)
            }
            guard overlap > 0 else { continue }
            let centre = dir.axis == .horizontal ? abs(c.midY - from.midY) : abs(c.midX - from.midX)
            if let b = best {
                if dist < b.dist - eps || (abs(dist - b.dist) <= eps && (overlap > b.overlap + eps || (abs(overlap - b.overlap) <= eps && centre < b.centre))) {
                    best = (i, dist, overlap, centre)
                }
            } else {
                best = (i, dist, overlap, centre)
            }
        }
        return best?.i
    }

    /// The tiling area of a screen: its visible frame minus a bar and padding (all top-left origin).
    public static func area(screen: CGRect, visible: CGRect, barTop: Double, barBottom: Double, padding: Padding) -> CGRect {
        let topUsed = visible.minY - screen.minY
        let bottomUsed = screen.maxY - visible.maxY
        let top = max(0, barTop - topUsed) + padding.top
        let bottom = max(0, barBottom - bottomUsed) + padding.bottom
        return CGRect(x: visible.minX + padding.left, y: visible.minY + top,
                      width: max(1, visible.width - padding.left - padding.right),
                      height: max(1, visible.height - top - bottom))
    }
}

public struct Padding: Codable, Equatable, Sendable {
    public var top = 2.0, bottom = 2.0, left = 24.0, right = 24.0
    public init(top: Double = 2, bottom: Double = 2, left: Double = 24, right: Double = 24) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case top, bottom, left, right }
    public init(from decoder: Decoder) throws {
        let f = Fields(c: try decoder.container(keyedBy: CodingKeys.self))
        try f(.top, &top); try f(.bottom, &bottom); try f(.left, &left); try f(.right, &right)
    }
}
