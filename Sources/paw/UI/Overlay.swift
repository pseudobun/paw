import AppKit
import PawCore
import QuartzCore

/// One transparent, click-through, non-activating panel per screen, above everything.
/// Panels are made once and reused, so opening a mode only adds layers.
final class Overlay {
    final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    struct Screen {
        let screen: NSScreen
        /// The screen in AX coordinates (top-left origin).
        let ax: CGRect
        let panel: Panel
        let root: CALayer
        var scale: CGFloat { screen.backingScaleFactor }
    }

    private(set) var screens: [Screen] = []
    private(set) var isVisible = false

    init() { rebuild() }

    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    func rebuild() {
        for s in screens { s.panel.orderOut(nil) }
        let primary = Self.primaryHeight
        screens = NSScreen.screens.map { screen in
            let panel = Panel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.setFrame(screen.frame, display: false)
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let root = CALayer()
            root.frame = view.bounds
            view.layer = root
            view.wantsLayer = true
            panel.contentView = view
            return Screen(screen: screen, ax: ScreenGeometry.axFrame(ofScreen: screen.frame, primaryHeight: primary), panel: panel, root: root)
        }
        if isVisible { show() }
    }

    func index(for axRect: CGRect) -> Int? {
        ScreenGeometry.screenIndex(for: axRect, screens: screens.map(\.ax))
    }

    /// The screen of the mouse pointer, for islands when there is no window.
    var pointerScreen: Int {
        let p = NSEvent.mouseLocation
        return screens.firstIndex { $0.screen.frame.contains(p) } ?? 0
    }

    /// Adds a layer whose frame is given in the screen's AX space (top-left origin).
    func add(_ layer: CALayer, axFrame: CGRect, screen i: Int) {
        guard screens.indices.contains(i) else { return }
        let s = screens[i]
        layer.frame = ScreenGeometry.layerRect(axFrame, inScreen: s.ax)
        s.root.addSublayer(layer)
    }

    /// Adds an island centred horizontally, `top` points below the top of screen `i`.
    func addIsland(_ layer: CALayer, top: CGFloat, screen i: Int) {
        guard screens.indices.contains(i) else { return }
        let ax = screens[i].ax
        let size = layer.bounds.size
        add(layer, axFrame: CGRect(x: (ax.midX - size.width / 2).rounded(), y: ax.minY + top, width: size.width, height: size.height), screen: i)
    }

    func show() {
        isVisible = true
        for s in screens where !(s.root.sublayers ?? []).isEmpty { s.panel.orderFrontRegardless() }
    }

    func hide() {
        isVisible = false
        for s in screens { s.panel.orderOut(nil) }
        clear()
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for s in screens { s.root.sublayers = nil }
        CATransaction.commit()
    }
}
