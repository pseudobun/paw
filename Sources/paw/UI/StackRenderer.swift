import AppKit
import PawCore
import QuartzCore

/// Draws one stack indicator: a vertical sketchybar island with one cell per window, like
/// sketchybar's spaces. The window on top gets the island_hi cell; the focused window's icon
/// is gold, the top one fg, the others muted (dim when the stack isn't focused).
enum StackRenderer {
    static func layer(_ stack: Stack, size: CGSize, style: Style, config: PawConfig, icons: AppIconMap, scale: CGFloat,
                      hovered: Int? = nil) -> CALayer {
        let m = config.indicator.metrics
        let c = style.colors
        let root = CALayer()
        root.contentsScale = scale
        root.bounds = CGRect(origin: .zero, size: size)
        style.decorate(root, radius: min(style.a.radius, size.width / 2))
        let focused = stack.hasFocus
        for (i, item) in stack.items.enumerated() {
            let cellTL = IndicatorLayout.cell(i, metrics: m)
            // Layer space is bottom-left; cells are laid out from the top.
            let frame = CGRect(x: cellTL.minX, y: size.height - cellTL.maxY, width: cellTL.width, height: cellTL.height)
            if item.isActive || hovered == i {
                let bg = CALayer()
                bg.frame = frame
                bg.cornerRadius = min(style.a.cellRadius, frame.height / 2)
                bg.cornerCurve = .continuous
                bg.backgroundColor = (item.isActive ? c.islandHi : c.islandHi.withAlpha(0.5)).cg
                root.addSublayer(bg)
            }
            let color: ARGB = item.hasFocus ? c.accent : item.isActive ? c.fg : (focused ? c.muted : c.dim)
            let t = TextLayer()
            t.contentsScale = scale
            t.centered = true
            t.text = style.appGlyph(icons.glyph(for: item.app), app: item.app, color: color)
            t.frame = frame
            root.addSublayer(t)
        }
        return root
    }

    /// The hover island: icon, app and window title.
    static func titleLayer(_ item: Stack.Item, style: Style, icons: AppIconMap, scale: CGFloat) -> CALayer {
        let c = style.colors
        var segs: [Island.Segment] = [.init(text: style.appGlyph(icons.glyph(for: item.app), app: item.app,
                                                                 color: item.hasFocus ? c.accent : c.fg), gapAfter: 6)]
        segs.append(.init(text: style.text(item.app, c.fg, font: style.bold), gapAfter: 8))
        let title = item.title.count > 70 ? String(item.title.prefix(69)) + "…" : item.title
        if !title.isEmpty, title != item.app { segs.append(.init(text: style.text(title, c.muted))) }
        return Island.make(segs, style: style, scale: scale)
    }
}
