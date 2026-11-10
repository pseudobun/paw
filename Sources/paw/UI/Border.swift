import AppKit
import PawCore
import QuartzCore

/// The line around the focused window (`border`): one click-through panel, ordered just above
/// that window so windows in front of it still cover it.
final class FocusBorder {
    private let panel: NSPanel
    private let shape = CAShapeLayer()
    private var shownFor: (id: WindowID, frame: CGRect)?

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
    /// `screen`: the display's frame; the line stays on it (at the bottom edge a window reaches
    /// the screen, so the line moves in rather than off).
    func show(_ frame: CGRect?, window id: WindowID, above: Bool, screen: CGRect, config: PawConfig.Border) {
        guard config.enabled, let frame else { hide(); return }
        let o = config.offset + config.width / 2
        let ax = frame.insetBy(dx: -o - config.width, dy: -o - config.width).intersection(screen)
        guard !ax.isNull, ax.width > 2 * config.width, ax.height > 2 * config.width else { hide(); return }
        let cocoa = ScreenGeometry.cocoa(fromAX: ax, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if panel.frame != cocoa { panel.setFrame(cocoa, display: false) }
        let r = CGRect(origin: .zero, size: cocoa.size).insetBy(dx: config.width, dy: config.width)
        let radius = config.radius + o
        shape.frame = CGRect(origin: .zero, size: cocoa.size)
        shape.path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shape.lineWidth = config.width
        shape.strokeColor = config.color.cg
        CATransaction.commit()
        let moved = shownFor?.id != id || shownFor?.frame != frame || !panel.isVisible
        if above {
            // Ordering is a window-server round trip: only when the window or its place changed.
            if moved { panel.order(.above, relativeTo: Int(id)) }
        } else {
            // A placeholder sits under every window; so does its border.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
            panel.orderFrontRegardless()
        }
        if above { panel.level = .normal }
        shownFor = (id, frame)
    }

    func hide() {
        guard shownFor != nil else { return }
        shownFor = nil
        panel.orderOut(nil)
    }
}
