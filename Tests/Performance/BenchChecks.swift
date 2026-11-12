import CoreGraphics
import Foundation

@main enum BenchChecks {
    static func fails(_ body: () throws -> Void) {
        do { try body(); fatalError("expected rejection") } catch {}
    }

    static func main() throws {
        let empty = try reply(Data("{}".utf8))
        assert(empty.isEmpty)
        fails { _ = try reply(Data("{\"error\":\"invalid command\"}".utf8)) }
        fails { _ = try reply(Data("{\"error\":true}".utf8)) }
        fails { _ = try reply(Data("[]".utf8)) }
        fails { _ = try reply(Data()) }
        let timing = try summary([9, 1, 3, 7])
        assert(timing["median_ms"] == 5 && timing["p90_ms"] == 9 && timing["count"] == 4)
        fails { _ = try summary([]) }
        fails { _ = try summary([Double.nan]) }
        fails { _ = try summary([-1]) }
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let expected = [1: CGRect(x: 10, y: 20, width: 400, height: 300)]
        assert(framesMatch(expected, expected, screen: screen))
        assert(!framesMatch([:], expected, screen: screen))
        assert(!framesMatch([2: expected[1]!], expected, screen: screen))
        assert(!framesMatch([1: CGRect(x: 100, y: 20, width: 400, height: 300)], expected, screen: screen))
        // Measured on macOS 26: PAW parks at (1799, 1168); WindowServer clamps it to y 1137 and keeps another size.
        let parkedTarget = [1: CGRect(x: 1799, y: 1168, width: 400, height: 332)]
        assert(framesMatch([1: CGRect(x: 1799, y: 1137, width: 424, height: 440)], parkedTarget, screen: screen))
        assert(framesMatch([1: CGRect(x: -423, y: 1137, width: 424, height: 440)], parkedTarget, screen: screen))
        assert(!framesMatch([1: CGRect(x: 1340, y: 40, width: 424, height: 1127)], parkedTarget, screen: screen))
        assert(!framesMatch([1: CGRect(x: 1799, y: 1137, width: 424, height: 440)], expected, screen: screen))
        assert(geometryReport([1: CGRect(x: 100, y: 20, width: 400, height: 300)], expected, screen: screen).contains("MISMATCH"))
        fails { _ = try frame(["x": 0, "y": 0, "w": -1, "h": 10]) }
        print("bench helper checks passed")
    }
}
