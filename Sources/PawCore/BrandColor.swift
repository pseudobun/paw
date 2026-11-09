import Foundation

/// An app's own colour, picked from its icon: the most common saturated hue (white, black and
/// grey pixels don't count), brightened so it reads on a dark island.
public enum BrandColor {
    /// `rgba`: 8-bit RGBA pixels, premultiplied or not (only opaque pixels count).
    public static func pick(rgba: [UInt8]) -> ARGB? {
        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var sum = [(r: Double, g: Double, b: Double, w: Double)](repeating: (0, 0, 0, 0), count: bins)
        var opaque = 0.0
        for i in stride(from: 0, to: rgba.count - 3, by: 4) {
            let a = Double(rgba[i + 3]) / 255
            guard a > 0.6 else { continue }
            opaque += 1
            let r = Double(rgba[i]) / 255 / a, g = Double(rgba[i + 1]) / 255 / a, b = Double(rgba[i + 2]) / 255 / a
            let (h, s, v) = hsv(min(r, 1), min(g, 1), min(b, 1))
            guard s > 0.3, v > 0.25 else { continue }
            let bin = min(bins - 1, Int(h * Double(bins)))
            let w = s * v
            weight[bin] += w
            sum[bin].r += r * w; sum[bin].g += g * w; sum[bin].b += b * w; sum[bin].w += w
        }
        // Count neighbouring bins too, so a hue on a bin edge isn't split in two.
        var best = -1, bestScore = 0.0
        for i in 0..<bins {
            let score = weight[i] + 0.5 * (weight[(i + 1) % bins] + weight[(i + bins - 1) % bins])
            if score > bestScore { bestScore = score; best = i }
        }
        // Mostly grey icons (Finder's face is blue enough; a plain grey gear isn't).
        guard best >= 0, opaque > 0, bestScore / opaque > 0.04, sum[best].w > 0 else { return nil }
        let w = sum[best].w
        var (h, s, v) = hsv(sum[best].r / w, sum[best].g / w, sum[best].b / w)
        v = max(v, 0.85)
        s = min(s, 0.85)
        var (r, g, b) = rgb(h, s, v)
        // Deep blues and purples are bright by HSV but dark to the eye: mix in white until they read.
        while 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.4 {
            r += (1 - r) * 0.1; g += (1 - g) * 0.1; b += (1 - b) * 0.1
        }
        func byte(_ x: Double) -> UInt32 { UInt32((max(0, min(1, x)) * 255).rounded()) }
        return ARGB(0xff00_0000 | byte(r) << 16 | byte(g) << 8 | byte(b))
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
