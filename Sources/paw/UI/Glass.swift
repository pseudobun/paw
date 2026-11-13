import AppKit
import PawCore
import QuartzCore

/// Liquid Glass for paw's islands (macOS 26 and later, `appearance.glass`).
///
/// The islands stay plain Core Animation layers. With glass, `Style.decorate` leaves the island's
/// own fill, border and shadow out and marks the layer instead; the panel's `GlassHost` puts an
/// `NSGlassEffectView` behind it in that shape. The window server draws the glass, so it costs
/// paw no drawing and no timers; nothing changes while an island stays as it is.
enum Glass {
    static var supported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Layer key (key-value coding on `CALayer`) holding the island's tint, a `CGColor`.
    static let tintKey = "pawGlassTint"
    /// Layer key: true when the island's own colours are light (a light theme), so the glass is too.
    static let lightKey = "pawGlassLight"
    /// Layer key: true for clear glass (`appearance.glassStyle: "clear"`), false for regular.
    static let clearKey = "pawGlassClear"

    /// Marks `l` as a glass island tinted `fill`, `tint` (0…1, `appearance.glassTint`) strong.
    static func mark(_ l: CALayer, fill: ARGB, tint: Double, clear: Bool) {
        // A hint of the theme's island colour: enough to keep its character, not enough to hide
        // the glass (the default 0.2 lets the wallpaper through as Spotlight does).
        l.setValue(fill.withAlpha(min(fill.alpha, 1) * min(max(tint, 0), 1)).cg, forKey: tintKey)
        l.setValue(fill.luminance > 0.5, forKey: lightKey)
        l.setValue(clear, forKey: clearKey)
    }

    /// The tint `mark` stored, or nil for a layer that isn't a glass island.
    static func tint(of l: CALayer?) -> CGColor? {
        guard let v = l?.value(forKey: tintKey), CFGetTypeID(v as CFTypeRef) == CGColor.typeID else { return nil }
        return (v as! CGColor)
    }

    /// The island's content rises 3 pt into place and fades in, on the render server
    /// (no frames drawn by paw). Skipped with Reduce Motion.
    static func settle(_ l: CALayer, duration: CFTimeInterval = 0.24) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -3
        rise.toValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let g = CAAnimationGroup()
        g.animations = [rise, fade]
        g.duration = duration
        // easeOutQuint, like the stack highlight.
        g.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        l.add(g, forKey: "settle")
    }
}

extension ARGB {
    /// Relative luminance (sRGB, Rec. 709 weights), 0…1.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

/// The content view of a panel that shows one island. `content` holds the island's layers (and
/// takes the panel's mouse events); with a glass island it sits inside an `NSGlassEffectView`
/// shaped like the island, and back on its own without one.
final class GlassHost: NSView {
    let content: NSView
    /// The pointer lights up the glass (macOS 27): for islands that take clicks.
    var interactive = false
    private var glass: NSView?
    private var shownTint: CGColor?
    private var shownLight: Bool?
    private var shownClear: Bool?

    init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A layer-hosting view for islands drawn as layers.
    static func layerView() -> NSView {
        let v = NSView()
        v.layer = CALayer()
        v.wantsLayer = true
        return v
    }

    /// Puts glass behind `root` when it is a glass island (`Glass.mark`), takes it away otherwise.
    /// Cheap to call on every show: nothing changes when the island's shape and tint are the same.
    func adopt(_ root: CALayer?) {
        guard #available(macOS 26, *), let tint = Glass.tint(of: root), let root else {
            removeGlass()
            return
        }
        let g: NSGlassEffectView
        if let existing = glass as? NSGlassEffectView {
            g = existing
        } else {
            g = NSGlassEffectView(frame: bounds)
            g.autoresizingMask = [.width, .height]
            content.removeFromSuperview()
            content.frame = g.bounds
            g.contentView = content
            addSubview(g)
            glass = g
            if interactive, g.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                g.setValue(true, forKey: "effectIsInteractive")
            }
        }
        let radius = root.cornerRadius
        if g.cornerRadius != radius { g.cornerRadius = radius }
        // Set only on a change: each set makes the window server draw the glass again.
        if tint != shownTint {
            shownTint = tint
            g.tintColor = NSColor(cgColor: tint)
        }
        let clear = root.value(forKey: Glass.clearKey) as? Bool ?? false
        if clear != shownClear {
            shownClear = clear
            g.style = clear ? .clear : .regular
        }
        // The theme decides light or dark, not the system: its text colours are made for one.
        let light = root.value(forKey: Glass.lightKey) as? Bool ?? false
        if light != shownLight {
            shownLight = light
            g.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        }
    }

    private func removeGlass() {
        guard let g = glass else { return }
        glass = nil
        shownTint = nil
        shownLight = nil
        shownClear = nil
        if #available(macOS 26, *), let g = g as? NSGlassEffectView { g.contentView = nil }
        g.removeFromSuperview()
        content.frame = bounds
        addSubview(content)
    }
}
