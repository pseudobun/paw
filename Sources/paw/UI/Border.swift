import AppKit
import PawCore
import QuartzCore

/// The line around the focused window (`border`): one click-through panel, ordered just above
/// that window so windows in front of it still cover it.
final class FocusBorder {
    let panel: NSPanel
    let shape = CAShapeLayer()
    private struct State: Equatable {
        let id: WindowID
        let frame: CGRect
        let above: Bool
        let screen: CGRect
        let primaryHeight: CGFloat
        let config: PawConfig.Border
        let radius: CGFloat
    }
    private var shownFor: State?
    var windowID: WindowID? { shownFor?.id }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .normal
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        shape.fillColor = nil
        v.layer?.addSublayer(shape)
        panel.contentView = v
    }

    /// `frame` in AX coordinates; nil hides it.
    /// At a screen edge the stroke moves inward just enough to remain visible.
    func show(_ frame: CGRect?, window id: WindowID, above: Bool, screen: CGRect, config: PawConfig.Border, radius: CGFloat? = nil) {
        guard config.enabled, config.width > 0, let frame else { hide(); return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let o = config.offset + config.width / 2
        let radius = max(0, (radius ?? CGFloat(config.radius)) + CGFloat(o))
        let state = State(id: id, frame: frame, above: above, screen: screen, primaryHeight: primaryHeight, config: config, radius: radius)
        if shownFor == state, panel.isVisible { return }
        let ax = frame.insetBy(dx: -o - config.width, dy: -o - config.width).intersection(screen)
        guard !ax.isNull, ax.width > 2 * config.width, ax.height > 2 * config.width else { hide(); return }
        let cocoa = ScreenGeometry.cocoa(fromAX: ax, primaryHeight: primaryHeight)
        let visibleOutline = frame.insetBy(dx: -o, dy: -o).intersection(screen.insetBy(dx: config.width / 2, dy: config.width / 2))
        guard !visibleOutline.isNull, !visibleOutline.isEmpty else { hide(); return }
        let outline = ScreenGeometry.cocoa(fromAX: visibleOutline, primaryHeight: primaryHeight)
        let r = outline.offsetBy(dx: -cocoa.minX, dy: -cocoa.minY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if panel.frame != cocoa { panel.setFrame(cocoa, display: false) }
        shape.frame = CGRect(origin: .zero, size: cocoa.size)
        if shape.path?.boundingBoxOfPath != r || shownFor?.radius != radius {
            shape.path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        if shape.lineWidth != config.width { shape.lineWidth = config.width }
        if shownFor?.config.color != config.color { shape.strokeColor = config.color.cg }
        CATransaction.commit()
        let moved = shownFor?.id != id || shownFor?.frame != frame || shownFor?.above != above || !panel.isVisible
        if moved {
            panel.level = above ? .normal : NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            if above { panel.order(.above, relativeTo: Int(id)) }
            else { panel.orderFrontRegardless() }
        }
        shownFor = state
    }

    func hide() {
        guard shownFor != nil else { return }
        shownFor = nil
        panel.orderOut(nil)
    }
}
