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
    /// Liquid Glass islands: `appearance.glass` on macOS 26 and later.
    let glass: Bool
    /// The theme's colours; on glass the highlighted cell is a veil of the text colour instead of
    /// a solid fill, so the glass shows through it.
    let colors: PawConfig.Colors
    /// Height of title islands (sketchybar's: 28).
    var islandHeight: CGFloat { max(12, a.islandHeight) }

    /// `glass`: nil follows `appearance.glass`; false for drawings glass can't be part of (a PNG).
    init(_ a: PawConfig.Appearance, glass: Bool? = nil) {
        self.a = a
        self.glass = (glass ?? a.glass) && Glass.supported
        var c = a.colors
        if self.glass { c.islandHi = c.fg.withAlpha(0.14) }
        colors = c
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

    /// The app's sketchybar-app-font glyph; without the font, the app's own icon, or its initial
    /// when the app can't be found either.
    func appGlyph(_ ligature: String, app: String, color: ARGB) -> NSAttributedString {
        if let appFont {
            return NSAttributedString(string: ligature, attributes: [.font: appFont, .foregroundColor: color.ns, .ligature: 1])
        }
        let side = (a.appIconSize * 1.3).rounded()
        if let image = AppColors.shared.image(for: app, side: Int(saturating: (side * 2).rounded())) {
            let attachment = NSTextAttachment()
            attachment.image = NSImage(cgImage: image, size: NSSize(width: side, height: side))
            // Centre the icon on the text's cap height, like a glyph.
            attachment.bounds = CGRect(x: 0, y: ((font.capHeight - side) / 2).rounded(), width: side, height: side)
            return NSAttributedString(attachment: attachment)
        }
        return text(String(app.prefix(1)).uppercased(), color, font: bold)
    }

    /// A stack cell's fill: the window on top, or a hovered one.
    func cellFill(active: Bool) -> ARGB {
        active ? colors.islandHi : colors.islandHi.withAlpha(glass ? colors.islandHi.alpha * 0.5 : 0.5)
    }

    /// Island chrome: fill, 1 px border, radius, soft shadow. On glass: only the shape; the
    /// panel's `GlassHost` draws the glass, tinted with the fill.
    func decorate(_ l: CALayer, radius: Double, fill: ARGB? = nil, border: ARGB? = nil) {
        if glass {
            Glass.mark(l, fill: fill ?? colors.island, tint: a.glassTint, clear: a.glassStyle == "clear")
            l.backgroundColor = nil
            l.borderWidth = 0
            l.shadowOpacity = 0
            l.cornerRadius = radius
            l.cornerCurve = .continuous
            return
        }
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
