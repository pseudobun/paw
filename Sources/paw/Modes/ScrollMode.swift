import AppKit
import Carbon.HIToolbox
import PawCore

/// Numbers the scroll areas of the focused window; h/j/k/l scroll the selected one smoothly
/// while held (shift for speed), d/u half a page, g/G to the ends, digits or Tab switch areas.
final class ScrollMode: NSObject, Mode {
    let kind = Controller.Kind.scroll
    private unowned let controller: Controller
    private let target: Controller.Target
    private var areas: [Element] = []
    private var selected = 0
    private var closed = false
    private var layers: [CALayer] = []
    private var physics: ScrollPhysics
    /// Held direction keys and when they went down.
    private var held: [Character: CFTimeInterval] = [:]
    private var fast = false
    /// Remaining pixels of a d/u glide.
    private var glide: (x: Double, y: Double) = (0, 0)
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var idle: DispatchWorkItem?
    private var originalPointer: CGPoint?

    init(controller: Controller, target: Controller.Target) {
        self.controller = controller
        self.target = target
        let s = controller.config.scroll
        physics = ScrollPhysics(speed: s.speed, fastMultiplier: s.fastMultiplier, rampMs: s.rampMs)
        super.init()
        originalPointer = CGEvent(source: nil)?.location
        let options = controller.collectorOptions(.scroll)
        controller.collector.collect(pid: target.app.processIdentifier, bundleID: target.app.bundleIdentifier, options: options) {
            [weak self] r in self?.present(r)
        }
    }

    private func present(_ r: Collector.Result) {
        guard !closed else { return }
        var found = r.scrollAreas
        // Nested areas that cover their parent add nothing.
        found = ScreenGeometry.dedupe(found.map(\.frame), threshold: 0.9).map { found[$0] }
        if found.isEmpty, let w = r.windowFrame {
            found = [Element(ref: AXUIElementCreateApplication(target.app.processIdentifier), frame: w, role: "AXWindow",
                             subrole: nil, source: .window, clip: w)]
        }
        guard !found.isEmpty else {
            controller.dismiss()
            controller.notice("Nothing to scroll in \(target.name)", color: controller.style.colors.bad)
            return
        }
        areas = found
        let largest = areas.indices.max { areas[$0].frame.width * areas[$0].frame.height < areas[$1].frame.width * areas[$1].frame.height }
        select(largest ?? 0)
        Log.ax.info("scroll \(self.target.name, privacy: .public): \(self.areas.count) areas in \(r.ms, format: .fixed(precision: 1)) ms")
        resetIdle()
    }

    private func select(_ i: Int) {
        guard areas.indices.contains(i) else { return }
        selected = i
        let f = areas[i].frame
        let p = CGPoint(x: f.midX, y: f.midY)
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
        Clicker.postMove(to: p)
        render()
    }

    private func render() {
        let overlay = controller.overlay
        let style = controller.style
        let c = style.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in layers { l.removeFromSuperlayer() }
        layers = []
        for (i, a) in areas.enumerated() {
            guard let si = overlay.index(for: a.frame) else { continue }
            let screen = overlay.screens[si]
            let isSelected = i == selected
            if isSelected {
                let ring = CALayer()
                ring.borderColor = c.accent.withAlpha(0.8).cg
                ring.borderWidth = 1.5
                ring.cornerRadius = 8
                ring.cornerCurve = .continuous
                overlay.add(ring, axFrame: a.frame.insetBy(dx: 2, dy: 2), screen: si)
                layers.append(ring)
            }
            let badge = LabelLayer()
            badge.contentsScale = screen.scale
            badge.centered = true
            badge.text = style.text("\(i + 1)", isSelected ? c.accent : c.wave, font: style.labelFont)
            let h = style.a.labelHeight
            badge.bounds = CGRect(x: 0, y: 0, width: max(h, badge.text.size().width + style.a.labelPaddingX * 2), height: h)
            style.decorate(badge, radius: style.a.labelRadius, fill: isSelected ? c.islandHi : c.island, border: isSelected ? c.accent : c.border)
            overlay.add(badge, axFrame: CGRect(x: a.frame.minX + 8, y: a.frame.minY + 8, width: badge.bounds.width, height: h), screen: si)
            layers.append(badge)
        }
        if style.a.appIsland, let si = overlay.index(for: areas[selected].frame) {
            let island = controller.modeIsland(target, mode: "scroll", note: "\(selected + 1)/\(areas.count)  hjkl", screen: si)
            overlay.addIsland(island, top: style.a.islandTop, screen: si)
            layers.append(island)
        }
        CATransaction.commit()
        overlay.show()
    }

    func handle(_ key: KeyTap.Key) -> Bool {
        resetIdle()
        fast = key.shift
        if key.code == UInt16(kVK_Tab) {
            if key.down, !areas.isEmpty { select((selected + (key.shift ? areas.count - 1 : 1)) % areas.count) }
            return true
        }
        guard let ch = key.char else { return true }
        if "hjkl".contains(ch) {
            if key.down {
                if held[ch] == nil { held[ch] = CACurrentMediaTime() }
            } else {
                held[ch] = nil
            }
            updateLink()
            return true
        }
        guard key.down, !areas.isEmpty else { return true }
        if key.command { controller.dismiss(); return false }
        let page = areas[selected].frame.height
        switch ch {
        case "d": glide.y -= page / 2; updateLink()
        case "u": glide.y += page / 2; updateLink()
        case "g": post(dx: 0, dy: key.shift ? -1_000_000 : 1_000_000, continuous: false)
        default:
            if let n = ch.wholeNumberValue, n >= 1, n <= areas.count { select(n - 1) }
        }
        return true
    }

    func flagsChanged(_ flags: CGEventFlags) {
        fast = flags.contains(.maskShift)
    }

    private func updateLink() {
        let active = !held.isEmpty || glide.x != 0 || glide.y != 0
        if active, link == nil {
            let screen = controller.overlay.screens[safe: controller.overlay.index(for: areas[safe: selected]?.frame ?? .zero) ?? 0]?.screen
            link = (screen ?? NSScreen.screens[0]).displayLink(target: self, selector: #selector(tick(_:)))
            lastTick = 0
            link?.add(to: .main, forMode: .common)
        } else if !active, let l = link {
            l.invalidate()
            link = nil
            physics.reset()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick == 0 ? 1000 / 120 : min(50, (now - lastTick) * 1000)
        lastTick = now
        var dx = 0, dy = 0
        for k in held.keys {
            switch k {
            case "h": dx += 1
            case "l": dx -= 1
            case "j": dy -= 1
            case "k": dy += 1
            default: break
            }
        }
        let heldMs = (now - (held.values.min() ?? now)) * 1000
        var step = physics.step(dtMs: dt, heldMs: heldMs, dx: dx.signum(), dy: dy.signum(), fast: fast)
        // d/u glide: ease out over ~150 ms.
        for axis in 0..<2 {
            let rest = axis == 0 ? glide.x : glide.y
            guard rest != 0 else { continue }
            var part = (rest * min(1, dt / 50)).rounded(.towardZero)
            if abs(rest) < 2 || part == 0 { part = rest }
            if axis == 0 { glide.x -= part; step.x += Int(part) } else { glide.y -= part; step.y += Int(part) }
        }
        if step.x != 0 || step.y != 0 { post(dx: step.x, dy: step.y, continuous: true) }
        if held.isEmpty, glide.x == 0, glide.y == 0 { updateLink() }
    }

    private func post(dx: Int, dy: Int, continuous: Bool) {
        let sign: Int32 = controller.config.scroll.invert ? -1 : 1
        let y = Int32(clamping: dy) * sign, x = Int32(clamping: dx) * sign
        guard let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0) else { return }
        ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        ev.post(tap: .cghidEventTap)
    }

    private func resetIdle() {
        idle?.cancel()
        let s = controller.config.scroll.idleTimeout
        guard s > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !closed, held.isEmpty else { return }
            controller.dismiss()
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: work)
    }

    func tearDown() {
        closed = true
        idle?.cancel()
        link?.invalidate()
        link = nil
        held = [:]
        if controller.config.hint.restoreCursor, let p = originalPointer {
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }
}
