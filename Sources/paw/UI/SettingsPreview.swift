import AppKit
import PawCore
import QuartzCore

/// Every indicator paw shows, drawn around the Settings window while a page about their look is
/// open: a stack with a hovered title, the workspace HUD, the move strip, an edge marker, a
/// placeholder and the focus border. `render` redraws them from any config (the one being edited,
/// a theme under the pointer), so a change shows before it is saved.
@MainActor
final class IndicatorStage {
    private let stack = TitlePanel()
    private let title = TitlePanel()
    private let hud = TitlePanel()
    private let move = TitlePanel()
    private let edge = TitlePanel()
    private let border = TitlePanel()
    private let placeholder = TitlePanel()
    private let placeholderView = PlaceholderView()
    private var panels: [TitlePanel] { [stack, title, hud, move, edge, border, placeholder] }
    private(set) var isShown = false
    private var last: (config: PawConfig, frame: CGRect, borderAlways: Bool)?

    init() {
        placeholder.contentView = placeholderView
        border.level = .normal
    }

    private static let apps = ["Safari", "Mail", "Notes", "Music"]
    private static let titles = ["Apple", "Inbox", "Ideas", "Listen Now"]

    /// `window`: the Settings window's frame (Cocoa coordinates). `borderAlways`: draw the focus
    /// border even when it is off (on its own page, to show what it would look like).
    func render(_ config: PawConfig, around window: CGRect, icons: AppIconMap, borderAlways: Bool = false) {
        last = (config, window, borderAlways)
        isShown = true
        let screen = (NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main)?.visibleFrame ?? window
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let style = Style(config.appearance)
        let gap: CGFloat = 18

        func clamp(_ r: CGRect) -> CGRect {
            var r = r
            r.origin.x = min(max(r.minX, screen.minX + 4), screen.maxX - r.width - 4)
            r.origin.y = min(max(r.minY, screen.minY + 4), screen.maxY - r.height - 4)
            return r.integral
        }

        // A stack on the left: the first window on top and focused, the third hovered.
        let items = zip(Self.apps, Self.titles).enumerated().map { i, p in
            Stack.Item(id: i + 1, app: p.0, title: p.1, isActive: i == 0, hasFocus: i == 0)
        }
        let s = Stack(space: 1, frame: .zero, items: items)
        let m = config.indicator.metrics
        let size = CGSize(width: m.width, height: m.height(cells: items.count))
        let roomLeft = window.minX - screen.minX > size.width + 220
        let sx = roomLeft ? window.minX - gap - size.width : window.maxX + gap
        let sFrame = clamp(CGRect(x: sx, y: window.maxY - 120 - size.height, width: size.width, height: size.height))
        let hovered = 2
        stack.show(StackRenderer.layer(s, size: size, style: style, config: config, icons: icons, scale: scale, hovered: hovered),
                   at: sFrame)
        stack.alphaValue = config.indicator.enabled ? 1 : 0.35
        if config.indicator.titles == "hover" {
            let t = StackRenderer.titleLayer(items[hovered], style: style, icons: icons, scale: scale)
            let cell = IndicatorLayout.cell(hovered, metrics: m)
            let ty = sFrame.maxY - cell.midY - t.bounds.height / 2
            let tx = roomLeft ? sFrame.minX - 6 - t.bounds.width : sFrame.maxX + 6
            title.show(t, at: clamp(CGRect(x: tx, y: ty, width: t.bounds.width, height: t.bounds.height)))
            title.alphaValue = stack.alphaValue
        } else {
            title.orderOut(nil)
        }

        // The workspace HUD above the window, the move strip under it.
        let h = WorkspaceHUD.layer(label: "3", apps: Self.apps, icons: icons, config: config, style: style, scale: scale)
        hud.show(h, at: clamp(CGRect(x: window.midX - h.bounds.width / 2, y: window.maxY + 12,
                                     width: h.bounds.width, height: h.bounds.height)))
        hud.alphaValue = config.hud.workspace ? config.appearance.hudOpacity : 0.35
        let mv = MoveHUD.layer(prev: .init(label: "2", apps: ["Mail"]), current: .init(label: "3", apps: Self.apps),
                               next: nil, icons: icons, config: config, style: style, scale: scale)
        move.show(mv, at: clamp(CGRect(x: window.midX - mv.bounds.width / 2, y: window.minY - 12 - mv.bounds.height,
                                       width: mv.bounds.width, height: mv.bounds.height)))
        move.alphaValue = 0.95

        // An edge marker and a placeholder on the other side.
        let e = EdgeMarkers.layer(left: false, label: "4", apps: ["Notes", "Music"], icons: icons, config: config,
                                  style: style, scale: scale)
        let ex = roomLeft ? window.maxX + gap : window.minX - gap - e.bounds.width
        let eFrame = clamp(CGRect(x: ex, y: window.maxY - 120 - e.bounds.height, width: e.bounds.width, height: e.bounds.height))
        edge.show(e, at: eFrame)
        edge.alphaValue = config.hud.edges ? config.appearance.edgeOpacity : 0.35
        let pw: CGFloat = 170, ph: CGFloat = 130
        let px = roomLeft ? window.maxX + gap : window.minX - gap - pw
        placeholderView.item = Placeholders.Item(id: 99, app: "Music", title: "Listen Now",
                                                 frame: .zero, focused: false)
        placeholderView.style = style
        placeholder.setFrame(clamp(CGRect(x: px, y: window.minY + 40, width: pw, height: ph)), display: true)
        placeholderView.needsDisplay = true
        placeholder.orderFrontRegardless()
        placeholder.alphaValue = config.layout.placeholders ? 1 : 0.35

        // The focus border, around the Settings window itself.
        let b = config.border
        if b.enabled || borderAlways {
            let o = b.offset + b.width / 2
            let outer = window.insetBy(dx: -o - b.width, dy: -o - b.width)
            let shape = CAShapeLayer()
            shape.contentsScale = scale
            let r = CGRect(origin: .zero, size: outer.size).insetBy(dx: b.width, dy: b.width)
            shape.path = CGPath(roundedRect: r, cornerWidth: b.radius + o, cornerHeight: b.radius + o, transform: nil)
            shape.fillColor = nil
            shape.lineWidth = b.width
            shape.strokeColor = b.color.cg
            border.show(shape, at: outer)
            border.alphaValue = b.enabled ? 1 : 0.4
            border.order(.below, relativeTo: NSApp.windows.first { $0 is SettingsWindow }?.windowNumber ?? 0)
        } else {
            border.orderOut(nil)
        }
    }

    /// The window moved: the same indicators around its new frame.
    func follow(_ window: CGRect, icons: AppIconMap) {
        guard isShown, let last, last.frame != window else { return }
        render(last.config, around: window, icons: icons, borderAlways: last.borderAlways)
    }

    func hide() {
        isShown = false
        panels.forEach { $0.orderOut(nil) }
    }
}
