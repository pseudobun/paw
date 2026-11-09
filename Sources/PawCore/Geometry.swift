import CoreGraphics

/// Accessibility and Quartz use global coordinates with the origin at the top-left of the
/// primary display and y growing down; AppKit uses the bottom-left of the primary display
/// and y growing up. Both span every display, so one formula converts any screen.
public enum ScreenGeometry {
    public static func cocoa(fromAX r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The conversion is its own inverse.
    public static func ax(fromCocoa r: CGRect, primaryHeight: CGFloat) -> CGRect {
        cocoa(fromAX: r, primaryHeight: primaryHeight)
    }

    public static func cocoa(fromAX p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// A screen's frame (Cocoa) in AX coordinates.
    public static func axFrame(ofScreen cocoaFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        ax(fromCocoa: cocoaFrame, primaryHeight: primaryHeight)
    }

    /// Index of the screen (AX frames) that holds most of `rect`, or the one nearest to its centre.
    public static func screenIndex(for rect: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var best: (Int, CGFloat)? = nil
        for (i, s) in screens.enumerated() {
            let inter = s.intersection(rect)
            guard !inter.isNull else { continue }
            let area = inter.width * inter.height
            if area > (best?.1 ?? -1) { best = (i, area) }
        }
        if let best { return best.0 }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return screens.indices.min { distance(c, screens[$0]) < distance(c, screens[$1]) }
    }

    /// Point → rectangle distance (0 inside).
    static func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// `rect` (AX, global) relative to its screen (AX frame), in the screen's bottom-left
    /// layer coordinates: where an overlay window covering that screen draws it.
    public static func layerRect(_ rect: CGRect, inScreen screen: CGRect) -> CGRect {
        CGRect(x: rect.minX - screen.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
