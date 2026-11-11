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
        let expected = [1: CGRect(x: 10, y: 20, width: 400, height: 300)]
        assert(framesMatch(expected, expected))
        assert(!framesMatch([:], expected))
        assert(!framesMatch([2: expected[1]!], expected))
        assert(!framesMatch([1: CGRect(x: 100, y: 20, width: 400, height: 300)], expected))
        fails { _ = try frame(["x": 0, "y": 0, "w": -1, "h": 10]) }
        print("bench helper checks passed")
    }
}
