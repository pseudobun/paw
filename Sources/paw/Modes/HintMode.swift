import AppKit
import Carbon.HIToolbox
import PawCore

/// Labels every clickable element; typing a label clicks it.
final class HintMode: Mode {
    let kind = Controller.Kind.hint
    private unowned let controller: Controller
    private let target: Controller.Target
    private var elements: [Element] = []
    private var layers: [LabelLayer] = []
    private var matcher: HintMatcher?
    private var island: CALayer?
    private var islandScreen = 0
    private var count = 0
    /// Keys typed before the labels were up, replayed once they are.
    private var pending: [KeyTap.Key] = []
    private var closed = false
    private let started = DispatchTime.now().uptimeNanoseconds

    init(controller: Controller, target: Controller.Target) {
        self.controller = controller
        self.target = target
        let options = controller.collectorOptions(.hint)
        controller.collector.collect(pid: target.app.processIdentifier, bundleID: target.app.bundleIdentifier, options: options) {
            [weak self] r in self?.present(r)
        }
    }

    private func present(_ r: Collector.Result) {
        guard !closed else { return }
        let overlay = controller.overlay
        let style = controller.style
        let placed = r.elements.compactMap { e in overlay.index(for: e.frame).map { (e, $0) } }
        guard !placed.isEmpty else {
            controller.dismiss()
            controller.notice("Nothing to click in \(target.name)", color: style.colors.bad)
            return
        }
        elements = placed.map(\.0)
        let codes = LabelGenerator.labels(count: elements.count, charset: controller.config.hint.charset)
        guard codes.count == elements.count else {
            controller.dismiss()
            controller.notice("hint.charset needs two or more keys", color: style.colors.bad)
            return
        }
        matcher = HintMatcher(labels: codes)
        count = elements.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, (e, si)) in placed.enumerated() {
            let screen = overlay.screens[si]
            let l = LabelLayer.make(code: codes[i], style: style, scale: screen.scale)
            let origin = ScreenGeometry.labelOrigin(for: e.frame, size: l.bounds.size, anchor: style.a.labelAnchor, bounds: screen.ax)
            overlay.add(l, axFrame: CGRect(origin: origin, size: l.bounds.size), screen: si)
            layers.append(l)
        }
        islandScreen = r.windowFrame.flatMap { overlay.index(for: $0) } ?? overlay.pointerScreen
        updateIsland(note: "\(count)")
        CATransaction.commit()
        overlay.show()

        let total = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        Log.ax.info("hint \(self.target.name, privacy: .public): \(self.count) labels, \(r.nodes) nodes, collect \(r.ms, format: .fixed(precision: 1)) ms, visible after \(total, format: .fixed(precision: 1)) ms")

        let keys = pending
        pending = []
        for k in keys where !closed { _ = handle(k) }
    }

    private func updateIsland(note: String, color: ARGB? = nil) {
        guard controller.style.a.appIsland else { return }
        island?.removeFromSuperlayer()
        let l = controller.modeIsland(target, mode: matcher.map { _ in "hint" } ?? "hint", note: note, noteColor: color, screen: islandScreen)
        controller.overlay.addIsland(l, top: controller.style.a.islandTop, screen: islandScreen)
        island = l
    }

    func handle(_ key: KeyTap.Key) -> Bool {
        guard key.down else { return true }
        guard var matcher else {
            pending.append(key)
            return true
        }
        if key.code == UInt16(kVK_Delete) {
            let visible = matcher.backspace()
            self.matcher = matcher
            refresh(Set(visible))
            return true
        }
        guard let c = key.char else { return true }
        // ⌘ with a key that isn't a label key belongs to the app (⌘Tab, ⌘W…).
        if key.command, !LabelGenerator.uniqueKeys(Array(controller.config.hint.charset)).contains(c) {
            controller.dismiss()
            return false
        }
        switch matcher.type(c) {
        case .narrowed(let hits):
            self.matcher = matcher
            refresh(Set(hits))
        case .matched(let i):
            self.matcher = matcher
            controller.click(elements[i], kind: Clicker.kind(for: key.flags), key: c)
        case .noMatch:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateIsland(note: "no label \(matcher.typed)\(c)", color: controller.style.colors.bad)
            CATransaction.commit()
        }
        return true
    }

    private func refresh(_ visible: Set<Int>) {
        guard let matcher else { return }
        let style = controller.style
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, l) in layers.enumerated() where visible.contains(i) {
            l.update(style: style, typed: matcher.typed.count)
        }
        updateIsland(note: matcher.typed.isEmpty ? "\(count)" : "\(visible.count)/\(count)")
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(style.a.fadeMs / 1000)
        for (i, l) in layers.enumerated() {
            l.opacity = visible.contains(i) ? 1 : Float(style.a.unmatchedOpacity)
        }
        CATransaction.commit()
    }

    func tearDown() {
        closed = true
        layers = []
        elements = []
    }
}
