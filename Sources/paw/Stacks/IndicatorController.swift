import AppKit
import PawCore

/// Keeps one indicator panel per stack, placed next to its tile.
final class IndicatorController {
    let settings: Settings
    private(set) var style: Style
    private var panels: [String: IndicatorPanel] = [:]
    private var stacks: [Stack] = []
    /// Panels drawn so far (tests).
    private(set) var renders = 0
    private let title = TitlePanel()
    private var hidden = false
    /// Focus a window (click on its icon, scrolling).
    var onFocus: ((WindowID) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        style = Style(settings.config.appearance)
    }

    var config: PawConfig { settings.config }

    func configChanged() {
        style = Style(config.appearance)
        let old = stacks
        stacks = []
        apply(old, force: true)
    }

    func setHidden(_ h: Bool) {
        hidden = h
        if h {
            for p in panels.values { p.orderOut(nil) }
            title.orderOut(nil)
        } else {
            let old = stacks
            stacks = []
            apply(old, force: true)
        }
    }

    var snapshot: [Stack] { stacks }

    func apply(_ new: [Stack], force: Bool = false) {
        if !force, new == stacks, panels.count == new.count { return }
        // Stacks that didn't change keep their panels as they are: no new layers, no fade.
        let previous = force ? [:] : Dictionary(stacks.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        stacks = new
        guard !hidden, config.indicator.enabled else {
            for p in panels.values { p.orderOut(nil) }
            panels.removeAll()
            title.orderOut(nil)
            return
        }
        let primary = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens
        let axScreens = screens.map { ScreenGeometry.axFrame(ofScreen: $0.frame, primaryHeight: primary) }
        var keep = Set<String>()
        let fade = config.indicator.fadeMs / 1000

        for stack in new {
            guard let si = ScreenGeometry.screenIndex(for: stack.frame, screens: axScreens) else { continue }
            let (axRect, side) = IndicatorLayout.frame(window: stack.frame, screen: axScreens[si], count: stack.items.count,
                                                       side: config.indicator.side, metrics: config.indicator.metrics)
            let key = stack.key
            keep.insert(key)
            if previous[key] == stack, let panel = panels[key], panel.isVisible { _ = panel; continue }
            let panel = panels[key] ?? IndicatorPanel()
            let isNew = panels[key] == nil
            panels[key] = panel
            renders += 1
            panel.setFrame(ScreenGeometry.cocoa(fromAX: axRect, primaryHeight: primary), display: false)
            configure(panel.view, stack: stack, side: side, axRect: axRect, scale: screens[si].backingScaleFactor)
            panel.view.redraw(animated: !isNew)
            if isNew { panel.orderFrontRegardless() }
            let target = stack.hasFocus ? 1 : CGFloat(config.indicator.unfocusedOpacity)
            if isNew || panel.alphaValue != target {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = fade
                    panel.animator().alphaValue = target
                }
            }
        }
        for (key, panel) in panels where !keep.contains(key) {
            panels[key] = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = fade
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        title.orderOut(nil)
    }

    private func configure(_ v: IndicatorView, stack: Stack, side: IndicatorLayout.Side, axRect: CGRect, scale: CGFloat) {
        let size = axRect.size
        let style = style, config = config, icons = settings.icons
        v.stack = stack
        v.metrics = config.indicator.metrics
        v.render = { hovered in
            StackRenderer.layer(stack, size: size, style: style, config: config, icons: icons, scale: scale, hovered: hovered,
                                glide: true)
        }
        v.makeHighlight = { StackRenderer.highlight(style: style, metrics: config.indicator.metrics) }
        v.onClick = { [weak self] i in
            guard let self, config.indicator.clickToFocus else { return }
            onFocus?(WindowID(stack.items[i].id))
        }
        v.onScroll = { [weak self] dir in
            guard let self, config.indicator.scrollToCycle, let current = stack.activeIndex else { return }
            let n = stack.items.count
            var next = current + dir
            if config.focus.wrapStacks { next = (next + n) % n } else if !stack.items.indices.contains(next) { return }
            onFocus?(WindowID(stack.items[next].id))
        }
        v.onHover = { [weak self] i in
            guard let self else { return }
            guard let i, config.indicator.titles == "hover" else { title.orderOut(nil); return }
            let l = StackRenderer.titleLayer(stack.items[i], style: style, icons: icons, scale: scale)
            let cell = IndicatorLayout.cell(i, metrics: config.indicator.metrics)
            let h = l.bounds.height, w = l.bounds.width
            let y = axRect.minY + cell.midY - h / 2
            let toRight = side == .left || side == .insideLeft
            let x = toRight ? axRect.maxX + 6 : axRect.minX - 6 - w
            let primary = NSScreen.screens.first?.frame.height ?? 0
            title.show(l, at: ScreenGeometry.cocoa(fromAX: CGRect(x: x, y: y, width: w, height: h), primaryHeight: primary))
        }
    }
}
