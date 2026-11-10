import Foundation

/// Ranges for every number in the config. JSON5 allows `Infinity`, `NaN` and `1e308`, and the UI
/// turns many of these into `Int`s or frames, so a value outside its range is reported by
/// `paw config check` and clamped before paw uses it.
extension PawConfig {
    struct Limit {
        let key: String
        let path: WritableKeyPath<PawConfig, Double>
        let range: ClosedRange<Double>
    }

    struct IntLimit {
        let key: String
        let path: WritableKeyPath<PawConfig, Int>
        let range: ClosedRange<Int>
    }

    static var limits: [Limit] { [
        .init(key: "layout.gap", path: \.layout.gap, range: 0...500),
        .init(key: "layout.padding.top", path: \.layout.padding.top, range: 0...2000),
        .init(key: "layout.padding.bottom", path: \.layout.padding.bottom, range: 0...2000),
        .init(key: "layout.padding.left", path: \.layout.padding.left, range: 0...2000),
        .init(key: "layout.padding.right", path: \.layout.padding.right, range: 0...2000),
        .init(key: "layout.barTop", path: \.layout.barTop, range: 0...2000),
        .init(key: "layout.barBottom", path: \.layout.barBottom, range: 0...2000),
        .init(key: "layout.minTileWidth", path: \.layout.minTileWidth, range: 0...20000),
        .init(key: "layout.minTileHeight", path: \.layout.minTileHeight, range: 0...20000),
        .init(key: "layout.placeholderMinWidth", path: \.layout.placeholderMinWidth, range: 0...20000),
        .init(key: "layout.placeholderMinHeight", path: \.layout.placeholderMinHeight, range: 0...20000),
        .init(key: "animation.durationMs", path: \.animation.durationMs, range: 0...10000),
        .init(key: "initiate.timeout", path: \.initiate.timeout, range: 0...3600),
        .init(key: "border.width", path: \.border.width, range: 0...50),
        .init(key: "border.radius", path: \.border.radius, range: 0...500),
        .init(key: "border.offset", path: \.border.offset, range: -100...100),
        .init(key: "hud.durationMs", path: \.hud.durationMs, range: 0...10000),
        .init(key: "indicator.offsetX", path: \.indicator.offsetX, range: -2000...2000),
        .init(key: "indicator.offsetY", path: \.indicator.offsetY, range: -2000...2000),
        .init(key: "indicator.width", path: \.indicator.width, range: 1...500),
        .init(key: "indicator.cellHeight", path: \.indicator.cellHeight, range: 1...500),
        .init(key: "indicator.gap", path: \.indicator.gap, range: 0...200),
        .init(key: "indicator.padding", path: \.indicator.padding, range: 0...200),
        .init(key: "indicator.unfocusedOpacity", path: \.indicator.unfocusedOpacity, range: 0...1),
        .init(key: "indicator.fadeMs", path: \.indicator.fadeMs, range: 0...10000),
        .init(key: "appearance.fontSize", path: \.appearance.fontSize, range: 1...200),
        .init(key: "appearance.appIconSize", path: \.appearance.appIconSize, range: 1...200),
        .init(key: "appearance.radius", path: \.appearance.radius, range: 0...200),
        .init(key: "appearance.cellRadius", path: \.appearance.cellRadius, range: 0...200),
        .init(key: "appearance.borderWidth", path: \.appearance.borderWidth, range: 0...50),
    ] }

    static var intLimits: [IntLimit] { [
        .init(key: "layout.workspaces", path: \.layout.workspaces, range: 1...100),
        .init(key: "animation.maxWindows", path: \.animation.maxWindows, range: 0...1000),
    ] }

    static let tileSizeRange: ClosedRange<Double> = 0.01...100

    /// Numbers outside their range, as config-check warnings.
    public var rangeWarnings: [String] {
        var w: [String] = []
        for l in Self.limits {
            let v = self[keyPath: l.path]
            if !v.isFinite || !l.range.contains(v) {
                w.append("\(l.key): \(v) is outside \(Self.format(l.range.lowerBound))…\(Self.format(l.range.upperBound))")
            }
        }
        for l in Self.intLimits where !l.range.contains(self[keyPath: l.path]) {
            w.append("\(l.key): \(self[keyPath: l.path]) is outside \(l.range.lowerBound)…\(l.range.upperBound)")
        }
        func tiles(_ prefix: String, _ presets: [String: WorkspacePreset]) {
            for (name, p) in presets.sorted(by: { $0.key < $1.key }) {
                for (i, t) in p.tiles.enumerated() {
                    if let s = t.size, !s.isFinite || !Self.tileSizeRange.contains(s) {
                        w.append("\(prefix)\(name).tiles[\(i)].size: \(s) is outside 0.01…100")
                    }
                }
            }
        }
        tiles("workspaces.", workspaces)
        for (name, setup) in setups.sorted(by: { $0.key < $1.key }) { tiles("setups.\(name).workspaces.", setup.workspaces) }
        return w
    }

    /// The config with every number moved into its range (NaN takes the default).
    public func clamped() -> PawConfig {
        var c = self
        let defaults = PawConfig()
        for l in Self.limits {
            let v = c[keyPath: l.path]
            c[keyPath: l.path] = v.isNaN ? defaults[keyPath: l.path] : min(max(v, l.range.lowerBound), l.range.upperBound)
        }
        for l in Self.intLimits {
            c[keyPath: l.path] = min(max(c[keyPath: l.path], l.range.lowerBound), l.range.upperBound)
        }
        func fix(_ presets: inout [String: WorkspacePreset]) {
            for key in presets.keys {
                for i in presets[key]!.tiles.indices {
                    guard let s = presets[key]!.tiles[i].size else { continue }
                    presets[key]!.tiles[i].size = s.isNaN ? nil : min(max(s, Self.tileSizeRange.lowerBound), Self.tileSizeRange.upperBound)
                }
            }
        }
        fix(&c.workspaces)
        for key in c.setups.keys { fix(&c.setups[key]!.workspaces) }
        return c
    }

    private static func format(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
