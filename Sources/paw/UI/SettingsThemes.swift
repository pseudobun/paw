import AppKit
import PawCore

/// The theme picker on the Appearance page, like hop's Theme command: the theme under the pointer
/// shows on every indicator around the window; a click switches to it.
extension SettingsController {
    func themePicker() -> NSView {
        let card = Card()
        let current = config.appearance.theme
        let changed = config.appearance.overrides.subtracting(["appFont", "appIconSize"])
        let tiles = Themes.all.map { t in
            ThemeTile(theme: t, selected: t.id == current, changed: t.id == current && !changed.isEmpty) { [unowned self] hovering in
                hoveredTheme = hovering ? t.id : (hoveredTheme == t.id ? nil : hoveredTheme)
                refreshStage()
            } pick: { [unowned self] in
                hoveredTheme = nil
                endEditing()
                write(rebuild: true) { $0 = Self.applying(t, to: $0) }
                refreshStage()
            }
        }
        let columns = 3
        let rows = stride(from: 0, to: tiles.count, by: columns).map { i -> NSStackView in
            let row = NSStackView(views: Array(tiles[i..<min(i + columns, tiles.count)]))
            row.spacing = 14
            row.distribution = .fillEqually
            return row
        }
        let grid = NSStackView(views: rows)
        grid.orientation = .vertical
        grid.spacing = 14
        grid.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        for row in rows { row.widthAnchor.constraint(equalTo: grid.widthAnchor, constant: -32).isActive = true }
        card.add(grid)

        let name = Themes.named(current)?.label ?? current
        let help = changed.isEmpty
            ? "Hover a theme to see it on the indicators around this window; click to use it. Colours, fonts and shape below start from the theme."
            : "\(name), changed: \(changed.sorted().joined(separator: ", ")). Keys set below override the theme."
        let reset = button("Reset to \(name)") { [unowned self] in
            endEditing()
            if let t = Themes.named(current) { write(rebuild: true) { $0 = Self.applying(t, to: $0) } }
        }
        reset.isEnabled = !changed.isEmpty
        card.add(rowStack([textColumn(changed.isEmpty ? name : "\(name) (changed)", help, width: Self.textWidth + 120), reset]))
        return card
    }
}

/// One theme: a small picture of its indicators over a desktop, its name under it; a ring in the
/// accent colour marks the one in use, as in System Settings' Appearance.
final class ThemeTile: NSView {
    let theme: IndicatorTheme
    private let selected: Bool
    private let changed: Bool
    private let hover: (Bool) -> Void
    private let pick: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }
    private static let thumbHeight: CGFloat = 88

    init(theme: IndicatorTheme, selected: Bool, changed: Bool, hover: @escaping (Bool) -> Void, pick: @escaping () -> Void) {
        self.theme = theme
        self.selected = selected
        self.changed = changed
        self.hover = hover
        self.pick = pick
        super.init(frame: .zero)
        toolTip = theme.summary
        heightAnchor.constraint(equalToConstant: Self.thumbHeight + 26).isActive = true
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(theme.label) theme")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; hover(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; hover(false) }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { pick() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let a = theme.appearance, c = a.colors
        let thumb = CGRect(x: 3, y: 3, width: bounds.width - 6, height: Self.thumbHeight - 6)

        // Selection ring, then the desktop.
        if selected || hovering {
            let ring = NSBezierPath(roundedRect: thumb.insetBy(dx: -3, dy: -3), xRadius: 11, yRadius: 11)
            ring.lineWidth = selected ? 3 : 2
            (selected ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
            ring.stroke()
        }
        let desk = NSBezierPath(roundedRect: thumb, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        desk.addClip()
        let top = theme.light ? NSColor(srgbRed: 0.80, green: 0.84, blue: 0.90, alpha: 1) : NSColor(srgbRed: 0.16, green: 0.17, blue: 0.22, alpha: 1)
        let bottom = theme.light ? NSColor(srgbRed: 0.93, green: 0.90, blue: 0.86, alpha: 1) : NSColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: thumb, angle: 90)

        // A window, its focus border, a stack beside it and the workspace HUD over it.
        let win = CGRect(x: thumb.minX + 34, y: thumb.minY + 26, width: thumb.width - 46, height: thumb.height - 34)
        let winPath = NSBezierPath(roundedRect: win, xRadius: 5, yRadius: 5)
        (theme.light ? NSColor(white: 1, alpha: 0.9) : NSColor(white: 0.2, alpha: 0.9)).setFill()
        winPath.fill()
        let borderPath = NSBezierPath(roundedRect: win.insetBy(dx: -1.5, dy: -1.5), xRadius: 6, yRadius: 6)
        theme.borderColor.ns.setStroke()
        borderPath.lineWidth = 1.2
        borderPath.stroke()

        let scale: CGFloat = 0.5
        func island(_ r: CGRect, radius: CGFloat) {
            let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            if a.shadow {
                NSGraphicsContext.saveGraphicsState()
                let sh = NSShadow()
                sh.shadowColor = NSColor(white: 0, alpha: a.shadowOpacity)
                sh.shadowBlurRadius = a.shadowRadius * scale
                sh.shadowOffset = NSSize(width: 0, height: -1)
                sh.set()
                c.island.ns.setFill()
                p.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                c.island.ns.setFill()
                p.fill()
            }
            if a.borderWidth > 0 {
                c.border.ns.setStroke()
                p.lineWidth = max(0.5, a.borderWidth * scale)
                p.stroke()
            }
        }
        // Stack: four cells, the first highlighted.
        let cellH: CGFloat = 11, sw: CGFloat = 16
        let stack = CGRect(x: thumb.minX + 10, y: win.minY, width: sw, height: cellH * 4 + 4)
        island(stack, radius: min(a.radius * scale, sw / 2))
        let dots = [c.accent, c.fg, c.muted, c.dim]
        for i in 0..<4 {
            let cell = CGRect(x: stack.minX + 2, y: stack.minY + 2 + CGFloat(i) * cellH, width: sw - 4, height: cellH)
            if i == 0 {
                c.islandHi.ns.setFill()
                NSBezierPath(roundedRect: cell, xRadius: min(a.cellRadius * scale, cellH / 2), yRadius: min(a.cellRadius * scale, cellH / 2)).fill()
            }
            dots[i].ns.setFill()
            NSBezierPath(ovalIn: CGRect(x: cell.midX - 2.5, y: cell.midY - 2.5, width: 5, height: 5)).fill()
        }
        // HUD: the workspace number in the theme's font, then app dots.
        let style = Style(a)
        let num = NSAttributedString(string: "3", attributes: [
            .font: Style.font(a.font, size: 10, weight: a.boldWeight), .foregroundColor: c.accent.ns,
        ])
        let hudH: CGFloat = 16, hudW: CGFloat = 56
        let hud = CGRect(x: win.midX - hudW / 2, y: thumb.minY + 6, width: hudW, height: hudH)
        island(hud, radius: style.pillRadius(hudH))
        let ns = num.size()
        num.draw(at: CGPoint(x: hud.minX + 8, y: hud.midY - ns.height / 2))
        for (i, col) in [c.fg, c.muted, c.accent].enumerated() {
            col.ns.setFill()
            NSBezierPath(ovalIn: CGRect(x: hud.minX + 22 + CGFloat(i) * 10, y: hud.midY - 2.5, width: 5, height: 5)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: theme.light ? 0 : 1, alpha: 0.12).setStroke()
        desk.lineWidth = 0.5
        desk.stroke()

        // Name, centred under the picture.
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let label = NSAttributedString(string: theme.label + (changed ? " •" : ""), attributes: [
            .font: Theme.sans(12, selected ? 600 : 400),
            .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: p,
        ])
        label.draw(in: CGRect(x: 0, y: Self.thumbHeight + 4, width: bounds.width, height: 18))
    }
}
