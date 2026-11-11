import AppKit
import PawCore

private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

/// Stand-ins for windows whose app won't let them get as small as their tile: the app's icon and
/// title in the tile, under every window (just above the desktop), so nothing sticks out over
/// the neighbours. A click zooms in until the window fits.
final class Placeholders {
    struct Item: Equatable {
        let id: WindowID
        let app: String
        let title: String
        /// AX coordinates.
        let frame: CGRect
        let focused: Bool
    }

    struct Actions {
        let focus: (WindowID) -> Void
        let zoom: (WindowID) -> Void
        /// Pointer in AX coordinates.
        let drag: (WindowID, CGPoint) -> Void
        let drop: (WindowID, CGPoint) -> Void
    }

    private var panels: [WindowID: (panel: NSPanel, view: PlaceholderView)] = [:]

    func apply(_ items: [Item], style: Style, focusFollowsMouse: Bool, focusBorder: WindowID?, actions: Actions) {
        let ids = Set(items.map(\.id))
        for (id, p) in panels where !ids.contains(id) {
            p.panel.orderOut(nil)
            panels[id] = nil
        }
        for item in items {
            let p = panels[item.id] ?? make()
            panels[item.id] = p
            p.view.item = item
            p.view.style = style
            p.view.actions = actions
            p.view.focusFollowsMouse = focusFollowsMouse
            p.view.focusBorderVisible = focusBorder == item.id
            let f = ScreenGeometry.cocoa(fromAX: item.frame, primaryHeight: primaryHeight)
            if p.panel.frame != f { p.panel.setFrame(f, display: false) }
            p.view.needsDisplay = true
            if !p.panel.isVisible { p.panel.orderFrontRegardless() }
        }
    }

    private func make() -> (panel: NSPanel, view: PlaceholderView) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        panel.collectionBehavior = [.ignoresCycle, .stationary, .canJoinAllSpaces]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        let v = PlaceholderView()
        panel.contentView = v
        return (panel, v)
    }
}

final class PlaceholderView: NSView {
    var item: Placeholders.Item?
    var style = Style(PawConfig.Appearance())
    var actions: Placeholders.Actions?
    var focusFollowsMouse = false
    var focusBorderVisible = false
    private var downAt: CGPoint?
    private var dragging = false
    private var area: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseMoved(with event: NSEvent) {
        guard focusFollowsMouse, NSEvent.pressedMouseButtons == 0, let item, !item.focused else { return }
        actions?.focus(item.id)
    }

    override func draw(_ dirty: NSRect) {
        guard let item else { return }
        let c = style.colors
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        c.island.withAlpha(1).ns.setFill()
        path.fill()
        let dash = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        dash.setLineDash([6, 5], count: 2, phase: 0)
        dash.lineWidth = 1
        if item.focused {
            if !focusBorderVisible {
                c.accent.ns.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        } else {
            c.muted.withAlpha(0.5).ns.setStroke()
            dash.stroke()
        }

        let side = min(56, r.width * 0.3, r.height * 0.3)
        let lines: CGFloat = r.height > side + 70 ? 3 : (r.height > side + 30 ? 1 : 0)
        let block = side + (lines > 0 ? 8 + 18 * lines : 0)
        var y = r.midY - block / 2
        let iconRect = CGRect(x: r.midX - side / 2, y: y, width: side, height: side)
        if side >= 12, let img = AppColors.shared.image(for: item.app, side: Int(saturating: side * (window?.backingScaleFactor ?? 2))) {
            NSImage(cgImage: img, size: iconRect.size).draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.9,
                                                            respectFlipped: true, hints: nil)
        }
        y = iconRect.maxY + 8
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingTail
        func line(_ s: String, _ font: NSFont, _ color: ARGB) {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color.ns, .paragraphStyle: p])
                .draw(with: CGRect(x: r.minX + 10, y: y, width: r.width - 20, height: 17), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y += 18
        }
        if lines >= 1 { line(item.app, style.bold, c.fg) }
        if lines >= 3 {
            let title = item.title == item.app ? "" : item.title
            line(title, style.font, c.muted)
            line("too small · move it, or double-click to zoom in", style.font, c.dim)
        }
    }

    private var pointer: CGPoint { ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primaryHeight) }

    override func mouseDown(with event: NSEvent) {
        guard let id = item?.id else { return }
        if event.clickCount == 2 { actions?.zoom(id); return }
        downAt = event.locationInWindow
        dragging = false
        actions?.focus(id)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = item?.id, let d = downAt else { return }
        if !dragging, hypot(event.locationInWindow.x - d.x, event.locationInWindow.y - d.y) < 5 { return }
        dragging = true
        actions?.drag(id, pointer)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil; dragging = false }
        guard dragging, let id = item?.id else { return }
        actions?.drop(id, pointer)
    }
}
