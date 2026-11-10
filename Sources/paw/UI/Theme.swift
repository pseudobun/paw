import AppKit
import CoreText

/// The Settings window's look: hop's OG theme (olive-black, Outfit and Geist Mono), so paw's
/// settings read like hop's. The fonts ship in Resources/Fonts; without them (a plain `swift
/// build`) the system fonts stand in.
enum Theme {
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    // Surfaces
    static let background = rgb(0.047, 0.047, 0.035) // #0c0c09
    static let card = rgb(0.1135, 0.1135, 0.0861)
    static let foreground = rgb(0.985, 0.985, 0.976)
    static let mutedForeground = rgb(0.6706, 0.6706, 0.612)
    static let border = NSColor.white.withAlphaComponent(0.10)

    // Status tones
    static let good = rgb(0.2614, 0.8371, 0.5616)
    static let warn = rgb(0.989, 0.7105, 0.1729)
    static let info = rgb(0.3348, 0.7215, 0.9707)
    static let destructive = rgb(1.0, 0.3912, 0.4039)

    // Categorical
    static let chart1 = rgb(0.0, 0.8012, 0.5289)
    static let chart2 = rgb(1.0, 0.6865, 0.1142)
    static let chart3 = rgb(0.0, 0.688, 1.0)
    static let chart4 = rgb(1.0, 0.3469, 0.4331)
    static let chart5 = rgb(0.6729, 0.4741, 1.0)
    static var neutral: NSColor { mutedForeground }

    /// A faint wash of the foreground: selection and field fills.
    static func wash(_ alpha: CGFloat) -> NSColor { foreground.withAlphaComponent(alpha) }

    static let appearance = NSAppearance(named: .darkAqua)

    // MARK: Fonts

    private static var registered = false
    private static var fonts: [String: NSFont] = [:]

    /// Registers the bundled fonts for this process, once.
    static func registerFonts() {
        guard !registered else { return }
        registered = true
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Anything read as language. 400 regular, 500 medium, 600 semibold.
    static func sans(_ size: CGFloat, _ weight: CGFloat = 400) -> NSFont { font("Outfit-Thin", size, weight, mono: false) }

    /// Values, labels, keys.
    static func mono(_ size: CGFloat, _ weight: CGFloat = 400) -> NSFont { font("GeistMono-Regular", size, weight, mono: true) }

    static var label: NSFont { mono(11, 500) }
    static var meta: NSFont { mono(12) }

    /// Micro-label: 11 pt mono uppercase, tracked 0.18 em.
    static func labelString(_ text: String, color: NSColor = mutedForeground) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [.font: label, .foregroundColor: color, .kern: 11 * 0.18])
    }

    /// A variable font's instance at `weight`, or the system font when it isn't registered.
    private static func font(_ postScript: String, _ size: CGFloat, _ weight: CGFloat, mono: Bool) -> NSFont {
        let key = "\(postScript)/\(size)/\(weight)"
        if let f = fonts[key] { return f }
        let wght = 0x7767_6874 // 'wght'
        let d = NSFontDescriptor(name: postScript, size: size).addingAttributes([
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wght: weight],
        ])
        let sys: NSFont.Weight = weight < 450 ? .regular : weight < 550 ? .medium : .semibold
        let font = NSFont(descriptor: d, size: size).flatMap { $0.fontName.lowercased().hasPrefix(postScript.prefix(4).lowercased()) ? $0 : nil }
            ?? (mono ? .monospacedSystemFont(ofSize: size, weight: sys) : .systemFont(ofSize: size, weight: sys))
        fonts[key] = font
        return font
    }

    /// A rounded tile with an SF Symbol in `color`, as in hop's sidebar and page headers.
    static func tile(_ symbol: String, _ color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            color.withAlphaComponent(0.16).setFill()
            path.fill()
            color.withAlphaComponent(0.22).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold).applying(.init(paletteColors: [color]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let s = glyph.size
                glyph.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
    }
}
