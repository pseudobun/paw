import AppKit
import PawCore

extension ARGB {
    var cg: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var ns: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// Fonts and colours resolved from `appearance`, rebuilt when the config changes.
struct Style {
    let a: PawConfig.Appearance
    let labelFont: NSFont
    let islandFont: NSFont
    let islandBold: NSFont
    /// nil when sketchybar-app-font isn't installed: islands then show no app icon.
    let appFont: NSFont?
    var colors: PawConfig.Colors { a.colors }

    init(_ a: PawConfig.Appearance) {
        self.a = a
        labelFont = Self.font(a.font, size: a.fontSize, weight: a.fontWeight)
        islandFont = Self.font(a.font, size: a.islandFontSize, weight: "medium")
        islandBold = Self.font(a.font, size: a.islandFontSize, weight: "semibold")
        appFont = NSFont(name: a.appFont, size: a.appIconSize)
    }

    static func font(_ family: String, size: Double, weight: String) -> NSFont {
        let (w, sys): (Int, NSFont.Weight) = switch weight.lowercased() {
        case "light": (3, .light)
        case "regular", "normal": (5, .regular)
        case "medium": (6, .medium)
        case "semibold": (8, .semibold)
        case "heavy", "black": (11, .heavy)
        default: (9, .bold)
        }
        if let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: w, size: size) { return f }
        if let f = NSFont(name: family, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: sys)
    }

    func text(_ s: String, _ color: ARGB, font: NSFont? = nil) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font ?? islandFont, .foregroundColor: color.ns, .ligature: 1])
    }

    /// The app's sketchybar-app-font glyph, in the accent colour like sketchybar's front_app.
    func appGlyph(_ ligature: String, color: ARGB? = nil) -> NSAttributedString? {
        guard let appFont else { return nil }
        return NSAttributedString(string: ligature, attributes: [.font: appFont, .foregroundColor: (color ?? colors.accent).ns, .ligature: 1])
    }

    /// A label's code: typed keys in the accent colour, the rest in fg.
    func code(_ code: String, typed: Int) -> NSAttributedString {
        let s = NSMutableAttributedString()
        let chars = Array(code)
        let n = min(typed, chars.count)
        if n > 0 { s.append(NSAttributedString(string: String(chars[..<n]), attributes: [.font: labelFont, .foregroundColor: colors.accent.ns])) }
        if n < chars.count {
            s.append(NSAttributedString(string: String(chars[n...]), attributes: [.font: labelFont, .foregroundColor: colors.fg.ns]))
        }
        return s
    }

    /// Island chrome: fill, 1 px border, radius, soft shadow.
    func decorate(_ l: CALayer, radius: Double, fill: ARGB? = nil, border: ARGB? = nil) {
        l.backgroundColor = (fill ?? colors.island).cg
        l.borderColor = (border ?? colors.border).cg
        l.borderWidth = a.borderWidth
        l.cornerRadius = radius
        l.cornerCurve = .continuous
        if a.shadow {
            l.shadowColor = CGColor(gray: 0, alpha: 1)
            l.shadowOpacity = 0.35
            l.shadowRadius = 4
            l.shadowOffset = CGSize(width: 0, height: -1)
            l.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: l.bounds.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }
}
