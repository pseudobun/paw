import AppKit
import PawCore
import QuartzCore

private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

/// The ghost of where a dragged window will land: a translucent accent rectangle that glides
/// between drop zones.
final class DropPreview {
    private let panel: NSPanel
    private let box = CALayer()
    private var visible = false

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        v.layer?.addSublayer(box)
        panel.contentView = v
    }

    /// `frame` in AX coordinates.
    func show(_ frame: CGRect, style: Style) {
        let c = style.colors
        let target = ScreenGeometry.cocoa(fromAX: frame, primaryHeight: primaryHeight)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.backgroundColor = c.accent.withAlpha(0.16).cg
        box.borderColor = c.accent.withAlpha(0.85).cg
        box.borderWidth = 2
        box.cornerRadius = 12
        box.cornerCurve = .continuous
        CATransaction.commit()
        if !visible {
            panel.setFrame(target, display: false)
            box.frame = CGRect(origin: .zero, size: target.size)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
            visible = true
        } else if panel.frame != target {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            box.frame = CGRect(origin: .zero, size: target.size)
            CATransaction.commit()
        }
    }

    func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in panel.orderOut(nil) })
    }
}

// MARK: - Seam handles

/// Thin panels in the gaps between tiles, under every window (just above the desktop), so the
/// gap itself can be dragged: both sides resize, and tiles further along give way once one
/// reaches its minimum. Double-click evens out the two sides. A line fades in on hover.
final class SeamHandles {
    private weak var wm: WindowManager?
    private var panels: [String: SeamPanel] = [:]
    /// Panels out of use, kept for the next seams: a workspace switch swaps every seam, and a new
    /// panel is a new window-server window each time.
    private var spare: [SeamPanel] = []
    private static let maxSpare = 24
    private(set) var dragging = false
    /// Panels made so far (tests).
    private(set) var created = 0

    init(wm: WindowManager?) { self.wm = wm }

    func update() {
        guard !dragging, let wm else { return }
        apply(wm.visibleSeams(), accent: wm.indicators.style.colors.accent)
    }

    func apply(_ seams: [WindowManager.SeamInfo], accent: ARGB) {
        guard !dragging else { return }
        let keys = Set(seams.map(\.key))
        var free: [SeamPanel] = []
        for (k, p) in panels where !keys.contains(k) {
            panels[k] = nil
            free.append(p)
        }
        for s in seams {
            let p = panels[s.key] ?? free.popLast() ?? spare.popLast() ?? make()
            panels[s.key] = p
            let changed = p.view.seam != s || p.view.accent != accent
            p.view.seam = s
            p.view.accent = accent
            // At least 8 pt to grab, even with small gaps.
            var f = s.frame
            if s.axis == .horizontal, f.width < 8 { f = f.insetBy(dx: -(8 - f.width) / 2, dy: 0) }
            if s.axis == .vertical, f.height < 8 { f = f.insetBy(dx: 0, dy: -(8 - f.height) / 2) }
            let cocoa = ScreenGeometry.cocoa(fromAX: f, primaryHeight: primaryHeight)
            if p.frame != cocoa { p.setFrame(cocoa, display: false) }
            if changed { p.view.needsDisplay = true }
            if !p.isVisible { p.orderFrontRegardless() }
        }
        for p in free {
            p.orderOut(nil)
            p.view.seam = nil
            if spare.count < Self.maxSpare { spare.append(p) }
        }
    }

    private func make() -> SeamPanel {
        created += 1
        let p = SeamPanel()
        p.view.onBegin = { [weak self] s in self?.dragging = true; self?.wm?.seamBegan(s) }
        p.view.onDrag = { [weak self] s, pt in self?.wm?.seamDragged(s, to: pt) }
        p.view.onEnd = { [weak self] s in
            self?.dragging = false
            self?.wm?.seamEnded(s)
        }
        p.view.onDoubleClick = { [weak self] s in self?.wm?.seamEqualize(s) }
        return p
    }

    /// Shown seam panels (tests).
    var shownCount: Int { panels.count }

    func hideAll() {
        for p in panels.values {
            p.orderOut(nil)
            p.view.seam = nil
            if spare.count < Self.maxSpare { spare.append(p) }
        }
        panels = [:]
    }
}

final class SeamPanel: NSPanel {
    let view = SeamView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Just below every normal window (above the desktop and anything covering it, such as a
        // screen recorder hiding desktop icons): only the bare gap is grabbable.
        level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        collectionBehavior = [.ignoresCycle, .stationary, .canJoinAllSpaces]
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SeamView: NSView {
    var seam: WindowManager.SeamInfo?
    var accent = ARGB(0xffea_d186)
    var onBegin: ((WindowManager.SeamInfo) -> Void)?
    var onDrag: ((WindowManager.SeamInfo, CGPoint) -> Void)?
    var onEnd: ((WindowManager.SeamInfo) -> Void)?
    var onDoubleClick: ((WindowManager.SeamInfo) -> Void)?
    private var hover = false
    private var active = false
    private var area: NSTrackingArea?
    private var lastDrag = Date.distantPast

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    private var cursor: NSCursor { seam?.axis == .vertical ? .resizeUpDown : .resizeLeftRight }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true; cursor.set() }
    override func mouseExited(with event: NSEvent) { hover = false; if !active { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard hover || active, let seam else { return }
        let w: CGFloat = 3
        let r = seam.axis == .horizontal
            ? CGRect(x: (bounds.midX - w / 2).rounded(), y: bounds.minY + 8, width: w, height: max(0, bounds.height - 16))
            : CGRect(x: bounds.minX + 8, y: (bounds.midY - w / 2).rounded(), width: max(0, bounds.width - 16), height: w)
        accent.withAlpha(active ? 0.95 : 0.6).ns.setFill()
        NSBezierPath(roundedRect: r, xRadius: w / 2, yRadius: w / 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard let seam else { return }
        if event.clickCount == 2 { onDoubleClick?(seam); return }
        active = true
        needsDisplay = true
        onBegin?(seam)
    }

    override func mouseDragged(with event: NSEvent) {
        guard active, let seam else { return }
        // ~60 fps is plenty; apps redraw on every resize.
        guard Date().timeIntervalSince(lastDrag) > 1.0 / 60 else { return }
        lastDrag = Date()
        let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primaryHeight)
        onDrag?(seam, p)
    }

    override func mouseUp(with event: NSEvent) {
        guard active, let seam else { return }
        active = false
        needsDisplay = true
        let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primaryHeight)
        onDrag?(seam, p)
        onEnd?(seam)
    }
}

// MARK: - Gestures

/// Hold a mouse button (middle, back, forward), drag in a direction, release: runs a command.
/// Buttons with gestures are taken over; a press that doesn't move is sent on as a normal click.
///
/// The tap runs on `EventTapThread`, and only listens for what the config uses: no scroll or
/// trackpad events without a zoom modifier, no button events without gestures, no tap at all
/// with neither. The config it reads is swapped under `lock`.
final class MouseGestures {
    private weak var wm: WindowManager?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tapMask: CGEventMask = 0
    private var started = false
    private let lock = NSLock()
    private var byButton: [Int: [String: [Command]]] = [:]
    private var ignore: [String] = []
    private var zoomFlags: CGEventFlags?
    /// The frontmost app's name, kept by the main thread (NSWorkspace belongs to it).
    private var frontApp: String?
    private var activation: NSObjectProtocol?
    // Tap thread only.
    private var scrollAccum: Double = 0
    private var pinchAccum: Double = 0
    private var lastZoom = Date.distantPast
    private var down: (button: Int, at: CGPoint)?
    /// Marks the clicks paw sends on, so the tap lets them through.
    private static let marker: Int64 = 0x7061_7721

    init(wm: WindowManager) { self.wm = wm }

    /// The events a tap needs for this config; 0 for none.
    static func mask(zoom: Bool, buttons: Bool) -> CGEventMask {
        var types: [CGEventType] = []
        if buttons { types += [.otherMouseDown, .otherMouseUp, .otherMouseDragged] }
        if zoom { types.append(.scrollWheel) }
        var m = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        // 29: gesture events (pinch arrives as one), not in CGEventType.
        if zoom { m |= 1 << 29 }
        return m
    }

    func configChanged() {
        var buttons: [Int: [String: [Command]]] = [:]
        let flags: CGEventFlags? = switch wm?.config.mouse.zoomModifier ?? "alt" {
        case "cmd": .maskCommand
        case "ctrl": .maskControl
        case "shift": .maskShift
        case "off": nil
        default: .maskAlternate
        }
        for g in wm?.config.mouse.gestures ?? [] {
            guard let b = g.buttonNumber, let cmds = try? Command.parseAll(g.command) else { continue }
            buttons[b, default: [:]][g.direction.lowercased()] = cmds
        }
        let ignore = wm?.config.mouse.gestureIgnoreApps ?? []
        lock.withLock {
            byButton = buttons
            zoomFlags = flags
            self.ignore = ignore
        }
        // Listen for what this config needs, nothing more.
        if started, Self.mask(zoom: flags != nil, buttons: !buttons.isEmpty) != tapMask {
            stopTap()
            startTap()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.lock.withLock { self?.frontApp = app?.localizedName }
        }
        startTap()
    }

    private func startTap() {
        let mask = lock.withLock { Self.mask(zoom: zoomFlags != nil, buttons: !byButton.isEmpty) }
        tapMask = mask
        guard tap == nil, mask != 0 else { return }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MouseGestures>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let src = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            Log.app.error("mouse gestures: event tap not allowed (Accessibility)")
            return
        }
        tap = port
        source = src
        EventTapThread.shared.add(src)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { EventTapThread.shared.remove(source) }
        tap = nil
        source = nil
        tapMask = 0
    }

    /// Is the tap listening? (status, tests)
    var listening: CGEventMask { tap == nil ? 0 : tapMask }

    private func ignored() -> Bool {
        lock.withLock { frontApp.map { app in ignore.contains { AppMatcher.matches($0, app) } } ?? false }
    }

    /// True: swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return false }
        if type == .scrollWheel || type.rawValue == 29 { return zoom(type, event) }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard let gestures = lock.withLock({ byButton[button] }), !gestures.isEmpty else { return false }
        let p = event.location
        switch type {
        case .otherMouseDown:
            if ignored() {
                down = nil
                return false
            }
            down = (button, p)
            return true
        case .otherMouseDragged:
            return down?.button == button
        case .otherMouseUp:
            guard let d = down, d.button == button else { return false }
            down = nil
            let dx = p.x - d.at.x, dy = p.y - d.at.y
            if max(abs(dx), abs(dy)) < 30 {
                if let cmds = gestures["click"] {
                    DispatchQueue.main.async { [weak self] in self?.wm?.run(cmds) }
                } else {
                    replayClick(button: button, at: d.at)
                }
                return true
            }
            let dir = abs(dx) > abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up")
            if let cmds = gestures[dir] { DispatchQueue.main.async { [weak self] in self?.wm?.run(cmds) } }
            return true
        default:
            return false
        }
    }

    /// ⌥-scroll and ⌥-pinch: one step through the tree per notch (or a good pinch), at most
    /// four a second. Only the exact modifier counts, so ⌥⇧-scroll and the like stay the app's.
    private func zoom(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard let want = lock.withLock({ zoomFlags }) else { return false }
        let mods: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        guard event.flags.intersection(mods) == want else { scrollAccum = 0; pinchAccum = 0; return false }
        if ignored() { return false }
        var step = 0
        if type == .scrollWheel {
            let precise = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            let dy = precise ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1) * 30
            scrollAccum += dy
            if abs(scrollAccum) >= 40 { step = scrollAccum > 0 ? 1 : -1; scrollAccum = 0 }
        } else {
            guard let ns = NSEvent(cgEvent: event), ns.type == .magnify else { return false }
            pinchAccum += ns.magnification
            if abs(pinchAccum) >= 0.18 { step = pinchAccum > 0 ? 1 : -1; pinchAccum = 0 }
            if ns.phase == .ended || ns.phase == .cancelled { pinchAccum = 0 }
        }
        guard step != 0 else { return true }
        guard Date().timeIntervalSince(lastZoom) > 0.25 else { return true }
        lastZoom = Date()
        let p = event.location
        DispatchQueue.main.async { [weak self] in self?.wm?.zoom(inward: step > 0, at: p) }
        return true
    }

    /// The press wasn't a gesture: hand the app its click after all.
    private func replayClick(button: Int, at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        let mb = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: mb) else { continue }
            e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            e.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}
