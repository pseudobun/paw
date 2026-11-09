/// Rate-based scrolling: a held key scrolls at `speed` pixels per millisecond, easing in over
/// `rampMs` so a tap moves a little and a hold glides. Fractions carry over between frames
/// so slow speeds stay smooth at 120 Hz.
public struct ScrollPhysics: Sendable {
    public var speed: Double
    public var fastMultiplier: Double
    public var rampMs: Double
    /// Fraction of full speed right at the key press.
    public var startFraction: Double

    private var carryX = 0.0
    private var carryY = 0.0

    public init(speed: Double = 1.6, fastMultiplier: Double = 3, rampMs: Double = 140, startFraction: Double = 0.35) {
        self.speed = speed
        self.fastMultiplier = fastMultiplier
        self.rampMs = rampMs
        self.startFraction = startFraction
    }

    /// Pixels per ms after the key has been held `heldMs`.
    public func rate(heldMs: Double, fast: Bool) -> Double {
        let t = rampMs > 0 ? min(1, max(0, heldMs) / rampMs) : 1
        let eased = startFraction + (1 - startFraction) * (t * (2 - t)) // ease-out
        return speed * eased * (fast ? fastMultiplier : 1)
    }

    /// Whole-pixel deltas for one frame of `dtMs` in direction (dx, dy) each -1, 0 or 1.
    public mutating func step(dtMs: Double, heldMs: Double, dx: Int, dy: Int, fast: Bool) -> (x: Int, y: Int) {
        let r = rate(heldMs: heldMs, fast: fast) * max(0, dtMs)
        carryX += r * Double(dx)
        carryY += r * Double(dy)
        let x = carryX.rounded(.towardZero), y = carryY.rounded(.towardZero)
        carryX -= x
        carryY -= y
        return (Int(x), Int(y))
    }

    public mutating func reset() {
        carryX = 0
        carryY = 0
    }
}
