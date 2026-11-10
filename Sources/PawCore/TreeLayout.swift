import CoreGraphics

/// Turns a workspace tree into frames (top-left origin) and finds neighbours by geometry.
public enum TreeLayout {
    /// Frame of every node.
    /// `full`: the whole tree (on a canvas, at its full size, which can be larger than `area`)
    /// instead of only the branch on screen.
    public static func nodeFrames(_ ws: Workspace, in area: CGRect, gap: Double, full: Bool = false) -> [ObjectIdentifier: CGRect] {
        var out: [ObjectIdentifier: CGRect] = [:]
        func walk(_ n: Node, _ r: CGRect) {
            out[ObjectIdentifier(n)] = r
            guard !n.isTile else { return }
            for (c, f) in zip(n.children, childFrames(n, in: r, gap: gap)) { walk(c, f) }
        }
        if full {
            if let root = ws.root { walk(root, canvas(ws, in: area, gap: gap)) }
        } else if let top = ws.shownRoot {
            if let r = ws.shownRange {
                // A picked region: only those children, sharing the area by their weights.
                let sub = Node(axis: top.axis, children: [], weights: [])
                let kids = Array(top.children[r]), ws2 = Array(top.weights[r])
                out[ObjectIdentifier(top)] = area
                let frames = childFrames(axis: top.axis, weights: ws2, in: area, gap: gap)
                _ = sub
                for (c, f) in zip(kids, frames) { walk(c, f) }
            } else {
                walk(top, area)
            }
        }
        return out
    }

    /// Every tiled window where the camera puts it: the whole tree laid out on the screen, then
    /// stretched so the branch on screen fills `area`. Windows outside that branch land off
    /// screen, where they'd be, so zooming can glide them in and out.
    public static func cameraFrames(_ ws: Workspace, in area: CGRect, gap: Double) -> [WindowID: CGRect] {
        guard let root = ws.root else { return [:] }
        var frames: [ObjectIdentifier: CGRect] = [:]
        func walk(_ n: Node, _ r: CGRect) {
            frames[ObjectIdentifier(n)] = r
            for (c, f) in zip(n.children, childFrames(n, in: r, gap: gap)) { walk(c, f) }
        }
        walk(root, area)
        var cam = ws.shownRoot.flatMap { frames[ObjectIdentifier($0)] } ?? area
        if let s = ws.shownRoot, let r = ws.shownRange {
            // The picked children only.
            cam = s.children[r].compactMap { frames[ObjectIdentifier($0)] }.reduce(CGRect.null) { $0.union($1) }
        }
        let sx = area.width / max(1, cam.width), sy = area.height / max(1, cam.height)
        var out: [WindowID: CGRect] = [:]
        for t in ws.tiles {
            guard let f = frames[ObjectIdentifier(t)] else { continue }
            let m = CGRect(x: area.minX + (f.minX - cam.minX) * sx, y: area.minY + (f.minY - cam.minY) * sy,
                           width: f.width * sx, height: f.height * sy).integral
            for w in t.windows { out[w] = m }
        }
        // Inside the branch, the real layout (gaps stay gaps).
        for (w, f) in windowFrames(ws, in: area, gap: gap) { out[w] = f }
        return out
    }

    /// The smallest size `n` fits in with every tile at least `min`, given its weights.
    public static func minSize(_ n: Node, min: CGSize, gap: Double, ws: Workspace? = nil) -> CGSize {
        guard !n.isTile else { return min }
        let kids = n.children.map { minSize($0, min: min, gap: gap, ws: ws) }
        let f = n.fractions
        let gaps = gap * Double(max(0, kids.count - 1))
        if n.axis == .horizontal {
            let w = zip(kids, f).map { $0.0.width / max(0.0001, $0.1) }.max() ?? 0
            return CGSize(width: w + gaps, height: kids.map(\.height).max() ?? 0)
        }
        let h = zip(kids, f).map { $0.0.height / max(0.0001, $0.1) }.max() ?? 0
        return CGSize(width: kids.map(\.width).max() ?? 0, height: h + gaps)
    }

    /// Where the whole tree lies: `area`, or on a canvas larger when its tiles need more room.
    public static func canvas(_ ws: Workspace, in area: CGRect, gap: Double) -> CGRect {
        guard ws.layout == .bsp, let root = ws.root else { return area }
        let m = minSize(root, min: ws.canvasMin, gap: gap, ws: ws)
        return CGRect(x: area.minX, y: area.minY, width: max(area.width, m.width.rounded(.up)), height: max(area.height, m.height.rounded(.up)))
    }

    /// Frames of a split's children: its length minus the gaps, shared by weight, rounded so
    /// the pieces add up exactly.
    public static func childFrames(_ n: Node, in r: CGRect, gap: Double) -> [CGRect] {
        childFrames(axis: n.axis, weights: n.weights, in: r, gap: gap)
    }

    public static func childFrames(axis: Axis, weights: [Double], in r: CGRect, gap: Double) -> [CGRect] {
        let count = weights.count
        guard count > 0 else { return [] }
        let total = weights.reduce(0, +)
        let fractions = total > 0 ? weights.map { $0 / total } : weights.map { _ in 1 / Double(count) }
        let horizontal = axis == .horizontal
        let length = (horizontal ? r.width : r.height) - gap * Double(count - 1)
        var out: [CGRect] = []
        var acc = 0.0
        var pos = horizontal ? r.minX : r.minY
        for (i, f) in fractions.enumerated() {
            let start = (length * acc).rounded()
            acc += f
            let end = i == count - 1 ? length : (length * acc).rounded()
            let size = max(0, end - start)
            out.append(horizontal ? CGRect(x: pos, y: r.minY, width: size, height: r.height)
                                  : CGRect(x: r.minX, y: pos, width: r.width, height: size))
            pos += size + gap
        }
        return out
    }

    /// The seams of every split: the gap between neighbouring children, `index` being the child
    /// before it.
    public struct Seam: Equatable {
        public let split: ObjectIdentifier
        public let index: Int
        public let axis: Axis
        /// The gap itself (at least 1 pt wide).
        public let frame: CGRect
        /// The split's frame, to turn pointer positions into fractions.
        public let splitFrame: CGRect
    }

    public static func seams(_ ws: Workspace, in area: CGRect, gap: Double, full: Bool = false) -> [Seam] {
        let frames = nodeFrames(ws, in: area, gap: gap, full: full)
        var out: [Seam] = []
        for s in ws.splits {
            guard let r = frames[ObjectIdentifier(s)] else { continue }
            let kids = s.children.compactMap { frames[ObjectIdentifier($0)] }
            guard kids.count == s.children.count else { continue }
            for i in 0..<(kids.count - 1) {
                let a = kids[i], b = kids[i + 1]
                let f = s.axis == .horizontal
                    ? CGRect(x: a.maxX, y: r.minY, width: max(1, b.minX - a.maxX), height: r.height)
                    : CGRect(x: r.minX, y: a.maxY, width: r.width, height: max(1, b.minY - a.maxY))
                out.append(Seam(split: ObjectIdentifier(s), index: i, axis: s.axis, frame: f, splitFrame: r))
            }
        }
        return out
    }

    public static func tileFrames(_ ws: Workspace, in area: CGRect, gap: Double, full: Bool = false) -> [ObjectIdentifier: CGRect] {
        let all = nodeFrames(ws, in: area, gap: gap, full: full)
        var out: [ObjectIdentifier: CGRect] = [:]
        for t in ws.tiles { out[ObjectIdentifier(t)] = all[ObjectIdentifier(t)] }
        return out
    }

    /// Where every tiled window goes. Stacked windows share their tile's frame; a zoomed
    /// window takes the whole area.
    public static func windowFrames(_ ws: Workspace, in area: CGRect, gap: Double, full: Bool = false) -> [WindowID: CGRect] {
        var out: [WindowID: CGRect] = [:]
        let frames = tileFrames(ws, in: area, gap: gap, full: full)
        for t in ws.tiles {
            guard let f = frames[ObjectIdentifier(t)] else { continue }
            for w in t.windows { out[w] = f }
        }
        if !full, let z = ws.zoomed, out[z] != nil { out[z] = area }
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
