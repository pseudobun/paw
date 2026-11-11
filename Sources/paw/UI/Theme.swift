import AppKit
import CoreText

/// The Settings window's look: System Settings'. SF Pro, the system's label and fill colours, light
/// or dark with the system. (The indicators' look is a separate thing: `appearance` and `Themes`.)
enum Theme {
    /// A colour for light and one for dark mode.
    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    // Surfaces
    static let background = NSColor.windowBackgroundColor
    /// A grouped form section, as in System Settings.
    static let card = dynamic(light: NSColor(white: 1, alpha: 0.55), dark: NSColor(white: 1, alpha: 0.045))
    static let foreground = NSColor.labelColor
    static let mutedForeground = NSColor.secondaryLabelColor
    static let border = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.07))

    // Status tones
    static let good = NSColor.systemGreen
    static let warn = NSColor.systemOrange
    static let info = NSColor.systemBlue
    static let destructive = NSColor.systemRed

    // Sidebar icon colours
    static let chart1 = NSColor.systemGreen
    static let chart2 = NSColor.systemOrange
    static let chart3 = NSColor.systemBlue
    static let chart4 = NSColor.systemPink
    static let chart5 = NSColor.systemPurple
    static let neutral = NSColor.systemGray

    /// A faint wash of the foreground: selection and field fills.
    static func wash(_ alpha: CGFloat) -> NSColor { foreground.withAlphaComponent(alpha) }

    /// nil: light or dark with the system.
    static let appearance: NSAppearance? = nil

    // MARK: Fonts

    private static var registered = false

    /// Registers the fonts in paw.app's Resources/Fonts (the themes' fonts) for this process, once.
    static func registerFonts() {
        guard !registered else { return }
        registered = true
        for ext in ["ttf", "otf"] {
            for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    private static func weight(_ w: CGFloat) -> NSFont.Weight {
        w < 450 ? .regular : w < 550 ? .medium : w < 650 ? .semibold : .bold
    }

    /// Anything read as language. 400 regular, 500 medium, 600 semibold.
    static func sans(_ size: CGFloat, _ w: CGFloat = 400) -> NSFont { .systemFont(ofSize: size, weight: weight(w)) }

    /// Values and keys.
    static func mono(_ size: CGFloat, _ w: CGFloat = 400) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight(w)) }

    static var meta: NSFont { sans(11) }

    /// A section's title over its group, as in System Settings: 13 pt semibold.
    static func labelString(_ text: String, color: NSColor = foreground) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: sans(13, 600), .foregroundColor: color])
    }

    /// A sidebar group's name: small and secondary.
    static func groupString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: sans(11, 600), .foregroundColor: NSColor.tertiaryLabelColor])
    }

    /// System Settings' icon: a white SF Symbol on a rounded square of `color`, lit from the top.
    static func tile(_ symbol: String, _ color: NSColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let r = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: r, xRadius: size * 0.225, yRadius: size * 0.225)
            let base = color.usingColorSpace(.sRGB) ?? color
            NSGradient(starting: base.blended(withFraction: 0.18, of: .white) ?? base,
                       ending: base.blended(withFraction: 0.08, of: .black) ?? base)?.draw(in: path, angle: -90)
            NSColor(white: 0, alpha: 0.12).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .medium).applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let s = glyph.size
                glyph.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
    }
}
