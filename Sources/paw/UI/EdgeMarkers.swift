import AppKit
import PawCore
import QuartzCore

/// Upright islands against a display's left and right edges, halfway down, in the look of the
/// move strip: the workspace `workspace prev|next` goes to there, its number and apps. They sit
/// in the margin the stack indicators already keep free. A click goes there.
final class EdgeMarkers {
    struct Marker: Equatable {
        let display: CGDirectDisplayID
        let left: Bool
        let name: String
        let label: String
        let apps: [String]
        /// The display's tiling area and whole frame, AX coordinates.
        let area: CGRect
        let screen: CGRect
    }

    static let width: CGFloat = 26
    static let inset: CGFloat = 3

    var style = Style(PawConfig.Appearance())
    var onClick: ((String) -> Void)?
    private var panels: [String: EdgePanel] = [:]
    private var shown: [String: Marker] = [:]
    private var styleKey: (PawConfig.Appearance, PawConfig.Icons)?

    func apply(_ markers: [Marker], icons: AppIconMap, config: PawConfig) {
        let restyle = styleKey.map { $0.0 != config.appearance || $0.1 != config.icons } ?? true
        styleKey = (config.appearance, config.icons)
        var keep = Set<String>()
        for m in markers {
            let k = "\(m.display)-\(m.left ? "l" : "r")"
            keep.insert(k)
            let panel = panels[k] ?? EdgePanel()
            panels[k] = panel
            panel.onClick = { [weak self] in self?.onClick?(m.name) }
            panel.idleAlpha = style.a.edgeOpacity
            if !restyle, shown[k] == m, panel.isVisible { continue }
            // A neighbour that changed glides to its new size, like the tip bar's islands.
            let glide = !restyle && shown[k] != nil && panel.isVisible
            shown[k] = m
            draw(m, in: panel, icons: icons, config: config, animated: glide)
        }
        for (k, p) in panels where !keep.contains(k) {
            p.orderOut(nil)
            shown[k] = nil
        }
    }

    func hideAll() {
        for p in panels.values { p.orderOut(nil) }
        shown = [:]
    }

    /// The upright island: the way it goes, the neighbour's number, its apps.
    static func layer(left: Bool, label: String, apps: [String], icons: AppIconMap, config: PawConfig, style: Style,
                      scale: CGFloat) -> CALayer {
        let c = style.colors
        let w = width, row: CGFloat = 22, pad: CGFloat = 5
        var rows: [NSAttributedString] = [
            style.text(left ? "‹" : "›", c.muted, font: style.bold),
            style.text(label, apps.isEmpty ? c.dim : c.muted, font: style.bold),
        ]
        for app in apps.prefix(5) {
            let color = AppColors.shared.color(for: app, icons: config.icons) ?? c.fg
            rows.append(style.appGlyph(icons.glyph(for: app), app: app, color: color.withAlpha(0.7)))
        }
        let h = pad * 2 + row * CGFloat(rows.count)
        let root = CALayer()
        root.contentsScale = scale
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        style.decorate(root, radius: style.pillRadius(w))
        for (i, t) in rows.enumerated() {
            let l = TextLayer()
            l.contentsScale = scale
            l.centered = true
            l.text = t
            // Layers count up from the bottom: the first row goes on top.
            l.frame = CGRect(x: 0, y: h - pad - row * CGFloat(i + 1), width: w, height: row)
            root.addSublayer(l)
        }
        return root
    }

    private func draw(_ m: Marker, in panel: EdgePanel, icons: AppIconMap, config: PawConfig, animated: Bool) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let root = Self.layer(left: m.left, label: m.label, apps: m.apps, icons: icons, config: config, style: style, scale: scale)
        let w = root.bounds.width, h = root.bounds.height
        let x = m.left ? m.screen.minX + Self.inset : m.screen.maxX - Self.inset - w
        let ax = CGRect(x: x, y: (m.area.midY - h / 2).rounded(), width: w, height: h)
        panel.show(root, at: ScreenGeometry.cocoa(fromAX: ax, primaryHeight: NSScreen.screens.first?.frame.height ?? 0),
                   animated: animated)
    }
}

private final class EdgePanel: NSPanel {
    var onClick: (() -> Void)?
    private let view = EdgeView()
    private lazy var host = GlassHost(content: view)
    var idleAlpha: CGFloat = 0.8 {
        didSet { if oldValue != idleAlpha { alphaValue = idleAlpha } }
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = false
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        isReleasedWhenClosed = false
        animationBehavior = .none
        let v = view
        v.layer = CALayer()
        v.wantsLayer = true
        host.interactive = true
        v.onClick = { [weak self] in self?.onClick?() }
        v.onHover = { [weak self] inside in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                self?.animator().alphaValue = inside ? 1 : self?.idleAlpha ?? 0.8
            }
        }
        contentView = host
        alphaValue = idleAlpha
    }

    override var canBecomeKey: Bool { false }

    /// The island shown now: its background and its rows, kept apart so the background can
    /// glide while the rows swap.
    private var island: CALayer?
    private var rows: CALayer?
    private var generation = 0

    /// The tip bar's motion: islands glide over 220 ms (easeOutQuint), content swaps in 80 ms.
    private static let glide: CFTimeInterval = 0.22
    private static let contentFade: CFTimeInterval = 0.08

    /// Shows the island `l` at `cocoaFrame`. `animated`, the old island's background glides to
    /// the new size and place while its rows cross-fade into the new ones.
    func show(_ l: CALayer, at cocoaFrame: CGRect, animated: Bool = false) {
        guard let root = host.content.layer else { return }
        generation += 1
        let gen = generation
        // The rows move into their own layer; `l` keeps only the island's chrome.
        let content = CALayer()
        content.contentsScale = l.contentsScale
        for row in l.sublayers ?? [] { content.addSublayer(row) }
        let from = frame
        // A glass island doesn't glide: the glass fills the panel, which grows for the glide.
        let motion = animated && isVisible && from != cocoaFrame && island != nil
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && Glass.tint(of: l) == nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard motion else {
            setFrame(cocoaFrame, display: false)
            l.frame = CGRect(origin: .zero, size: cocoaFrame.size)
            content.frame = l.frame
            root.sublayers = [l, content]
            island = l
            rows = content
            host.adopt(l)
            CATransaction.commit()
            orderFrontRegardless()
            return
        }
        // Grow the panel to cover both places for the glide, then settle on the new one.
        let union = from.union(cocoaFrame)
        let f = from.offsetBy(dx: -union.minX, dy: -union.minY)
        let t = cocoaFrame.offsetBy(dx: -union.minX, dy: -union.minY)
        setFrame(union, display: false)
        let oldRows = rows
        oldRows?.frame = f
        l.frame = t
        content.frame = t
        root.sublayers = [l, oldRows, content].compactMap { $0 }
        host.adopt(l)
        island = l
        rows = content
        let ease = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        func anim(_ key: String, _ from: Any?, _ duration: CFTimeInterval, _ timing: CAMediaTimingFunction) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.duration = duration
            a.timingFunction = timing
            return a
        }
        l.add(anim("bounds", NSValue(rect: CGRect(origin: .zero, size: f.size)), Self.glide, ease), forKey: "glide.bounds")
        l.add(anim("position", NSValue(point: CGPoint(x: f.midX, y: f.midY)), Self.glide, ease), forKey: "glide.position")
        if l.shadowPath != nil {
            let r = l.cornerRadius
            let fromPath = CGPath(roundedRect: CGRect(origin: .zero, size: f.size), cornerWidth: min(r, f.width / 2),
                                  cornerHeight: min(r, f.height / 2), transform: nil)
            l.add(anim("shadowPath", fromPath, Self.glide, ease), forKey: "glide.shadow")
        }
        let linear = CAMediaTimingFunction(name: .linear)
        content.add(anim("opacity", 0, Self.contentFade, linear), forKey: "fade")
        oldRows?.opacity = 0
        oldRows?.add(anim("opacity", 1, Self.contentFade, linear), forKey: "fade")
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, gen == generation else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setFrame(cocoaFrame, display: false)
            l.frame = CGRect(origin: .zero, size: cocoaFrame.size)
            content.frame = l.frame
            root.sublayers = [l, content]
            CATransaction.commit()
        }
        CATransaction.commit()
        orderFrontRegardless()
    }
}

private final class EdgeView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseUp(with event: NSEvent) {
        onHover?(false)
        onClick?()
    }
}
