import CoreGraphics

/// Where a stack's indicator goes: a vertical island next to the window, on the side nearer
/// the screen edge (like stackline), kept on screen.
public enum IndicatorLayout {
    public enum Side: String, Codable, Sendable, CaseIterable {
        case auto, left, right, insideLeft, insideRight
    }

    public struct Metrics: Equatable, Sendable {
        public var width: Double
        public var cellHeight: Double
        public var gap: Double
        public var padding: Double
        public var offsetX: Double
        public var offsetY: Double

        public init(width: Double = 28, cellHeight: Double = 22, gap: Double = 2, padding: Double = 3, offsetX: Double = 4, offsetY: Double = 2) {
            self.width = width
            self.cellHeight = cellHeight
            self.gap = gap
            self.padding = padding
            self.offsetX = offsetX
            self.offsetY = offsetY
        }

        public func height(cells n: Int) -> Double {
            padding * 2 + Double(n) * cellHeight + Double(max(0, n - 1)) * gap
        }
    }

    /// stackline's rule: a window whose left edge is past the first quarter of the screen and
    /// whose right edge is in the last quarter gets its indicator on the right; the rest left.
    public static func resolve(_ side: Side, window: CGRect, screen: CGRect) -> Side {
        guard side == .auto else { return side }
        let w = screen.width
        guard w > 0 else { return .left }
        let percR = (window.maxX - screen.minX) / w
        let percL = (screen.maxX - window.minX) / w
        return percR > 0.75 && percL < 0.75 ? .right : .left
    }

    /// The island's frame (top-left origin) for a stack of `count` windows.
    public static func frame(window: CGRect, screen: CGRect, count: Int, side: Side, metrics m: Metrics) -> (CGRect, Side) {
        let s = resolve(side, window: window, screen: screen)
        let w = m.width, h = m.height(cells: count)
        var x: Double
        switch s {
        case .right: x = window.maxX + m.offsetX
        case .insideLeft: x = window.minX + m.offsetX
        case .insideRight: x = window.maxX - w - m.offsetX
        default: x = window.minX - w - m.offsetX
        }
        x = min(max(x, screen.minX), screen.maxX - w)
        var y = window.minY + m.offsetY
        y = min(max(y, screen.minY), screen.maxY - h)
        return (CGRect(x: x, y: y, width: w, height: h), s)
    }

    /// Cell `i` inside the island (top-left origin, relative to the island).
    public static func cell(_ i: Int, metrics m: Metrics) -> CGRect {
        CGRect(x: m.padding, y: m.padding + Double(i) * (m.cellHeight + m.gap), width: m.width - m.padding * 2, height: m.cellHeight)
    }

    /// Which cell a point (relative to the island, top-left origin) is in.
    public static func cellIndex(at p: CGPoint, count: Int, metrics m: Metrics) -> Int? {
        for i in 0..<count {
            let c = cell(i, metrics: m).insetBy(dx: 0, dy: -m.gap / 2)
            if c.contains(p) { return i }
        }
        return nil
    }
}
