import Foundation

/// A colour in the sketchybar notation: `0xAARRGGBB`. The config also takes `#RRGGBB`,
/// `#RRGGBBAA` and plain numbers (JSON5 hex literals such as `0xeb1d1d16`).
public struct ARGB: Hashable, Sendable, Codable, CustomStringConvertible {
    public var value: UInt32

    public init(_ value: UInt32) { self.value = value }

    public var alpha: Double { Double((value >> 24) & 0xff) / 255 }
    public var red: Double { Double((value >> 16) & 0xff) / 255 }
    public var green: Double { Double((value >> 8) & 0xff) / 255 }
    public var blue: Double { Double(value & 0xff) / 255 }

    /// Same colour with alpha replaced (0…1), like sketchybar's `colors.alpha`.
    public func withAlpha(_ a: Double) -> ARGB {
        let byte = UInt32((max(0, min(1, a)) * 255).rounded())
        return ARGB((value & 0x00ff_ffff) | (byte << 24))
    }

    public var description: String { String(format: "0x%08x", value) }

    public static func parse(_ text: String) -> ARGB? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("0x") {
            s.removeFirst(2)
            guard s.count == 8 || s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            return ARGB(s.count == 6 ? v | 0xff00_0000 : v)
        }
        if s.hasPrefix("#") {
            s.removeFirst()
            guard let v = UInt32(s, radix: 16) else { return nil }
            switch s.count {
            case 6: return ARGB(v | 0xff00_0000)
            case 8: return ARGB((v >> 8) | ((v & 0xff) << 24)) // RRGGBBAA → AARRGGBB
            default: return nil
            }
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(UInt32.self) { value = n; return }
        if let n = try? c.decode(Double.self), n >= 0, n <= Double(UInt32.max) { value = UInt32(n); return }
        let s = try c.decode(String.self)
        guard let parsed = ARGB.parse(s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "“\(s)” is not a colour (0xAARRGGBB or #RRGGBB)")
        }
        value = parsed.value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
