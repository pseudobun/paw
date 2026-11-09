import AppKit
import Carbon.HIToolbox
import PawCore

/// Type to find an element by its text; ↵ clicks the top match, Tab switches to labels.
final class SearchMode: Mode {
    let kind = Controller.Kind.search
    private unowned let controller: Controller
    private let target: Controller.Target
    private var elements: [Element] = []
    private var loaded = false
    private var closed = false
    private var query = ""
    private var results: [Int] = []
    private var selected = 0
    private var labelMode = false
    private var matcher = HintMatcher(labels: [])
    private var layers: [CALayer] = []
    private var labelLayers: [LabelLayer] = []
    private var island: CALayer?
    private var islandScreen: Int

    init(controller: Controller, target: Controller.Target) {
        self.controller = controller
        self.target = target
        islandScreen = controller.overlay.pointerScreen
        if let f = target.app.focusedWindowFrameHint, let i = controller.overlay.index(for: f) { islandScreen = i }
        render()
        controller.overlay.show()
        let options = controller.collectorOptions(.search)
        controller.collector.collect(pid: target.app.processIdentifier, bundleID: target.app.bundleIdentifier, options: options) {
            [weak self] r in
            guard let self, !closed else { return }
            elements = r.elements
            loaded = true
            if let f = r.windowFrame, let i = controller.overlay.index(for: f) { islandScreen = i }
            Log.ax.info("search \(self.target.name, privacy: .public): \(r.elements.count) elements in \(r.ms, format: .fixed(precision: 1)) ms")
            update()
        }
    }

    func handle(_ key: KeyTap.Key) -> Bool {
        guard key.down else { return true }
        switch Int(key.code) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let i = results[safe: selected] { controller.click(elements[i], kind: Clicker.kind(for: key.flags), key: nil) }
            return true
        case kVK_Tab:
            if !results.isEmpty {
                labelMode.toggle()
                matcher.reset()
                render()
            }
            return true
        case kVK_DownArrow:
            move(1)
            return true
        case kVK_UpArrow:
            move(-1)
            return true
        case kVK_Delete:
            if labelMode {
                if matcher.typed.isEmpty { labelMode = false } else { _ = matcher.backspace() }
                render()
            } else if key.command {
                query = ""
                update()
            } else if key.option {
                var q = query.trimmingCharacters(in: .whitespaces)
                while let last = q.last, last != " " { q.removeLast() }
                query = q
                update()
            } else if !query.isEmpty {
                query.removeLast()
                update()
            }
            return true
        default:
            break
        }
        if key.control, key.char == "n" { move(1); return true }
        if key.control, key.char == "p" { move(-1); return true }
        if key.command {
            if key.char == "v", let s = NSPasteboard.general.string(forType: .string) {
                query += s.replacingOccurrences(of: "\n", with: " ")
                update()
                return true
            }
            controller.dismiss()
            return false
        }
        if labelMode {
            guard let c = key.char else { return true }
            switch matcher.type(c) {
            case .matched(let i): controller.click(elements[results[i]], kind: Clicker.kind(for: key.flags), key: c)
            case .narrowed: render()
            case .noMatch: break
            }
            return true
        }
        let typed = key.text.filter { !$0.isNewline && $0.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f } }
        guard !typed.isEmpty else { return true }
        query += typed
        update()
        return true
    }

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + d + results.count) % results.count
        render()
    }

    /// Re-ranks after the query changed.
    private func update() {
        labelMode = false
        matcher.reset()
        selected = 0
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty || !loaded {
            results = []
        } else {
            var scored: [(Int, Int)] = []
            for (i, e) in elements.enumerated() {
                if let s = FuzzyMatcher.best(q, fields: e.searchFields) { scored.append((i, s)) }
            }
            scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            results = scored.prefix(max(1, controller.config.search.maxResults)).map(\.0)
        }
        matcher = HintMatcher(labels: LabelGenerator.labels(count: results.count, charset: controller.config.hint.charset))
        render()
    }

    private func render() {
        guard !closed else { return }
        let overlay = controller.overlay
        let style = controller.style
        let c = style.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in layers { l.removeFromSuperlayer() }
        layers = []
        labelLayers = []

        for (rank, i) in results.enumerated() {
            let e = elements[i]
            guard let si = overlay.index(for: e.frame) else { continue }
            let screen = overlay.screens[si]
            let isSelected = rank == selected
            if isSelected {
                let ring = CALayer()
                ring.borderColor = c.accent.cg
                ring.borderWidth = 1.5
                ring.cornerRadius = 5
                overlay.add(ring, axFrame: e.frame.insetBy(dx: -2, dy: -2), screen: si)
                layers.append(ring)
            }
            let code = matcher.labels[safe: rank] ?? ""
            let l = LabelLayer.make(code: code, style: style, scale: screen.scale)
            if isSelected { style.decorate(l, radius: style.a.labelRadius, fill: c.islandHi, border: c.accent) }
            let visible = !labelMode || code.hasPrefix(matcher.typed)
            l.update(style: style, typed: labelMode ? matcher.typed.count : 0)
            l.opacity = visible ? 1 : Float(style.a.unmatchedOpacity)
            let origin = ScreenGeometry.labelOrigin(for: e.frame, size: l.bounds.size, anchor: style.a.labelAnchor, bounds: screen.ax)
            overlay.add(l, axFrame: CGRect(origin: origin, size: l.bounds.size), screen: si)
            layers.append(l)
            labelLayers.append(l)
        }

        island?.removeFromSuperlayer()
        var segs: [Island.Segment] = []
        if let g = style.appGlyph(target.glyph) { segs.append(.init(text: g, gapAfter: 8)) }
        if query.isEmpty {
            segs.append(.init(text: style.text("search \(target.name)", c.dim)))
        } else {
            let color = loaded && results.isEmpty ? c.bad : (labelMode ? c.muted : c.fg)
            segs.append(.init(text: style.text(query, color, font: style.islandBold), gapAfter: 1))
        }
        if !labelMode { segs.append(.init(text: style.text("▏", c.accent))) }
        let trailing: NSAttributedString
        if !loaded { trailing = style.text("…", c.dim) }
        else if labelMode { trailing = style.text("labels", c.accent) }
        else if query.isEmpty { trailing = style.text("\(elements.count)", c.dim) }
        else if let i = results[safe: selected] {
            trailing = style.text("\(selected + 1)/\(results.count)  \(elements[i].roleDescription ?? "")", c.muted)
        } else { trailing = style.text("no match", c.bad) }
        let l = Island.make(segs, style: style, scale: overlay.screens[safe: islandScreen]?.scale ?? 2,
                            width: controller.config.search.width, trailing: trailing)
        overlay.addIsland(l, top: style.a.islandTop, screen: islandScreen)
        island = l
        CATransaction.commit()
        overlay.show()
    }

    func tearDown() {
        closed = true
        layers = []
    }
}

extension NSRunningApplication {
    /// Cheap guess of where the app is (its frontmost on-screen window), for placing islands
    /// before accessibility answers. Uses window-server info only; no permission needed.
    var focusedWindowFrameHint: CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier && (w[kCGWindowLayer as String] as? Int) == 0 {
            if let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) { return r }
        }
        return nil
    }
}
