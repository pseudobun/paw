import AppKit
import PawCore

extension ARGB {
    var cg: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var ns: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// Fonts and colours resolved from `appearance`, rebuilt when the config changes.
struct Style {
    let a: PawConfig.Appearance
    let font: NSFont
    let bold: NSFont
    /// nil when sketchybar-app-font isn't installed: cells then show the app's initial.
    let appFont: NSFont?
    var colors: PawConfig.Colors { a.colors }
    /// Height of title islands (sketchybar's: 28).
    var islandHeight: CGFloat { max(12, a.islandHeight) }

    init(_ a: PawConfig.Appearance) {
        self.a = a
        font = Self.font(a.font, size: a.fontSize, weight: a.fontWeight)
        bold = Self.font(a.font, size: a.fontSize, weight: a.boldWeight)
        appFont = NSFont(name: a.appFont, size: a.appIconSize)
    }

    /// Corner radius for a pill-shaped island `height` tall: round ends, or `radius` without pills.
    func pillRadius(_ height: CGFloat) -> CGFloat { a.pills ? height / 2 : min(a.radius, height / 2) }

    static func font(_ family: String, size: Double, weight: String) -> NSFont {
        let (w, sys): (Int, NSFont.Weight) = switch weight.lowercased() {
        case "regular": (5, .regular)
        case "medium": (6, .medium)
        case "semibold": (8, .semibold)
        default: (9, .bold)
        }
        switch family.lowercased().replacingOccurrences(of: " ", with: "-") {
        case "system", "sf-pro": return .systemFont(ofSize: size, weight: sys)
        case "system-mono", "sf-mono": return .monospacedSystemFont(ofSize: size, weight: sys)
        case "system-rounded", "sf-pro-rounded":
            let base = NSFont.systemFont(ofSize: size, weight: sys)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        default: break
        }
        if let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: w, size: size) { return f }
        if let f = NSFont(name: family, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: sys)
    }

    func text(_ s: String, _ color: ARGB, font: NSFont? = nil) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font ?? self.font, .foregroundColor: color.ns, .ligature: 1])
    }

    /// The app's sketchybar-app-font glyph, or its initial without the font.
    func appGlyph(_ ligature: String, app: String, color: ARGB) -> NSAttributedString {
        if let appFont {
            return NSAttributedString(string: ligature, attributes: [.font: appFont, .foregroundColor: color.ns, .ligature: 1])
        }
        return text(String(app.prefix(1)).uppercased(), color, font: bold)
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
            l.shadowOpacity = Float(a.shadowOpacity)
            l.shadowRadius = a.shadowRadius
            l.shadowOffset = CGSize(width: 0, height: -1)
            l.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: l.bounds.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }
}
