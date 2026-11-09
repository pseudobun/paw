import CoreGraphics
import Foundation

/// Animation curves for window moves (`animation.curve`).
public enum Easing: String, Codable, Sendable, CaseIterable {
    case linear, easeOutCubic, easeInOutCubic, easeOutQuint, easeOutBack, spring

    public func value(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        switch self {
        case .linear: return t
        case .easeOutCubic: return 1 - pow(1 - t, 3)
        case .easeInOutCubic: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .easeOutQuint: return 1 - pow(1 - t, 5)
        case .easeOutBack:
            let c1 = 1.20158, c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        case .spring:
            // Critically damped-ish spring settling at 1.
            return 1 - exp(-7 * t) * cos(5 * t)
        }
    }

    public static func lerp(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
        func l(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * p }
        return CGRect(x: l(a.minX, b.minX), y: l(a.minY, b.minY), width: l(a.width, b.width), height: l(a.height, b.height)).integral
    }
}
