import CoreGraphics
import Foundation

struct BenchError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw BenchError(message) }
}

func reply(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BenchError("invalid IPC reply")
    }
    if let error = object["error"] {
        try require(error is String && (error as! String).isEmpty, "PAW: \(error)")
    }
    return object
}

func summary(_ values: [Double]) throws -> [String: Double] {
    try require(!values.isEmpty && values.allSatisfy { $0.isFinite && $0 >= 0 }, "invalid timing samples")
    let sorted = values.sorted()
    func percentile(_ p: Double) -> Double { sorted[max(0, Int(ceil(Double(sorted.count) * p)) - 1)] }
    let middle = sorted.count / 2
    return ["count": Double(sorted.count), "median_ms": sorted.count.isMultiple(of: 2)
        ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle],
        "p90_ms": percentile(0.9), "p99_ms": percentile(0.99), "max_ms": sorted.last!]
}

func frame(_ object: [String: Any]) throws -> CGRect {
    guard let x = object["x"] as? Double, let y = object["y"] as? Double,
          let w = object["w"] as? Double, let h = object["h"] as? Double,
          [x, y, w, h].allSatisfy(\.isFinite), w > 0, h > 0 else { throw BenchError("invalid window frame") }
    return CGRect(x: x, y: y, width: w, height: h)
}

/// PAW parks a hidden window with one point on screen, but macOS clamps it to about a title bar
/// and may keep its own size there: a target off the display only needs the window off it too.
func parked(_ r: CGRect, on screen: CGRect, tolerance: Double = 4) -> Bool {
    let shown = r.intersection(screen)
    return shown.isNull || min(shown.width, shown.height) <= tolerance
}

func framesMatch(_ actual: [Int: CGRect], _ expected: [Int: CGRect], screen: CGRect, tolerance: Double = 4) -> Bool {
    Set(actual.keys) == Set(expected.keys) && expected.allSatisfy { id, wanted in
        guard let got = actual[id] else { return false }
        if parked(wanted, on: screen, tolerance: tolerance) { return parked(got, on: screen, tolerance: tolerance) }
        return abs(got.minX - wanted.minX) <= tolerance && abs(got.minY - wanted.minY) <= tolerance
            && abs(got.width - wanted.width) <= tolerance && abs(got.height - wanted.height) <= tolerance
    }
}

/// One line per window: PAW's target, WindowServer's actual frame, and whether it matched.
func geometryReport(_ actual: [Int: CGRect], _ expected: [Int: CGRect], screen: CGRect) -> String {
    func text(_ r: CGRect?) -> String { r.map { "(\($0.minX), \($0.minY), \($0.width), \($0.height))" } ?? "missing" }
    return expected.keys.sorted().map { id in
        let ok = actual[id].map { framesMatch([id: $0], [id: expected[id]!], screen: screen) } ?? false
        return "window \(id) target \(text(expected[id])) actual \(text(actual[id]))\(ok ? "" : " MISMATCH")"
    }.joined(separator: "\n") + "\nscreen \(text(screen))"
}
