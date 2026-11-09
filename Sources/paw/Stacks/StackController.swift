import AppKit
import PawCore

/// Queries yabai on every change (debounced), groups windows into stacks and keeps one
/// indicator panel per stack in place.
final class StackController {
    let settings: Settings
    private(set) var style: Style
    private var panels: [String: IndicatorPanel] = [:]
    private var stacks: [Stack] = []
    private let title = TitlePanel()
    private let queue = DispatchQueue(label: "dev.paw.yabai", qos: .userInitiated)
    private var pending = false
    private var again = false
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    private var hidden = false

    init(settings: Settings) {
        self.settings = settings
        style = Style(settings.config.appearance)
    }

    var config: PawConfig { settings.config }
    var yabai: YabaiClient { YabaiClient(path: config.yabai.path) }

    func configChanged() {
        style = Style(config.appearance)
        let old = stacks
        stacks = []
        apply(old, force: true)
        refresh()
    }

    /// Coalesces bursts (a window drag sends dozens of signals) into one query at a time.
    func refresh() {
        if pending { again = true; return }
        pending = true
        let client = yabai
        let fuzz = config.yabai.fuzz
        let excluded = Set(config.excludedApps.map { $0.lowercased() })
        queue.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
            let result = client.query()
            let stacks = result.map { r in
                StackBuilder.stacks(windows: r.windows.filter { !excluded.contains($0.app.lowercased()) }, spaces: r.spaces, fuzz: fuzz)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                pending = false
                lastRefresh = Date()
                if let stacks {
                    lastError = nil
                    apply(stacks, force: false)
                } else {
                    lastError = "yabai did not answer (\(config.yabai.path))"
                }
                if again { again = false; refresh() }
            }
        }
    }

    func hideAll() {
        hidden = true
        for p in panels.values { p.orderOut(nil) }
        title.orderOut(nil)
    }

    func showAll() {
        hidden = false
        refresh()
    }

    var snapshot: [Stack] { stacks }

    // MARK: - Drawing

    private func apply(_ new: [Stack], force: Bool) {
        if !force, new == stacks, panels.count == new.count { return }
        stacks = new
        guard !hidden else { return }
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
            let panel = panels[key] ?? IndicatorPanel()
            let isNew = panels[key] == nil
            panels[key] = panel
            panel.setFrame(ScreenGeometry.cocoa(fromAX: axRect, primaryHeight: primary), display: false)
            configure(panel.view, stack: stack, side: side, axRect: axRect, scale: screens[si].backingScaleFactor)
            panel.view.redraw()
            let target = stack.hasFocus ? 1 : CGFloat(config.indicator.unfocusedOpacity)
            if isNew { panel.orderFrontRegardless() }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fade
                panel.animator().alphaValue = target
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
            StackRenderer.layer(stack, size: size, style: style, config: config, icons: icons, scale: scale, hovered: hovered)
        }
        v.onClick = { [weak self] i in
            guard let self, config.indicator.clickToFocus else { return }
            let id = stack.items[i].id
            queue.async { [client = yabai] in client.focus(window: id) }
            refresh()
        }
        v.onScroll = { [weak self] dir in
            guard let self, config.indicator.scrollToCycle, let current = stack.activeIndex else { return }
            let n = stack.items.count
            let id = stack.items[(current + dir + n) % n].id
            queue.async { [client = yabai] in client.focus(window: id) }
            refresh()
        }
        v.onHover = { [weak self] i in
            guard let self else { return }
            guard let i, config.indicator.titles == "hover" else { title.orderOut(nil); return }
            let l = StackRenderer.titleLayer(stack.items[i], style: style, icons: icons, scale: scale)
            let cell = IndicatorLayout.cell(i, metrics: config.indicator.metrics)
            let h = l.bounds.height, w = l.bounds.width
            let y = axRect.minY + cell.midY - h / 2
            // Beside the indicator, towards the window.
            let toRight = side == .left || side == .insideLeft
            let x = toRight ? axRect.maxX + 6 : axRect.minX - 6 - w
            let primary = NSScreen.screens.first?.frame.height ?? 0
            title.show(l, at: ScreenGeometry.cocoa(fromAX: CGRect(x: x, y: y, width: w, height: h), primaryHeight: primary))
        }
    }
}
