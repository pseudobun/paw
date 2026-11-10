import AppKit
import PawCore
import QuartzCore
import ScreenCaptureKit

private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

/// The overview (hyper+tab, `paw overview`): on every display, its workspaces as cards in a
/// rail and the selected one large below, every window in its real place. Arrows move between
/// windows (and workspaces at the edges), typing filters by app or title, Return goes there,
/// ⇧Return brings the window here, Esc closes. Windows can be dragged onto a card (send to that
/// workspace) or next to another window (the same drop zones as dragging on the desktop).
final class OverviewController {
    private weak var wm: WindowManager?
    private(set) var isOpen = false
    private var panels: [OverviewPanel] = []
    private(set) var model: [WindowManager.OverviewWorkspace] = []
    /// The workspace each display's stage shows.
    private(set) var stageWorkspace: [Int: String] = [:]
    private(set) var selected: WindowID?
    private(set) var query = ""
    /// Pictures of windows, kept between openings (refreshed each time).
    private(set) var thumbnails: [WindowID: CGImage] = [:]
    /// The display the overview opened on: the search field and the hints stay there.
    private(set) var keyDisplay = 0
    /// The display whose stage the selection is on (arrows, Tab, Return).
    private(set) var activeDisplay = 0

    struct Drag {
        let id: WindowID
        let app: String
        var point: CGPoint // AX
        var display: Int?
        var target: DropKind?
    }

    enum DropKind: Equatable {
        case card(String)
        case stage(String, DropTarget?, CGRect?)
    }

    private(set) var drag: Drag?

    init(wm: WindowManager) { self.wm = wm }

    var style: Style { wm?.indicators.style ?? Style(PawConfig.Appearance()) }
    var config: PawConfig? { wm?.config }

    // MARK: Opening and closing

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard let wm, !isOpen else { return }
        isOpen = true
        wm.hud.hide()
        query = ""
        keyDisplay = wm.focusedDisplayIndex
        activeDisplay = keyDisplay
        reloadModel()
        stageWorkspace = [:]
        for ws in model where ws.visible { stageWorkspace[ws.display] = ws.name }
        selected = model.first(where: { $0.focused })?.windows.first(where: { $0.focused })?.id
            ?? model.first(where: { $0.focused })?.windows.first?.id
        panels.forEach { $0.orderOut(nil) }
        panels = (0..<wm.displayCount).compactMap { i in
            guard let frame = wm.displayFrame(i) else { return nil }
            let p = OverviewPanel(controller: self, display: i)
            p.setFrame(ScreenGeometry.cocoa(fromAX: frame, primaryHeight: primaryHeight), display: false)
            p.alphaValue = 0
            return p
        }
        NSApp.activate(ignoringOtherApps: true)
        for p in panels {
            p.orderFrontRegardless()
            p.view.needsDisplay = true
            p.view.animateIn()
        }
        let key = panels.first { $0.display == keyDisplay } ?? panels.first
        key?.makeKeyAndOrderFront(nil)
        key?.view.focusSearch()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for p in panels { p.animator().alphaValue = 1 }
        }
        captureThumbnails()
    }

    /// Closes, then runs `then` (go to a window, say).
    func close(then: (() -> Void)? = nil) {
        guard isOpen else { return }
        isOpen = false
        drag = nil
        let closing = panels
        panels = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            for p in closing { p.animator().alphaValue = 0 }
        }, completionHandler: {
            for p in closing { p.orderOut(nil) }
        })
        if let then {
            then()
        } else if let wm {
            // Nothing chosen: focus goes back to the window that had it.
            wm.focusWindow(wm.focusedWorkspaceFocus, warp: false)
        }
    }

    func reloadModel() {
        model = wm?.overviewModel() ?? []
    }

    func refresh() {
        reloadModel()
        if let s = selected, !model.contains(where: { $0.windows.contains { $0.id == s } }) { selected = nil }
        redraw()
    }

    func redraw() { panels.forEach { $0.view.needsDisplay = true } }

    /// Takes the key window back after paw moved windows around (which focuses apps).
    private func reclaimFocus() {
        NSApp.activate(ignoringOtherApps: true)
        let key = panels.first { $0.display == keyDisplay } ?? panels.first
        key?.makeKeyAndOrderFront(nil)
        key?.view.focusSearch()
    }

    // MARK: Queries for the views

    func workspaces(on display: Int) -> [WindowManager.OverviewWorkspace] { model.filter { $0.display == display } }

    func stage(on display: Int) -> WindowManager.OverviewWorkspace? {
        let list = workspaces(on: display)
        return list.first { $0.name == stageWorkspace[display] } ?? list.first { $0.visible } ?? list.first
    }

    func matches(_ w: WindowManager.OverviewWindow) -> Bool {
        query.isEmpty || WindowManager.matchScore(query, app: w.app, title: w.title) > 0
    }

    func matchCount(_ ws: WindowManager.OverviewWorkspace) -> Int {
        query.isEmpty ? 0 : ws.windows.filter(matches).count
    }

    // MARK: Actions

    func go(window id: WindowID) {
        close { [weak wm] in wm?.goTo(id) }
    }

    func go(workspace name: String) {
        close { [weak wm] in wm?.run([.workspace(.name(name))]) }
    }

    /// From a card click: the stage of that display shows it.
    func show(workspace name: String, on display: Int) {
        stageWorkspace[display] = name
        activeDisplay = display
        if let ws = model.first(where: { $0.name == name }) {
            selected = ws.windows.first(where: { $0.focused })?.id ?? ws.windows.first?.id
        }
        redraw()
    }

    func select(_ id: WindowID?) {
        guard selected != id else { return }
        selected = id
        if let id, let ws = model.first(where: { $0.windows.contains { $0.id == id } }) {
            stageWorkspace[ws.display] = ws.name
            activeDisplay = ws.display
        }
        redraw()
    }

    /// Arrow keys: the nearest window that way among the stages of every display (as they sit
    /// side by side); past the last one, the next workspace of that display.
    func move(_ dir: Direction) {
        // Every window shown on a stage, in global coordinates.
        var all: [(id: WindowID, display: Int, frame: CGRect)] = []
        for p in panels {
            guard let ws = stage(on: p.display), let origin = wm?.displayFrame(p.display)?.origin else { continue }
            let st = p.view.stageRect
            for w in ws.windows where w.isActive && matches(w) {
                all.append((w.id, p.display, OverviewLayout.place(w.frame, in: st).offsetBy(dx: origin.x, dy: origin.y)))
            }
        }
        // A window in a stack counts as its stack's top window.
        let selectedTop = selected.flatMap { id in
            model.flatMap(\.windows).first { $0.id == id }.map { w in w.isActive ? w.id : (w.stack.first { s in all.contains { $0.id == s } } ?? id) }
        }
        guard let cur = all.first(where: { $0.id == selectedTop }) else {
            if let first = all.first(where: { $0.display == activeDisplay }) ?? all.first { select(first.id) }
            else if dir.axis == .horizontal { cycleWorkspace(dir == .east ? 1 : -1) }
            return
        }
        let others = all.filter { $0.id != cur.id }
        if let i = OverviewLayout.neighbor(of: cur.frame, dir, among: others.map(\.frame)) {
            select(others[i].id)
        } else if dir.axis == .horizontal {
            activeDisplay = cur.display
            cycleWorkspace(dir == .east ? 1 : -1, entering: dir)
        } else {
            activeDisplay = cur.display
            stepWorkspace(dir == .south ? 1 : -1, entering: dir)
        }
    }

    /// ↑ / ↓ past the stage's edge: the previous / next workspace in number order, on whichever
    /// display it lives.
    func stepWorkspace(_ step: Int, entering dir: Direction) {
        guard let cur = stage(on: activeDisplay), let i = model.firstIndex(where: { $0.name == cur.name }),
              model.indices.contains(i + step) else { return }
        let next = model[i + step]
        activeDisplay = next.display
        stageWorkspace[next.display] = next.name
        let candidates = next.windows.filter { $0.isActive && matches($0) }
        selected = (dir == .south ? candidates.min { $0.frame.minY < $1.frame.minY } : candidates.max { $0.frame.maxY < $1.frame.maxY })?.id
        redraw()
    }

    func displayName(_ i: Int) -> String { wm?.displayName(i) ?? "" }

    /// Tab / ⇧Tab, and arrows past the edge: the next workspace of the active display.
    func cycleWorkspace(_ step: Int, entering dir: Direction? = nil) {
        let list = workspaces(on: activeDisplay)
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.name == stage(on: activeDisplay)?.name } ?? 0
        let next = list[(i + step + list.count) % list.count]
        stageWorkspace[activeDisplay] = next.name
        let candidates = next.windows.filter { $0.isActive && matches($0) }
        // Entering from the left lands on the leftmost window, and so on.
        let pick: WindowManager.OverviewWindow?
        switch dir {
        case .east?: pick = candidates.min { $0.frame.minX < $1.frame.minX }
        case .west?: pick = candidates.max { $0.frame.maxX < $1.frame.maxX }
        default: pick = candidates.first { $0.focused } ?? candidates.first
        }
        selected = pick?.id
        redraw()
    }

    func selectWorkspace(number n: Int) {
        let list = workspaces(on: activeDisplay)
        if let ws = list.first(where: { $0.label == "\(n)" }) ?? model.first(where: { $0.label == "\(n)" }) {
            show(workspace: ws.name, on: ws.display)
        }
    }

    /// The search field's text changed (typing, ⌥⌫, paste…).
    func queryChanged(_ text: String) {
        // A lone digit on an empty field picks a workspace instead.
        if query.isEmpty, text.count == 1, let n = Int(text), (1...9).contains(n) {
            panels.first { $0.display == keyDisplay }?.view.setSearchText("")
            selectWorkspace(number: n)
            return
        }
        query = text
        selectBestMatch()
    }

    func type(_ s: String) {
        query += s
        selectBestMatch()
    }

    func backspace() {
        guard !query.isEmpty else { return }
        query.removeLast()
        selectBestMatch()
    }

    func escape() {
        if !query.isEmpty {
            query = ""
            panels.first { $0.display == keyDisplay }?.view.setSearchText("")
            redraw()
        } else {
            close()
        }
    }

    private func selectBestMatch() {
        guard !query.isEmpty else { redraw(); return }
        let all = model.flatMap { ws in ws.windows.map { (ws, $0) } }
        let best = all.max { WindowManager.matchScore(query, app: $0.1.app, title: $0.1.title) < WindowManager.matchScore(query, app: $1.1.app, title: $1.1.title) }
        if let best, WindowManager.matchScore(query, app: best.1.app, title: best.1.title) > 0 {
            selected = best.1.id
            stageWorkspace[best.0.display] = best.0.name
            activeDisplay = best.0.display
        }
        redraw()
    }

    func confirm(bringHere: Bool) {
        if let id = selected {
            if bringHere, let wm, let here = model.first(where: { $0.visible && $0.display == wm.focusedDisplayIndex }) {
                close { [weak wm] in
                    wm?.sendWindow(id, to: here.name)
                    wm?.goTo(id)
                }
            } else {
                go(window: id)
            }
        } else if let ws = stage(on: activeDisplay) {
            go(workspace: ws.name)
        }
    }

    /// A region picked on a stage: close, and work there.
    func focusArea(_ ids: [WindowID], in name: String) {
        close { [weak wm] in wm?.focusArea(ids, in: name) }
    }

    func newWorkspace() {
        close { [weak wm] in _ = wm?.newWorkspaceFromOverview() }
    }

    // MARK: Dragging

    func beginDrag(_ id: WindowID, at p: CGPoint) {
        guard let w = model.flatMap(\.windows).first(where: { $0.id == id }) else { return }
        drag = Drag(id: id, app: w.app, point: p, display: nil, target: nil)
        selected = id
        updateDrag(p)
    }

    /// `p` in AX coordinates.
    func updateDrag(_ p: CGPoint) {
        guard var d = drag, let wm else { return }
        d.point = p
        d.display = panels.first { ScreenGeometry.ax(fromCocoa: $0.frame, primaryHeight: primaryHeight).contains(p) }?.display
        d.target = nil
        if let di = d.display, let view = panels.first(where: { $0.display == di })?.view {
            d.target = view.dropKind(at: p, dragging: d.id, wm: wm)
        }
        drag = d
        redraw()
    }

    func endDrag() {
        guard let d = drag, let wm else { drag = nil; return }
        drag = nil
        switch d.target {
        case .card(let name)?:
            if let from = model.first(where: { $0.windows.contains { $0.id == d.id } }), from.name != name {
                wm.sendWindow(d.id, to: name)
            }
        case .stage(let name, let target, _)?:
            wm.drop(d.id, on: target, in: wm.workspaceNamed(name))
        case nil:
            break
        }
        refresh()
        reclaimFocus()
        captureThumbnails()
    }

    // MARK: Pictures

    private var thumbnailsEnabled: Bool {
        switch config?.overview.thumbnails ?? "auto" {
        case "off": return false
        case "on": return CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
        default: return CGPreflightScreenCaptureAccess()
        }
    }

    private func captureThumbnails() {
        guard thumbnailsEnabled else { return }
        let ids = Set(model.flatMap { $0.windows.map(\.id) })
        Task { [weak self] in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            for w in content.windows where ids.contains(w.windowID) {
                let cfg = SCStreamConfiguration()
                let scale = min(1, 720 / max(1, w.frame.width))
                cfg.width = max(32, Int(w.frame.width * scale * 2))
                cfg.height = max(32, Int(w.frame.height * scale * 2))
                cfg.showsCursor = false
                cfg.ignoreShadowsSingleWindow = true
                let filter = SCContentFilter(desktopIndependentWindow: w)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { continue }
                let id = w.windowID
                await MainActor.run {
                    self?.thumbnails[id] = image
                    self?.redraw()
                }
            }
        }
    }
}

// MARK: - Panel

final class OverviewPanel: NSPanel {
    let display: Int
    let view: OverviewView

    init(controller: OverviewController, display: Int) {
        self.display = display
        view = OverviewView(controller: controller, display: display)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        view.autoresizingMask = [.width, .height]
        let root = NSView()
        root.focusRingType = .none
        root.addSubview(blur)
        root.addSubview(view)
        contentView = root
        blur.frame = root.bounds
        view.frame = root.bounds
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

final class OverviewView: NSView {
    private unowned let controller: OverviewController
    let display: Int
    private var hits: [(rect: CGRect, hit: Hit)] = []
    private var hovered: Hit?
    private var pressed: (hit: Hit, at: CGPoint)?
    /// A region being picked on the stage (drag on empty space, or ⇧-drag anywhere).
    private var band: (from: CGPoint, to: CGPoint)?
    private var trackingArea: NSTrackingArea?
    private var layoutCache: OverviewLayout?
    private var searchField: SearchField?
    /// The stage in this view's coordinates (top-left origin, like AX within the display).
    var stageRect: CGRect { (layoutCache ?? currentLayout()).stage }

    enum Hit: Equatable {
        case window(WindowID)
        case card(String)
        case newCard
        case search
    }

    init(controller: OverviewController, display: Int) {
        self.controller = controller
        self.display = display
        super.init(frame: .zero)
        wantsLayer = true
        focusRingType = .none
    }

    /// The real text field (native editing: ⌥←, ⌘←, ⌥⌫, ⌘A, paste…) on the display the
    /// overview opened on. Plain arrows, Return, Tab and Esc drive the overview instead.
    func focusSearch() {
        let f = searchField ?? {
            let f = SearchField(controller: controller)
            addSubview(f)
            searchField = f
            return f
        }()
        let l = currentLayout()
        f.frame = CGRect(x: l.search.minX + 34, y: l.search.minY + (l.search.height - 20) / 2, width: l.search.width - 48, height: 20)
        f.font = style.font
        f.textColor = style.colors.fg.ns
        f.placeholderAttributedString = NSAttributedString(string: "Type to find a window",
                                                           attributes: [.font: style.font, .foregroundColor: style.colors.dim.ns])
        window?.makeFirstResponder(f)
    }

    func setSearchText(_ s: String) { searchField?.stringValue = s }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func animateIn() {
        guard let l = layer else { return }
        let a = CABasicAnimation(keyPath: "transform.scale")
        a.fromValue = 1.03
        a.toValue = 1
        a.duration = 0.2
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        l.add(a, forKey: "in")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        trackingArea = a
    }

    private var style: Style { controller.style }
    private var isKey: Bool { controller.keyDisplay == display }

    // MARK: Geometry

    private func currentLayout() -> OverviewLayout {
        let list = controller.workspaces(on: display)
        let area = controller.stage(on: display)?.area ?? list.first?.area ?? CGRect(x: 0, y: 0, width: 16, height: 10)
        let screen = window?.screen ?? NSScreen.main
        let top = screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
        return OverviewLayout(bounds: bounds, top: top, cardCount: list.count + (isKey ? 1 : 0), aspect: area.width / max(1, area.height))
    }

    /// Where a dragged window would go if released at `p` (AX) over this display.
    func dropKind(at p: CGPoint, dragging id: WindowID, wm: WindowManager) -> OverviewController.DropKind? {
        guard let win = window else { return nil }
        let local = convert(win.convertPoint(fromScreen: ScreenGeometry.cocoa(fromAX: p, primaryHeight: primaryHeight)), from: nil)
        let l = layoutCache ?? currentLayout()
        let list = controller.workspaces(on: display)
        for (i, ws) in list.enumerated() where l.cards.indices.contains(i) && l.cards[i].insetBy(dx: -6, dy: -6).contains(local) {
            return .card(ws.name)
        }
        guard let ws = controller.stage(on: display), l.stage.insetBy(dx: -40, dy: -40).contains(local) else { return nil }
        let ax = OverviewLayout.unplace(local, from: l.stage, to: ws.area)
        let workspace = wm.workspaceNamed(ws.name)
        let copy = workspace.clone()
        let stack = NSEvent.modifierFlags.contains(.option)
        let target = DropZones.target(at: ax, in: copy, area: ws.area, gap: wm.config.layout.gap, dragging: id, stack: stack, full: true)
        var preview: CGRect?
        if let target, let f = DropZones.preview(target, in: copy, area: ws.area, gap: wm.config.layout.gap, dragging: id, full: true) {
            preview = OverviewLayout.place(ax: f, area: ws.area, in: l.stage)
        }
        if target == nil, !workspace.contains(id) {
            // Another workspace: dropped anywhere on its stage, it joins it.
            return .stage(ws.name, nil, l.stage.insetBy(dx: l.stage.width * 0.3, dy: l.stage.height * 0.3))
        }
        return .stage(ws.name, target, preview)
    }

    // MARK: Drawing

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let c = style.colors
        let l = currentLayout()
        layoutCache = l
        hits = []
        c.island.withAlpha(0.55).ns.setFill()
        bounds.fill()

        drawSearch(l, ctx)
        drawRail(l, ctx)
        if let ws = controller.stage(on: display) { drawStage(ws, l, ctx) }
        drawFooter(l)
        drawDrag(l, ctx)
        drawBand(ctx)
    }

    private func drawSearch(_ l: OverviewLayout, _ ctx: CGContext) {
        let c = style.colors
        // Which display this is, top left.
        draw(controller.displayName(display), in: CGRect(x: OverviewLayout.margin, y: l.search.minY, width: max(0, l.search.minX - OverviewLayout.margin - 16),
                                                          height: l.search.height),
             font: style.bold, color: controller.activeDisplay == display ? c.fg : c.muted, centerY: true)
        guard isKey else { return }
        let r = l.search
        let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        c.islandHi.withAlpha(0.95).ns.setFill()
        path.fill()
        (controller.query.isEmpty ? c.border : c.accent.withAlpha(0.7)).ns.setStroke()
        path.lineWidth = 1
        path.stroke()
        draw("⌕", in: CGRect(x: r.minX + 14, y: r.minY, width: 18, height: r.height), font: style.bold, color: c.muted, centerY: true)
        hits.append((r, .search))
    }

    private func drawRail(_ l: OverviewLayout, _ ctx: CGContext) {
        let c = style.colors
        let list = controller.workspaces(on: display)
        let stageName = controller.stage(on: display)?.name
        for (i, ws) in list.enumerated() where l.cards.indices.contains(i) {
            let r = l.cards[i]
            let isStage = ws.name == stageName
            let dropHere = controller.drag?.target == .card(ws.name) && controller.drag?.display == display
            let hover = hovered == .card(ws.name)
            // Label above the card: number, and a dot when it is on screen.
            let labelColor = ws.focused ? c.accent : (isStage ? c.fg : c.muted)
            draw(ws.label + (ws.visible ? "  ●" : ""), in: CGRect(x: r.minX + 2, y: r.minY - 18, width: r.width, height: 16),
                 font: style.bold, color: labelColor)
            let n = controller.matchCount(ws)
            if n > 0 {
                draw("\(n)", in: CGRect(x: r.maxX - 40, y: r.minY - 18, width: 38, height: 16), font: style.bold, color: c.accent, align: .right)
            }
            let path = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
            (dropHere ? c.accent.withAlpha(0.22) : c.islandHi.withAlpha(hover ? 1 : 0.85)).ns.setFill()
            path.fill()
            ctx.saveGState()
            path.addClip()
            let inner = r.insetBy(dx: 4, dy: 4)
            for w in ws.windows where w.isActive {
                let f = OverviewLayout.place(w.frame, in: inner).insetBy(dx: 1.5, dy: 1.5)
                guard f.width > 2, f.height > 2 else { continue }
                ctx.setAlpha(controller.matches(w) ? 1 : 0.25)
                drawMini(w, in: f)
                hits.append((f, .window(w.id)))
            }
            ctx.setAlpha(1)
            if let cam = ws.camera {
                let cr = OverviewLayout.place(cam, in: inner).insetBy(dx: -1, dy: -1)
                let cp = NSBezierPath(roundedRect: cr, xRadius: 3, yRadius: 3)
                cp.lineWidth = 1
                c.accent.withAlpha(0.8).ns.setStroke()
                cp.stroke()
            }
            ctx.restoreGState()
            path.lineWidth = isStage || dropHere ? 2 : 1
            (dropHere || isStage ? c.accent : (ws.visible ? c.fg.withAlpha(0.35) : c.border)).ns.setStroke()
            path.stroke()
            hits.append((r, .card(ws.name)))
        }
        if isKey, l.cards.count > list.count, let r = l.cards.last {
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            path.setLineDash([5, 4], count: 2, phase: 0)
            path.lineWidth = 1.5
            (hovered == .newCard ? c.accent : c.dim).ns.setStroke()
            path.stroke()
            draw("+", in: r, font: Style.font(style.a.font, size: 22, weight: "bold"), color: hovered == .newCard ? c.accent : c.dim,
                 align: .center, centerY: true)
            hits.append((r, .newCard))
        }
    }

    private func drawMini(_ w: WindowManager.OverviewWindow, in f: CGRect) {
        let c = style.colors
        let color = AppColors.shared.color(for: w.app, icons: controller.config?.icons ?? PawConfig.Icons()) ?? c.muted
        let p = NSBezierPath(roundedRect: f, xRadius: 3, yRadius: 3)
        if let img = controller.thumbnails[w.id] {
            NSGraphicsContext.saveGraphicsState()
            p.addClip()
            drawImage(img, fill: f)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            color.withAlpha(0.35).ns.setFill()
            p.fill()
            let side = min(22, f.width * 0.6, f.height * 0.6)
            if side >= 9 { drawIcon(w.app, in: CGRect(x: f.midX - side / 2, y: f.midY - side / 2, width: side, height: side)) }
        }
        (w.id == controller.selected ? c.accent : color.withAlpha(0.7)).ns.setStroke()
        p.lineWidth = w.id == controller.selected ? 1.5 : 0.75
        p.stroke()
    }

    private func drawStage(_ ws: WindowManager.OverviewWorkspace, _ l: OverviewLayout, _ ctx: CGContext) {
        let c = style.colors
        let stage = l.stage
        let bg = NSBezierPath(roundedRect: stage.insetBy(dx: -10, dy: -10), xRadius: 16, yRadius: 16)
        c.island.withAlpha(0.35).ns.setFill()
        bg.fill()
        if controller.activeDisplay == display {
            c.accent.withAlpha(0.35).ns.setStroke()
            bg.lineWidth = 1
            bg.stroke()
        }
        // Header: number, layout, how many windows, whether it's on screen.
        let n = Set(ws.windows.map(\.id)).count
        let head = NSMutableAttributedString(attributedString: style.text("Workspace \(ws.label)", ws.focused ? c.accent : c.fg, font: style.bold))
        head.append(style.text("   \(ws.layout.rawValue) · \(n) window\(n == 1 ? "" : "s")" + (ws.visible ? " · on screen" : ""), c.muted))
        drawAttributed(head, in: CGRect(x: stage.minX - 8, y: stage.minY - 40, width: stage.width, height: 18), align: .left, centerY: false)
        if ws.windows.isEmpty {
            draw("Empty", in: stage, font: Style.font(style.a.font, size: 16, weight: "medium"),
                 color: c.dim, align: .center, centerY: true)
            return
        }
        // Tiled first, floating on top; in a stack only the window on top, with its stack.
        let order = ws.windows.filter { !$0.floating && $0.isActive } + ws.windows.filter(\.floating)
        for w in order {
            let f = OverviewLayout.place(w.frame, in: stage).insetBy(dx: 4, dy: 4)
            guard f.width > 8, f.height > 8 else { continue }
            let match = controller.matches(w) || w.stack.contains(where: { id in ws.windows.first { $0.id == id }.map(controller.matches) ?? false })
            // Outside the zoom / off the canvas's screen: there, but quieter.
            ctx.setAlpha((match ? 1 : 0.25) * (w.inCamera ? 1 : 0.55))
            drawWindow(w, ws: ws, in: f, ctx)
            ctx.setAlpha(1)
        }
        if let cam = ws.camera {
            let r = OverviewLayout.place(cam, in: stage).insetBy(dx: -2, dy: -2)
            let p = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
            p.setLineDash([8, 5], count: 2, phase: 0)
            p.lineWidth = 2
            c.accent.withAlpha(0.8).ns.setStroke()
            p.stroke()
            let tag = style.text(" on screen ", c.island, font: style.bold)
            let tw = tag.size().width + 8
            let tr = CGRect(x: r.minX + 12, y: r.minY - 9, width: tw, height: 18)
            c.accent.ns.setFill()
            NSBezierPath(roundedRect: tr, xRadius: 9, yRadius: 9).fill()
            drawAttributed(tag, in: tr, align: .center, centerY: true)
        }
    }

    private func drawWindow(_ w: WindowManager.OverviewWindow, ws: WindowManager.OverviewWorkspace, in f: CGRect, _ ctx: CGContext) {
        let c = style.colors
        let brand = AppColors.shared.color(for: w.app, icons: controller.config?.icons ?? PawConfig.Icons()) ?? c.muted
        let radius: CGFloat = 12
        // A stack: cards fanned out behind the top one.
        if w.stack.count > 1 {
            for k in stride(from: min(2, w.stack.count - 1), through: 1, by: -1) {
                let off = CGFloat(k) * 5
                let back = NSBezierPath(roundedRect: f.offsetBy(dx: off, dy: off).insetBy(dx: off / 2, dy: off / 2), xRadius: radius, yRadius: radius)
                c.islandHi.withAlpha(0.9).ns.setFill()
                back.fill()
                c.border.ns.setStroke()
                back.stroke()
            }
        }
        if w.floating {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: CGColor(gray: 0, alpha: 0.5))
        }
        let path = NSBezierPath(roundedRect: f, xRadius: radius, yRadius: radius)
        c.islandHi.ns.setFill()
        path.fill()
        if w.floating { ctx.restoreGState() }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let img = controller.thumbnails[w.id] {
            drawImage(img, fill: f)
            // A strip at the bottom for the label.
            let strip = CGRect(x: f.minX, y: f.maxY - 34, width: f.width, height: 34)
            NSColor.black.withAlphaComponent(0.55).setFill()
            strip.fill()
            let icon: CGFloat = 20
            drawIcon(w.app, in: CGRect(x: strip.minX + 10, y: strip.midY - icon / 2, width: icon, height: icon))
            drawLabel(w, in: CGRect(x: strip.minX + 38, y: strip.minY, width: strip.width - 48, height: strip.height), oneLine: true)
        } else {
            brand.withAlpha(0.16).ns.setFill()
            f.fill()
            let side = min(72, f.width * 0.35, f.height * 0.35)
            let iconRect = CGRect(x: f.midX - side / 2, y: f.midY - side / 2 - 14, width: side, height: side)
            drawIcon(w.app, in: iconRect)
            drawLabel(w, in: CGRect(x: f.minX + 12, y: iconRect.maxY + 8, width: f.width - 24, height: 38), oneLine: false)
        }
        NSGraphicsContext.restoreGraphicsState()
        // Stack: badge and one icon per window, each clickable.
        if w.stack.count > 1 {
            let s: CGFloat = 22, gap: CGFloat = 4
            var x = f.minX + 10
            let y = f.minY + 10
            let pill = CGRect(x: x - 4, y: y - 4, width: CGFloat(w.stack.count) * (s + gap) - gap + 8, height: s + 8)
            NSColor.black.withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            for id in w.stack {
                guard let other = ws.windows.first(where: { $0.id == id }) else { continue }
                let r = CGRect(x: x, y: y, width: s, height: s)
                drawIcon(other.app, in: r)
                if id == controller.selected || hovered == .window(id), id != w.id {
                    c.accent.ns.setStroke()
                    NSBezierPath(roundedRect: r.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6).stroke()
                }
                hits.append((r, .window(id)))
                x += s + gap
            }
        }
        let selected = w.id == controller.selected || w.stack.contains(where: { $0 == controller.selected })
        let hover = hovered == .window(w.id)
        path.lineWidth = selected ? 3 : (hover ? 1.5 : 1)
        (selected ? c.accent : (hover ? c.fg.withAlpha(0.6) : c.border)).ns.setStroke()
        path.stroke()
        hits.append((f, .window(w.id)))
    }

    private func drawLabel(_ w: WindowManager.OverviewWindow, in r: CGRect, oneLine: Bool) {
        let c = style.colors
        let title = w.title.isEmpty || w.title == w.app ? "" : w.title
        if oneLine {
            let s = NSMutableAttributedString(attributedString: style.text(w.app, c.fg, font: style.bold))
            if !title.isEmpty { s.append(style.text("  " + title, c.muted)) }
            drawAttributed(s, in: r, align: .left, centerY: true)
        } else {
            draw(w.app, in: CGRect(x: r.minX, y: r.minY, width: r.width, height: 18), font: style.bold, color: c.fg, align: .center)
            if !title.isEmpty {
                draw(title, in: CGRect(x: r.minX, y: r.minY + 19, width: r.width, height: 18), font: style.font, color: c.muted, align: .center)
            }
        }
    }

    private func drawFooter(_ l: OverviewLayout) {
        guard isKey else { return }
        let hint = "←↑→↓ move   ⇥ workspace   ⏎ go   ⇧⏎ bring here   drag to move (⌥ stacks)   drag empty space or ⇧-drag: work in that area   esc close"
        draw(hint, in: l.footer, font: style.font, color: style.colors.dim, align: .center)
    }

    private var bandRect: CGRect? { band.flatMap(Self.rect) }

    private static func rect(_ b: (from: CGPoint, to: CGPoint)) -> CGRect? {
        let r = CGRect(x: min(b.from.x, b.to.x), y: min(b.from.y, b.to.y), width: abs(b.to.x - b.from.x), height: abs(b.to.y - b.from.y))
        return r.width > 3 || r.height > 3 ? r : nil
    }

    /// Tiled windows of the stage the band touches.
    private func bandWindows(_ b: (from: CGPoint, to: CGPoint)) -> [WindowID] {
        guard let r = Self.rect(b), let ws = controller.stage(on: display) else { return [] }
        let stage = (layoutCache ?? currentLayout()).stage
        return ws.windows.filter { !$0.floating && $0.isActive && OverviewLayout.place($0.frame, in: stage).intersects(r) }.map(\.id)
    }

    private func drawBand(_ ctx: CGContext) {
        guard let r = bandRect, let b = band else { return }
        let c = style.colors
        let stage = (layoutCache ?? currentLayout()).stage
        if let ws = controller.stage(on: display) {
            let ids = Set(bandWindows(b))
            for w in ws.windows where ids.contains(w.id) {
                let f = OverviewLayout.place(w.frame, in: stage).insetBy(dx: 4, dy: 4)
                c.accent.withAlpha(0.14).ns.setFill()
                NSBezierPath(roundedRect: f, xRadius: 12, yRadius: 12).fill()
            }
        }
        let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        c.accent.withAlpha(0.1).ns.setFill()
        p.fill()
        p.setLineDash([6, 4], count: 2, phase: 0)
        p.lineWidth = 1.5
        c.accent.ns.setStroke()
        p.stroke()
    }

    private func drawDrag(_ l: OverviewLayout, _ ctx: CGContext) {
        guard let d = controller.drag, d.display == display, let win = window else { return }
        let c = style.colors
        if case .stage(_, _, let preview?)? = d.target {
            let p = NSBezierPath(roundedRect: preview.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12)
            c.accent.withAlpha(0.18).ns.setFill()
            p.fill()
            c.accent.withAlpha(0.9).ns.setStroke()
            p.lineWidth = 2
            p.stroke()
        }
        let local = convert(win.convertPoint(fromScreen: ScreenGeometry.cocoa(fromAX: d.point, primaryHeight: primaryHeight)), from: nil)
        let s: CGFloat = 48
        let r = CGRect(x: local.x - s / 2, y: local.y - s / 2, width: s, height: s)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 12, color: CGColor(gray: 0, alpha: 0.6))
        drawIcon(d.app, in: r)
        ctx.restoreGState()
    }

    // MARK: Drawing helpers

    private func drawIcon(_ app: String, in r: CGRect) {
        let scale = window?.backingScaleFactor ?? 2
        guard let img = AppColors.shared.image(for: app, side: Int((r.width * scale).rounded())) else {
            let c = style.colors
            draw(String(app.prefix(1)).uppercased(), in: r, font: Style.font(style.a.font, size: r.height * 0.6, weight: "bold"),
                 color: c.fg, align: .center, centerY: true)
            return
        }
        NSImage(cgImage: img, size: r.size).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// Aspect-fill, top aligned (a window's top matters most).
    private func drawImage(_ img: CGImage, fill r: CGRect) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        guard iw > 0, ih > 0 else { return }
        let k = max(r.width / iw, r.height / ih)
        let w = iw * k, h = ih * k
        let dest = CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: h)
        NSImage(cgImage: img, size: dest.size).draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func draw(_ s: String, in r: CGRect, font: NSFont, color: ARGB, align: NSTextAlignment = .left, centerY: Bool = false) {
        drawAttributed(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color.ns]), in: r, align: align, centerY: centerY)
    }

    private func drawAttributed(_ s: NSAttributedString, in r: CGRect, align: NSTextAlignment, centerY: Bool) {
        let p = NSMutableParagraphStyle()
        p.alignment = align
        p.lineBreakMode = .byTruncatingTail
        let m = NSMutableAttributedString(attributedString: s)
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
        var rect = r
        if centerY {
            let h = m.boundingRect(with: CGSize(width: r.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
            let lineH = min(h, (m.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { ceil($0.ascender - $0.descender + $0.leading) } ?? h)
            rect = CGRect(x: r.minX, y: r.midY - lineH / 2, width: r.width, height: lineH + 2)
        }
        m.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: Mouse

    private func hit(at p: CGPoint) -> Hit? {
        // Later entries were drawn on top.
        hits.last { $0.rect.contains(p) }?.hit
    }

    override func mouseMoved(with event: NSEvent) {
        let h = hit(at: convert(event.locationInWindow, from: nil))
        guard h != hovered else { return }
        hovered = h
        // Pointing at a window selects it, so the mouse and the arrows share one selection.
        if case .window(let id)? = h { controller.select(id) } else { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let onStage = (layoutCache ?? currentLayout()).stage.contains(p)
        let h = hit(at: p)
        if onStage, h == nil || event.modifierFlags.contains(.shift) {
            if case .window? = h, !event.modifierFlags.contains(.shift) {} else {
                band = (p, p)
                pressed = nil
                return
            }
        }
        guard let h else { pressed = nil; return }
        if event.clickCount == 2, case .card(let name) = h {
            controller.go(workspace: name)
            return
        }
        pressed = (h, p)
    }

    override func mouseDragged(with event: NSEvent) {
        if let b = band {
            band = (b.from, convert(event.locationInWindow, from: nil))
            needsDisplay = true
            return
        }
        let ax = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primaryHeight)
        if controller.drag != nil {
            controller.updateDrag(ax)
            return
        }
        guard let pr = pressed, case .window(let id) = pr.hit else { return }
        let p = convert(event.locationInWindow, from: nil)
        if hypot(p.x - pr.at.x, p.y - pr.at.y) > 5 { controller.beginDrag(id, at: ax) }
    }

    override func mouseUp(with event: NSEvent) {
        if let b = band {
            band = nil
            needsDisplay = true
            let ids = bandWindows(b)
            if let ws = controller.stage(on: display), !ids.isEmpty { controller.focusArea(ids, in: ws.name) }
            return
        }
        if controller.drag != nil {
            controller.endDrag()
            pressed = nil
            return
        }
        guard let pr = pressed else { return }
        pressed = nil
        switch pr.hit {
        case .window(let id): controller.go(window: id)
        case .card(let name): controller.show(workspace: name, on: display)
        case .newCard: controller.newWorkspace()
        case .search: focusSearch()
        }
    }

    override func rightMouseDown(with event: NSEvent) { controller.close() }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: controller.escape()
        case 36, 76: controller.confirm(bringHere: shift)
        case 51: controller.backspace()
        case 48: controller.cycleWorkspace(shift ? -1 : 1)
        case 123: controller.move(.west)
        case 124: controller.move(.east)
        case 125: controller.move(.south)
        case 126: controller.move(.north)
        default:
            guard !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control),
                  let chars = event.characters, !chars.isEmpty else { return }
            if controller.query.isEmpty, let n = Int(chars), (1...9).contains(n) {
                controller.selectWorkspace(number: n)
            } else if chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                controller.type(chars)
            }
        }
    }
}

// MARK: - Search field

/// The overview's search: a borderless text field with the system's editing, whose plain
/// arrows, Return, Tab and Esc go to the overview.
final class SearchField: NSTextField, NSTextFieldDelegate {
    private unowned let controller: OverviewController

    init(controller: OverviewController) {
        self.controller = controller
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        cell?.isScrollable = true
        cell?.wraps = false
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func controlTextDidChange(_ obj: Notification) {
        controller.queryChanged(stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        switch sel {
        case #selector(NSResponder.moveLeft(_:)): controller.move(.west)
        case #selector(NSResponder.moveRight(_:)): controller.move(.east)
        case #selector(NSResponder.moveUp(_:)): controller.move(.north)
        case #selector(NSResponder.moveDown(_:)): controller.move(.south)
        case #selector(NSResponder.insertNewline(_:)): controller.confirm(bringHere: shift)
        case #selector(NSResponder.insertTab(_:)): controller.cycleWorkspace(1)
        case #selector(NSResponder.insertBacktab(_:)): controller.cycleWorkspace(-1)
        case #selector(NSResponder.cancelOperation(_:)): controller.escape()
        default: return false
        }
        return true
    }
}
