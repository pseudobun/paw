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
    private var styleKey = ""

    func apply(_ markers: [Marker], icons: AppIconMap, config: PawConfig) {
        let key = "\(config.appearance)\(config.icons)"
        let restyle = key != styleKey
        styleKey = key
        var keep = Set<String>()
        for m in markers {
            let k = "\(m.display)-\(m.left ? "l" : "r")"
            keep.insert(k)
            let panel = panels[k] ?? EdgePanel()
            panels[k] = panel
            panel.onClick = { [weak self] in self?.onClick?(m.name) }
            panel.idleAlpha = style.a.edgeOpacity
            if !restyle, shown[k] == m, panel.isVisible { continue }
            shown[k] = m
            draw(m, in: panel, icons: icons, config: config)
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

    private func draw(_ m: Marker, in panel: EdgePanel, icons: AppIconMap, config: PawConfig) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let root = Self.layer(left: m.left, label: m.label, apps: m.apps, icons: icons, config: config, style: style, scale: scale)
        let w = root.bounds.width, h = root.bounds.height
        let x = m.left ? m.screen.minX + Self.inset : m.screen.maxX - Self.inset - w
        let ax = CGRect(x: x, y: (m.area.midY - h / 2).rounded(), width: w, height: h)
        panel.show(root, at: ScreenGeometry.cocoa(fromAX: ax, primaryHeight: NSScreen.screens.first?.frame.height ?? 0))
    }
}

private final class EdgePanel: NSPanel {
    var onClick: (() -> Void)?
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
        let v = EdgeView()
        v.layer = CALayer()
        v.wantsLayer = true
        v.onClick = { [weak self] in self?.onClick?() }
        v.onHover = { [weak self] inside in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                self?.animator().alphaValue = inside ? 1 : self?.idleAlpha ?? 0.8
            }
        }
        contentView = v
        alphaValue = idleAlpha
    }

    override var canBecomeKey: Bool { false }

    func show(_ l: CALayer, at cocoaFrame: CGRect) {
        setFrame(cocoaFrame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.frame = CGRect(origin: .zero, size: cocoaFrame.size)
        contentView?.layer?.sublayers = [l]
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
