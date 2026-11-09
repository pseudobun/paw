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

    /// Intersection over union of two rectangles (0 when they don't touch).
    public static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }

    /// Indices to keep so that no two frames overlap by more than `threshold` (IoU) or
    /// share a top-left corner (labels would sit on top of each other). Earlier frames win,
    /// so callers order by priority.
    public static func dedupe(_ frames: [CGRect], threshold: CGFloat = 0.8, cornerTolerance: CGFloat = 3) -> [Int] {
        var kept: [Int] = []
        kept.reserveCapacity(frames.count)
        outer: for (i, f) in frames.enumerated() {
            guard f.width > 0, f.height > 0 else { continue }
            for j in kept {
                let g = frames[j]
                if abs(f.minX - g.minX) <= cornerTolerance, abs(f.minY - g.minY) <= cornerTolerance { continue outer }
                if iou(f, g) >= threshold { continue outer }
            }
            kept.append(i)
        }
        return kept
    }

    /// Where to click: the centre of the part of `frame` inside `clip`.
    public static func clickPoint(_ frame: CGRect, clip: CGRect?) -> CGPoint {
        var r = frame
        if let clip {
            let i = frame.intersection(clip)
            if !i.isNull, i.width > 0, i.height > 0 { r = i }
        }
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Positions a label of `size` at the element's top-left inside `bounds` (AX coordinates).
    public static func labelOrigin(for element: CGRect, size: CGSize, anchor: LabelAnchor, bounds: CGRect) -> CGPoint {
        var p: CGPoint
        switch anchor {
        case .topLeft: p = CGPoint(x: element.minX, y: element.minY)
        case .left: p = CGPoint(x: element.minX, y: element.midY - size.height / 2)
        case .center: p = CGPoint(x: element.midX - size.width / 2, y: element.midY - size.height / 2)
        }
        p.x = min(max(p.x, bounds.minX), bounds.maxX - size.width)
        p.y = min(max(p.y, bounds.minY), bounds.maxY - size.height)
        return p
    }
}

public enum LabelAnchor: String, Codable, Sendable, CaseIterable {
    case topLeft, left, center
}
