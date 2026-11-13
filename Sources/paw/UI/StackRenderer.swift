import AppKit
import PawCore
import QuartzCore

/// Draws one stack indicator: a vertical sketchybar island with one cell per window, like
/// sketchybar's spaces. The window on top gets the island_hi cell; the focused window's icon
/// is gold, the top one fg, the others muted (dim when the stack isn't focused).
enum StackRenderer {
    /// `glide`: leave out the top window's cell; the caller draws it as a layer that glides
    /// between cells (`highlight`).
    static func layer(_ stack: Stack, size: CGSize, style: Style, config: PawConfig, icons: AppIconMap, scale: CGFloat,
                      hovered: Int? = nil, glide: Bool = false) -> CALayer {
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
            if glide ? (hovered == i && !item.isActive) : (item.isActive || hovered == i) {
                let bg = CALayer()
                bg.frame = frame
                bg.cornerRadius = min(style.a.cellRadius, frame.height / 2)
                bg.cornerCurve = .continuous
                bg.backgroundColor = style.cellFill(active: item.isActive).cg
                root.addSublayer(bg)
            }
            let color: ARGB
            if let brand = AppColors.shared.color(for: item.app, icons: config.icons) {
                // The app's colour, full on the window on top, faded on the ones behind it.
                color = brand.withAlpha(item.isActive ? 1 : (focused ? 0.55 : 0.35))
            } else {
                // No colour of its own (a white or grey icon): white, like the icon, not gold.
                color = item.hasFocus || item.isActive ? c.fg : (focused ? c.muted : c.dim)
            }
            if icons.mapped(item.app) == nil || style.appFont == nil,
               let image = AppColors.shared.image(for: item.app, side: Int(saturating: (style.a.appIconSize * 1.3 * scale).rounded())) {
                // No glyph (or no font): the app's own icon, faded like the glyphs behind it.
                let side = (style.a.appIconSize * 1.3).rounded()
                let img = CALayer()
                img.contents = image
                img.contentsGravity = .resizeAspect
                img.frame = CGRect(x: (frame.midX - side / 2).rounded(), y: (frame.midY - side / 2).rounded(),
                                   width: side, height: side)
                img.opacity = item.isActive || item.hasFocus ? 1 : (focused ? 0.55 : 0.35)
                root.addSublayer(img)
                continue
            }
            let t = TextLayer()
            t.contentsScale = scale
            t.centered = true
            t.text = style.appGlyph(icons.glyph(for: item.app), app: item.app, color: color)
            t.frame = frame
            root.addSublayer(t)
        }
        return root
    }

    /// The top window's cell as its own layer: island_hi, the cells' corner radius.
    static func highlight(style: Style, metrics: IndicatorLayout.Metrics) -> CALayer {
        let l = CALayer()
        l.backgroundColor = style.colors.islandHi.cg
        l.cornerRadius = min(style.a.cellRadius, IndicatorLayout.cell(0, metrics: metrics).height / 2)
        l.cornerCurve = .continuous
        return l
    }

    /// The hover island: icon, app and window title.
    static func titleLayer(_ item: Stack.Item, style: Style, icons: AppIconMap, scale: CGFloat) -> CALayer {
        let c = style.colors
        let color = AppColors.shared.color(for: item.app, icons: PawConfig.Icons()) ?? c.fg
        var segs: [Island.Segment] = [.init(text: style.appGlyph(icons.glyph(for: item.app), app: item.app, color: color), gapAfter: 6)]
        segs.append(.init(text: style.text(item.app, c.fg, font: style.bold), gapAfter: 8))
        let title = item.title.count > 70 ? String(item.title.prefix(69)) + "…" : item.title
        if !title.isEmpty, title != item.app { segs.append(.init(text: style.text(title, c.muted))) }
        return Island.make(segs, style: style, scale: scale)
    }
}
