import AppKit
import PawCore
import QuartzCore

/// The island that flashes when the workspace changes: its number, then one icon per app on it.
final class WorkspaceHUD {
    var style = Style(PawConfig.Appearance())
    private let panel = TitlePanel()
    private var hideWork: DispatchWorkItem?

    /// `area` in AX coordinates (the display's tiling area).
    func show(label: String, apps: [String], in area: CGRect, icons: AppIconMap, config: PawConfig, duration: Double) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let c = style.colors
        var segs: [Island.Segment] = [.init(text: style.text(label, c.accent, font: style.bold), gapAfter: apps.isEmpty ? 0 : 10)]
        for (i, app) in apps.prefix(12).enumerated() {
            let color = AppColors.shared.color(for: app, icons: config.icons) ?? c.fg
            segs.append(.init(text: style.appGlyph(icons.glyph(for: app), app: app, color: color), gapAfter: i == apps.count - 1 ? 0 : 8))
        }
        let l = Island.make(segs, style: style, scale: scale)
        let h: CGFloat = 30
        let w = l.bounds.width
        let inner = l
        let root = CALayer()
        root.contentsScale = scale
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        style.decorate(root, radius: h / 2)
        inner.backgroundColor = nil
        inner.borderWidth = 0
        inner.shadowOpacity = 0
        inner.frame = CGRect(x: 0, y: (h - inner.bounds.height) / 2, width: inner.bounds.width, height: inner.bounds.height)
        root.addSublayer(inner)
        // Just under the top of the tiling area, over the windows' title bars.
        let ax = CGRect(x: (area.midX - w / 2).rounded(), y: area.minY + 10, width: w, height: h)
        let frame = ScreenGeometry.cocoa(fromAX: ax, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        hideWork?.cancel()
        let wasVisible = panel.isVisible && panel.alphaValue > 0.4
        panel.show(root, at: frame)
        if !wasVisible {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 0.85
            }
        } else {
            panel.alphaValue = 0.85
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
