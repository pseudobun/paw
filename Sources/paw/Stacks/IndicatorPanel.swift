import AppKit
import PawCore
import QuartzCore

/// One stack's indicator: a small borderless panel next to the window. It doesn't take focus;
/// clicks focus a window, scrolling moves through the stack.
final class IndicatorPanel: NSPanel {
    let view = IndicatorView()
    /// Puts the island on Liquid Glass when the style asks for it.
    let host: GlassHost

    init() {
        host = GlassHost(content: view)
        host.interactive = true
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // Stays on the space it was shown on, so it slides away with its windows.
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        alphaValue = 0
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class IndicatorView: NSView {
    var stack: Stack?
    var render: ((Int?) -> CALayer)?
    var onClick: ((Int) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onHover: ((Int?) -> Void)?
    var metrics = IndicatorLayout.Metrics()
    private var hovered: Int?
    private var scrollAccum: CGFloat = 0
    private var area: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // Not flipped: AppKit flips a flipped view's layer whenever it lays the view out, which
    // turned the bottom-up rendered island (and its icons) upside down. Points are flipped by hand.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The top window's cell, kept across redraws so it can glide to the next one like the
    /// tip bar's sliding highlights.
    var makeHighlight: (() -> CALayer)?
    /// Where the highlight sits, top-left coordinates (the panel's height changes with the stack).
    private var highlightCell: CGRect?

    /// The tip bar's motion: highlights glide over 220 ms (easeOutQuint), content swaps in 80 ms.
    static let glide: CFTimeInterval = 0.22
    static let contentFade: CFTimeInterval = 0.08

    /// Draws the stack again; `animated`, the highlight glides to the window now on top and the
    /// icons cross-fade, as in the tip bar.
    func redraw(animated: Bool = false) {
        guard let render else { return }
        let motion = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let l = render(hovered)
        l.frame = bounds
        if motion, layer?.sublayers?.isEmpty == false {
            let t = CATransition()
            t.type = .fade
            t.duration = Self.contentFade
            layer?.add(t, forKey: "redraw")
        }
        layer?.sublayers = [l]
        placeHighlight(in: l, animated: motion)
        CATransaction.commit()
    }

    private func placeHighlight(in root: CALayer, animated: Bool) {
        guard let stack, let i = stack.activeIndex, let makeHighlight else {
            highlightCell = nil
            return
        }
        let h = makeHighlight()
        let cell = IndicatorLayout.cell(i, metrics: metrics)
        func frame(_ tl: CGRect) -> CGRect { CGRect(x: tl.minX, y: bounds.height - tl.maxY, width: tl.width, height: tl.height) }
        h.frame = frame(cell)
        root.insertSublayer(h, at: 0)
        if animated, let from = highlightCell, from != cell {
            let a = CABasicAnimation(keyPath: "position")
            let f = frame(from)
            a.fromValue = NSValue(point: CGPoint(x: f.midX, y: f.midY))
            a.toValue = NSValue(point: CGPoint(x: h.frame.midX, y: h.frame.midY))
            a.duration = Self.glide
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            h.add(a, forKey: "glide")
        }
        highlightCell = cell
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    private func cell(at event: NSEvent) -> Int? {
        guard let stack else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let topLeft = CGPoint(x: p.x, y: bounds.height - p.y)
        return IndicatorLayout.cellIndex(at: topLeft, count: stack.items.count, metrics: metrics)
    }

    override func mouseMoved(with event: NSEvent) { setHovered(cell(at: event)) }
    override func mouseEntered(with event: NSEvent) { setHovered(cell(at: event)) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func setHovered(_ i: Int?) {
        guard i != hovered else { return }
        hovered = i
        redraw()
        onHover?(i)
    }

    override func mouseDown(with event: NSEvent) {
        if let i = cell(at: event) { onClick?(i) }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccum += event.scrollingDeltaY
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 24 : 1
        if abs(scrollAccum) >= step {
            onScroll?(scrollAccum > 0 ? -1 : 1)
            scrollAccum = 0
        }
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccum = 0 }
    }
}

/// The floating title island shown next to a hovered icon.
final class TitlePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = host
    }

    override var canBecomeKey: Bool { false }

    /// Holds the island's layers, on glass when the island is a glass one.
    let host = GlassHost(content: GlassHost.layerView())

    func show(_ l: CALayer, at cocoaFrame: CGRect) {
        setFrame(cocoaFrame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.frame = CGRect(origin: .zero, size: cocoaFrame.size)
        host.content.layer?.sublayers = [l]
        host.adopt(l)
        CATransaction.commit()
        orderFrontRegardless()
    }
}
