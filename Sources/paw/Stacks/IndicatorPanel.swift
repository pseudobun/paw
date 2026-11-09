import AppKit
import PawCore
import QuartzCore

/// One stack's indicator: a small borderless panel next to the window. It doesn't take focus;
/// clicks focus a window through yabai, scrolling moves through the stack.
final class IndicatorPanel: NSPanel {
    let view = IndicatorView()

    init() {
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
        contentView = view
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

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func redraw() {
        guard let render else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let l = render(hovered)
        l.frame = bounds
        layer?.sublayers = [l]
        CATransaction.commit()
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
        return IndicatorLayout.cellIndex(at: p, count: stack.items.count, metrics: metrics)
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
        let v = NSView()
        v.layer = CALayer()
        v.wantsLayer = true
        contentView = v
    }

    override var canBecomeKey: Bool { false }

    func show(_ l: CALayer, at cocoaFrame: CGRect) {
        setFrame(cocoaFrame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.frame = CGRect(origin: .zero, size: cocoaFrame.size)
        contentView?.layer?.sublayers = [l]
        CATransaction.commit()
        orderFrontRegardless()
    }
}
