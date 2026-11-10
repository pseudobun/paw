import CoreGraphics

/// Geometry of the overview on one display (top-left origin, points): a search pill at the
/// top, a rail of workspace cards under it, and a stage showing the selected workspace large.
public struct OverviewLayout: Equatable, Sendable {
    public var bounds: CGRect
    public var search: CGRect
    public var rail: CGRect
    /// One card per workspace, in order; the last extra card (if any) is "new workspace".
    public var cards: [CGRect]
    public var stage: CGRect
    public var footer: CGRect

    public static let margin: CGFloat = 32
    public static let cardGap: CGFloat = 16

    /// `aspect`: width / height of the workspaces' area. `top`: room taken by a menu bar.
    public init(bounds: CGRect, top: CGFloat, cardCount: Int, aspect: CGFloat) {
        self.bounds = bounds
        let m = Self.margin
        let aspect = max(0.3, min(4, aspect))
        search = CGRect(x: (bounds.midX - 210).rounded(), y: bounds.minY + top + 20, width: 420, height: 34)
        let railTop = search.maxY + 18
        var cardH = min(150, max(70, bounds.height * 0.13))
        var cardW = cardH * aspect
        let available = bounds.width - 2 * m
        let n = CGFloat(max(1, cardCount))
        let needed = n * cardW + (n - 1) * Self.cardGap
        if needed > available {
            let k = (available - (n - 1) * Self.cardGap) / (n * cardW)
            cardW *= k
            cardH *= k
        }
        let total = n * cardW + (n - 1) * Self.cardGap
        var x = bounds.minX + ((bounds.width - total) / 2).rounded()
        cards = (0..<max(0, cardCount)).map { _ in
            defer { x += cardW + Self.cardGap }
            return CGRect(x: x.rounded(), y: railTop + 18, width: cardW.rounded(), height: cardH.rounded())
        }
        // 18 pt above the cards for their labels.
        rail = CGRect(x: bounds.minX + m, y: railTop, width: bounds.width - 2 * m, height: cardH + 18)
        footer = CGRect(x: bounds.minX + m, y: bounds.maxY - m - 18, width: bounds.width - 2 * m, height: 18)
        // Room between the cards and the stage for the stage's header.
        let headroom: CGFloat = 60
        let room = CGRect(x: bounds.minX + m * 2, y: rail.maxY + headroom, width: bounds.width - m * 4,
                          height: max(40, footer.minY - 20 - (rail.maxY + headroom)))
        stage = Self.fit(aspect: aspect, in: room)
    }

    /// The largest rect of that aspect centred in `r`.
    public static func fit(aspect: CGFloat, in r: CGRect) -> CGRect {
        var w = r.width, h = w / aspect
        if h > r.height { h = r.height; w = h * aspect }
        return CGRect(x: (r.midX - w / 2).rounded(), y: (r.midY - h / 2).rounded(), width: w.rounded(), height: h.rounded())
    }

    /// A frame relative to the workspace area (0…1) placed in `container`.
    public static func place(_ rel: CGRect, in container: CGRect) -> CGRect {
        CGRect(x: container.minX + rel.minX * container.width, y: container.minY + rel.minY * container.height,
               width: rel.width * container.width, height: rel.height * container.height)
    }

    /// A point in `container` back in the workspace's own (AX) coordinates.
    public static func unplace(_ p: CGPoint, from container: CGRect, to area: CGRect) -> CGPoint {
        CGPoint(x: area.minX + (p.x - container.minX) / max(1, container.width) * area.width,
                y: area.minY + (p.y - container.minY) / max(1, container.height) * area.height)
    }

    /// The same rect mapped from the workspace's AX area into `container`.
    public static func place(ax r: CGRect, area: CGRect, in container: CGRect) -> CGRect {
        let rel = CGRect(x: (r.minX - area.minX) / area.width, y: (r.minY - area.minY) / area.height,
                         width: r.width / area.width, height: r.height / area.height)
        return place(rel, in: container)
    }

    /// Index of the frame nearest to `from` in `dir` (same rules as focusing tiles).
    public static func neighbor(of from: CGRect, _ dir: Direction, among frames: [CGRect]) -> Int? {
        if let i = TreeLayout.nearest(from: from, dir, candidates: frames) { return i }
        // Floating windows overlap; fall back to centres on that side.
        var best: (Int, CGFloat)?
        for (i, f) in frames.enumerated() where f != from {
            let d: CGFloat
            switch dir {
            case .west: guard f.midX < from.midX - 1 else { continue }; d = from.midX - f.midX + abs(f.midY - from.midY) * 2
            case .east: guard f.midX > from.midX + 1 else { continue }; d = f.midX - from.midX + abs(f.midY - from.midY) * 2
            case .north: guard f.midY < from.midY - 1 else { continue }; d = from.midY - f.midY + abs(f.midX - from.midX) * 2
            case .south: guard f.midY > from.midY + 1 else { continue }; d = f.midY - from.midY + abs(f.midX - from.midX) * 2
            }
            if best.map({ d < $0.1 }) ?? true { best = (i, d) }
        }
        return best?.0
    }
}
