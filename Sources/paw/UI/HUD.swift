import AppKit
import PawCore
import QuartzCore

/// The island that flashes when the workspace changes: its number, then one icon per app on it.
final class WorkspaceHUD {
    var style = Style(PawConfig.Appearance())
    private let panel = TitlePanel()
    private var hideWork: DispatchWorkItem?
    private var layers = LayerCache()

    struct LayerCache {
        private struct Key: Equatable {
            let label: String
            let apps: [String]
            let appearance: PawConfig.Appearance
            let font: NSFont
            let bold: NSFont
            let appFont: NSFont?
            let glyphs: [String]
            let colors: [ARGB]
            let scale: CGFloat
        }

        private var entries: [(key: Key, layer: CALayer)] = []

        mutating func layer(label: String, apps: [String], icons: AppIconMap, config: PawConfig, style: Style, scale: CGFloat) -> CALayer {
            // shortcut: image fallbacks can change when AppColors evicts images; rebuild until images have a comparable revision.
            guard style.appFont != nil || apps.isEmpty else {
                return WorkspaceHUD.layer(label: label, apps: apps, icons: icons, config: config, style: style, scale: scale)
            }
            let glyphs = apps.prefix(12).map { icons.glyph(for: $0) }
            let colors = apps.prefix(12).map { AppColors.shared.color(for: $0, icons: config.icons) ?? style.colors.fg }
            let key = Key(label: label, apps: apps, appearance: style.a, font: style.font, bold: style.bold,
                          appFont: style.appFont, glyphs: glyphs, colors: colors, scale: scale)
            if let entry = entries.first(where: { $0.key == key }) { return entry.layer }
            let root = WorkspaceHUD.layer(label: label, apps: apps, glyphs: glyphs, colors: colors, style: style, scale: scale)
            // Two islands cover alternating workspaces without retaining every workspace/zoom label.
            if entries.count == 2 { entries.removeFirst() }
            entries.append((key, root))
            return root
        }
    }

    /// The HUD's island: the workspace's label, then its apps' icons.
    static func layer(label: String, apps: [String], icons: AppIconMap, config: PawConfig, style: Style, scale: CGFloat) -> CALayer {
        let glyphs = apps.prefix(12).map { icons.glyph(for: $0) }
        let colors = apps.prefix(12).map { AppColors.shared.color(for: $0, icons: config.icons) ?? style.colors.fg }
        return layer(label: label, apps: apps, glyphs: glyphs, colors: colors, style: style, scale: scale)
    }

    private static func layer(label: String, apps: [String], glyphs: [String], colors: [ARGB], style: Style, scale: CGFloat) -> CALayer {
        let c = style.colors
        var segs: [Island.Segment] = [.init(text: style.text(label, c.accent, font: style.bold), gapAfter: apps.isEmpty ? 0 : 10)]
        for (i, app) in apps.prefix(12).enumerated() {
            segs.append(.init(text: style.appGlyph(glyphs[i], app: app, color: colors[i]), gapAfter: i == apps.count - 1 ? 0 : 8))
        }
        let inner = Island.make(segs, style: style, scale: scale)
        let h = style.islandHeight + 2
        let root = CALayer()
        root.contentsScale = scale
        root.bounds = CGRect(x: 0, y: 0, width: inner.bounds.width, height: h)
        style.decorate(root, radius: style.pillRadius(h))
        inner.backgroundColor = nil
        inner.borderWidth = 0
        inner.shadowOpacity = 0
        inner.frame = CGRect(x: 0, y: (h - inner.bounds.height) / 2, width: inner.bounds.width, height: inner.bounds.height)
        root.addSublayer(inner)
        return root
    }

    /// `area` in AX coordinates (the display's tiling area).
    func show(label: String, apps: [String], in area: CGRect, icons: AppIconMap, config: PawConfig, duration: Double) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let root = layers.layer(label: label, apps: apps, icons: icons, config: config, style: style, scale: scale)
        let w = root.bounds.width, h = root.bounds.height
        // Just under the top of the tiling area, over the windows' title bars.
        let ax = CGRect(x: (area.midX - w / 2).rounded(), y: area.minY + 10, width: w, height: h)
        let frame = ScreenGeometry.cocoa(fromAX: ax, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        hideWork?.cancel()
        let wasVisible = panel.isVisible && panel.alphaValue > 0.4
        panel.show(root, at: frame)
        if !wasVisible {
            if style.glass { Glass.settle(root) }
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = style.a.hudOpacity
            }
        } else {
            panel.alphaValue = style.a.hudOpacity
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.panel.alphaValue ?? 1 < 0.05 { self?.panel.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, duration), execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }
}

/// While a workspace is being moved (`move-workspace next|prev`, hyper+š/đ): the workspaces on
/// either side of it and where it is now, held on screen as long as hyper is; an empty dashed
/// slot marks the start or the end when there is nowhere further to go.
final class MoveHUD {
    struct Cell {
        let label: String
        let apps: [String]
    }

    var style = Style(PawConfig.Appearance())
    private let panel = TitlePanel()
    private var timer: Timer?
    private var shownAt = Date.distantPast

    /// The strip: the neighbours, arrows and the moving workspace.
    /// `side`: the side workspace, shown dimmed before the start (it stays first).
    static func layer(prev: Cell?, current: Cell, next: Cell?, side: Cell? = nil, icons: AppIconMap, config: PawConfig,
                      style: Style, scale: CGFloat) -> CALayer {
        let c = style.colors
        let h = style.islandHeight + 18, pad: CGFloat = 8, gap: CGFloat = 6
        var parts: [CALayer] = []

        func cellLayer(_ cell: Cell, active: Bool) -> CALayer {
            var segs: [Island.Segment] = [.init(text: style.text(cell.label, active ? c.accent : c.muted, font: style.bold),
                                                gapAfter: cell.apps.isEmpty ? 0 : 8)]
            for (i, app) in cell.apps.prefix(5).enumerated() {
                let color = AppColors.shared.color(for: app, icons: config.icons) ?? c.fg
                segs.append(.init(text: style.appGlyph(icons.glyph(for: app), app: app, color: active ? color : color.withAlpha(0.55)),
                                  gapAfter: i == min(4, cell.apps.count - 1) ? 0 : 6))
            }
            if cell.apps.isEmpty, !active { segs[0] = .init(text: style.text(cell.label, c.dim, font: style.bold)) }
            let l = Island.make(segs, style: style, scale: scale)
            l.backgroundColor = (active ? c.islandHi : c.island.withAlpha(0)).cg
            l.borderColor = (active ? c.accent : c.border).cg
            l.borderWidth = active ? 1.5 : 0
            l.shadowOpacity = 0
            l.cornerRadius = style.pillRadius(l.bounds.height)
            return l
        }
        func text(_ s: String, _ color: ARGB) -> CALayer {
            let t = TextLayer()
            t.contentsScale = scale
            t.centered = true
            t.text = style.text(s, color, font: style.bold)
            t.bounds = CGRect(x: 0, y: 0, width: 14, height: 28)
            return t
        }
        /// The edge: nothing further that way.
        /// The end of the order: an empty dashed slot saying so.
        func end(_ word: String) -> CALayer {
            let t = style.text(word, c.dim, font: style.font)
            let w = (t.size().width + 20).rounded()
            let slot = CAShapeLayer()
            slot.contentsScale = scale
            slot.bounds = CGRect(x: 0, y: 0, width: w, height: style.islandHeight)
            let r = style.pillRadius(style.islandHeight)
            slot.path = CGPath(roundedRect: slot.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: r, cornerHeight: r, transform: nil)
            slot.fillColor = nil
            slot.strokeColor = c.dim.withAlpha(0.7).cg
            slot.lineWidth = 1
            slot.lineDashPattern = [4, 3]
            let label = TextLayer()
            label.contentsScale = scale
            label.centered = true
            label.text = t
            label.frame = slot.bounds
            slot.addSublayer(label)
            return slot
        }

        if prev == nil, let side {
            let s = cellLayer(side, active: false)
            s.opacity = 0.45
            parts.append(s)
        }
        parts.append(prev.map { cellLayer($0, active: false) } ?? end("start"))
        parts.append(text("‹", prev == nil ? c.dim : c.muted))
        parts.append(cellLayer(current, active: true))
        parts.append(text("›", next == nil ? c.dim : c.muted))
        parts.append(next.map { cellLayer($0, active: false) } ?? end("end"))

        let width = parts.reduce(0) { $0 + $1.bounds.width } + gap * CGFloat(parts.count - 1) + pad * 2
        let root = CALayer()
        root.contentsScale = scale
        root.bounds = CGRect(x: 0, y: 0, width: width, height: h)
        style.decorate(root, radius: style.pillRadius(h))
        var x = pad
        for p in parts {
            p.frame = CGRect(x: x, y: ((h - p.bounds.height) / 2).rounded(), width: p.bounds.width, height: p.bounds.height)
            root.addSublayer(p)
            x += p.bounds.width + gap
        }
        return root
    }

    /// `area` in AX coordinates.
    func show(prev: Cell?, current: Cell, next: Cell?, side: Cell? = nil, in area: CGRect, icons: AppIconMap, config: PawConfig) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let root = Self.layer(prev: prev, current: current, next: next, side: side, icons: icons, config: config, style: style, scale: scale)
        let width = root.bounds.width, h = root.bounds.height
        let ax = CGRect(x: (area.midX - width / 2).rounded(), y: area.minY + 10, width: width, height: h)
        if style.glass, !panel.isVisible || panel.alphaValue < 0.4 { Glass.settle(root) }
        panel.show(root, at: ScreenGeometry.cocoa(fromAX: ax, primaryHeight: NSScreen.screens.first?.frame.height ?? 0))
        panel.alphaValue = 0.95
        shownAt = Date()
        watchHyper()
    }

    /// Stays while hyper is held (⌘⌃⌥⇧ together, or the Caps Lock / F20 key a hyper-key app
    /// turns into them), then fades.
    private func watchHyper() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let hyper = flags.contains([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            let held = hyper || CGEventSource.keyState(.hidSystemState, key: 0x5A) || CGEventSource.keyState(.hidSystemState, key: 0x39)
            let age = Date().timeIntervalSince(shownAt)
            guard !held && age > 0.35 || age > 15 else { return }
            t.invalidate()
            hide()
        }
    }

    func hide() {
        timer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if (self?.panel.alphaValue ?? 1) < 0.05 { self?.panel.orderOut(nil) }
        })
    }
}
