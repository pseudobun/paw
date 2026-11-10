import AppKit
import PawCore

/// The window manager: tracks windows of regular apps, keeps them in workspaces (virtual, like
/// AeroSpace: a hidden workspace's windows wait in a screen corner), tiles them, and runs commands.
final class WindowManager {
    struct Display {
        let id: CGDirectDisplayID
        /// "DELL U2717D", "Built-in Retina Display"…
        let name: String
        let builtin: Bool
        /// AX coordinates (top-left origin).
        let frame: CGRect
        let area: CGRect
        var workspace: String
    }

    let settings: Settings
    let tracker = WindowTracker()
    let animator = Animator()
    let hotkeys = Hotkeys()
    let indicators: IndicatorController
    private(set) var windows: [WindowID: Window] = [:]
    private var workspaces: [String: Workspace] = [:]
    private(set) var displays: [Display] = []
    private var focusedDisplay = 0
    private var lastWorkspace: String?
    private var ignoreFocusUntil = Date.distantPast
    private var suppressMoves: [WindowID: Date] = [:]
    private var dragTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var windowsHookWork: DispatchWorkItem?
    private var displaysWork: DispatchWorkItem?
    /// The `setups` entry matching the connected displays; nil uses `workspaces`.
    private(set) var activeSetup: String?
    private var setupChanged = false
    /// Set by `initiate <setup>`: that setup stays until the displays change.
    private var forcedSetup: String?
    private var lastDisplayIDs: [String] = []
    /// Workspaces made with `workspace new` on a display that has pinned workspaces: they belong
    /// to that display and are numbered after its other workspaces (yabai's space order).
    private var extraPins: [String: CGDirectDisplayID] = [:]
    private var extraSeq = 0
    /// When paw last switched a display's workspace itself.
    private var lastSwitch = Date.distantPast
    /// The workspace presets in effect: the active setup's, else `workspaces`.
    var presets: [String: WorkspacePreset] { activeSetup.flatMap { config.setups[$0]?.workspaces } ?? config.workspaces }
    /// The workspace each display showed last, so one plugged in again gets its workspace back.
    private var workspaceByDisplay: [CGDirectDisplayID: String] = [:]
    private(set) var mode: String?
    private let modePanel = TitlePanel()
    private var lastWindowsSignature = ""
    private var mouseMonitor: Any?
    private var lastHover = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var pruneTimer: Timer?

    init(settings: Settings) {
        self.settings = settings
        indicators = IndicatorController(settings: settings)
    }

    var config: PawConfig { settings.config }

    // MARK: - Lifecycle

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElement.systemWide, 0.5)
        animator.settings = { [unowned self] in config.animation }
        animator.onFinish = { [weak self] in self?.updateIndicators() }
        tracker.onEvent = { [weak self] in self?.handle($0) }
        hotkeys.run = { [weak self] in self?.run($0) }
        indicators.onFocus = { [weak self] id in self?.focusWindow(id, warp: false) }
        configChanged()
        if !hotkeys.start() { Log.app.error("key bindings: event tap not allowed (Accessibility)") }

        rebuildDisplays()
        let state = StateFile.load()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            adopt(app, state: state)
        }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Give the app a moment to make its first window.
            // Some (Brave) make it after a window-created notification could reach paw; look again.
            for delay in [0.4, 1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.adopt(app, state: nil) }
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.appTerminated(app.processIdentifier)
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Menu bar apps (Cryptomator) start as accessories and turn regular when they show a
            // window; paw skipped them then, so take them on the first time they come forward.
            if let self, app.activationPolicy == .regular, !self.tracker.isObserving(app.processIdentifier) {
                self.adopt(app, state: nil)
            }
            self?.pruneDead()
            self?.syncFocus(app.processIdentifier)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.scheduleDisplaysChanged()
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleDisplaysChanged()
        })
        // Catches windows that vanish without any notification (see pruneDead).
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pruneDead() }
        layoutAll(animated: false)
        if setupChanged { applySetup() }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { syncFocus(pid, force: true) }
        Log.app.info("managing \(self.windows.count) windows on \(self.displays.count) displays")
    }

    func configChanged() {
        hotkeys.set(config.bindings, modes: config.modes)
        if let m = mode, config.modes[m] == nil { setMode(nil) }
        for p in hotkeys.problems { Log.app.warning("bindings: \(p, privacy: .public)") }
        indicators.configChanged()
        updateFocusFollowsMouse()
        if !displays.isEmpty {
            rebuildDisplays()
            layoutAll(animated: true)
            if setupChanged { applySetup() }
        }
    }

    /// Puts every hidden window back on screen (paw quitting must not lose windows).
    func restoreAll() {
        guard let d = displays.first else { return }
        var offset: CGFloat = 0
        for w in windows.values where w.isHidden {
            let size = CGSize(width: min(w.frame.width, d.area.width * 0.8), height: min(w.frame.height, d.area.height * 0.8))
            w.setFrame(CGRect(origin: CGPoint(x: d.area.minX + 40 + offset, y: d.area.minY + 40 + offset), size: size))
            w.isHidden = false
            offset = (offset + 30).truncatingRemainder(dividingBy: 300)
        }
        StateFile.clear()
    }

    // MARK: - Displays and workspaces

    static func axFrame(_ r: CGRect) -> CGRect {
        ScreenGeometry.axFrame(ofScreen: r, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// Screen padding widened so a stack indicator outside its window fits between the window
    /// and the screen edge, with `indicator.offsetX` on both sides of it.
    private func indicatorPadding(_ p: Padding) -> Padding {
        let i = config.indicator
        let room = i.width + 2 * i.offsetX
        var p = p
        if [.auto, .left].contains(i.side) { p.left = max(p.left, room) }
        if [.auto, .right].contains(i.side) { p.right = max(p.right, room) }
        return p
    }

    /// Displays come and go in bursts of notifications; act once they settle.
    /// macOS brings displays up one after another (a dock's two monitors ~2 s apart): wait until
    /// they have settled, so windows move once, for the final setup, not once per display.
    /// Unplugging is staggered the same way.
    private func scheduleDisplaysChanged() {
        displaysWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.displaysChanged() }
        displaysWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// A display was plugged in or out, or rearranged: give every display a workspace, park the
    /// windows of workspaces no longer shown (again, as the free corners moved), pick up windows
    /// macOS moved around, and retile everything.
    private func displaysChanged() {
        let before = displays.map { "\($0.id)@\($0.frame)" }
        rebuildDisplays()
        let after = displays.map { "\($0.id)@\($0.frame)" }
        Log.app.info("displays changed: \(after.joined(separator: ", "), privacy: .public)")
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { adopt(app, state: nil) }
        let visible = Set(displays.map(\.workspace))
        for (name, ws) in workspaces where !visible.contains(name) {
            for id in ws.allWindows { if let w = windows[id] { _ = w.readFrame(); hide(w, from: ws) } }
        }
        // Shown windows go back on their tiles even if macOS moved them; floating ones only when
        // they ended up off every display.
        for d in displays {
            let ws = workspace(d.workspace)
            for id in ws.allWindows {
                guard let w = windows[id] else { continue }
                if !ws.isFloating(id) { w.isHidden = true; continue }
                if let f = w.readFrame(), !displays.contains(where: { $0.frame.intersects(f.insetBy(dx: 20, dy: 20)) }) {
                    w.floatFrame = nil
                    w.isHidden = true
                }
            }
        }
        layoutAll(animated: false)
        if setupChanged { applySetup() }
        if before != after {
            runHook(config.hooks.workspaceChanged, ["PAW_WORKSPACE": focusedWorkspace.name, "PAW_PREV_WORKSPACE": focusedWorkspace.name])
            runHook(config.hooks.displaysChanged, ["PAW_DISPLAYS": "\(displays.count)"])
        }
        scheduleSave()
    }

    private func rebuildDisplays() {
        let old = displays
        for d in old { workspaceByDisplay[d.id] = d.workspace }
        let l = config.layout
        var used = Set<String>()
        displays = NSScreen.screens.enumerated().map { i, s in
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGDirectDisplayID(i)
            let frame = Self.axFrame(s.frame)
            let area = TreeLayout.area(screen: frame, visible: Self.axFrame(s.visibleFrame), barTop: l.barTop, barBottom: l.barBottom,
                                       padding: indicatorPadding(l.padding))
            var ws = old.first { $0.id == id }?.workspace ?? workspaceByDisplay[id] ?? ""
            if used.contains(ws) { ws = "" }
            if !ws.isEmpty { used.insert(ws) }
            return Display(id: id, name: s.localizedName, builtin: CGDisplayIsBuiltin(id) != 0, frame: frame, area: area, workspace: ws)
        }
        let displaysNow = displays.map { "\($0.id)" }
        if !lastDisplayIDs.isEmpty, displaysNow != lastDisplayIDs { forcedSetup = nil }
        lastDisplayIDs = displaysNow
        let match = forcedSetup.flatMap { n in config.setups[n].map { (name: n, setup: $0) } }
            ?? config.setup(for: displays.map { (name: $0.name, builtin: $0.builtin) })
        if match?.name != activeSetup {
            activeSetup = match?.name
            setupChanged = true
            // A new arrangement: every display gets its pinned workspace again.
            used = []
            for i in displays.indices { displays[i].workspace = "" }
            Log.app.info("setup: \(match?.name ?? "default", privacy: .public)")
        }
        for n in 1...max(1, l.workspaces) { _ = workspace("\(n)") }
        for name in presets.keys { _ = workspace(name) }
        for i in displays.indices where displays[i].workspace.isEmpty {
            let preset = presets.keys.sorted(by: Self.nameOrder).first { displayIndex(for: presets[$0]?.display) == i && !used.contains($0) }
            let name = preset ?? orderedNames.first { !used.contains($0) } ?? "\(displays.count + i)"
            displays[i].workspace = name
            used.insert(name)
        }
        focusedDisplay = min(focusedDisplay, max(0, displays.count - 1))
    }

    func displayIndex(for spec: String?) -> Int? {
        guard let spec else { return nil }
        switch spec.lowercased() {
        case "main", "primary": return 0
        case "secondary": return displays.count > 1 ? 1 : nil
        case "builtin", "internal", "laptop": return displays.firstIndex { $0.builtin }
        case "external": return displays.firstIndex { !$0.builtin }
        default:
            if let n = Int(spec) { return displays.indices.contains(n - 1) ? n - 1 : nil }
            // A display's name, or part of it: "DELL", "Gigabyte M32U".
            return displays.firstIndex { $0.name.localizedCaseInsensitiveContains(spec) }
        }
    }

    @discardableResult
    func workspace(_ name: String) -> Workspace {
        if let w = workspaces[name] { return w }
        let w = Workspace(name: name, layout: presets[name]?.layout ?? config.layout.default)
        workspaces[name] = w
        return w
    }

    var orderedNames: [String] { workspaces.keys.sorted(by: Self.nameOrder) }

    /// sketchybar's arrangement-id for a display: its 1-based position among the window server's
    /// managed displays (NSScreen.screens and CGGetActiveDisplayList use other orders).
    static func arrangement(of id: CGDirectDisplayID) -> Int {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) as String? else { return 0 }
        return SkyLight.managedDisplayUUIDs().firstIndex { $0.caseInsensitiveCompare(text) == .orderedSame }.map { $0 + 1 } ?? 0
    }

    /// Numbers in order, then names.
    static func nameOrder(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    var focusedWorkspace: Workspace { workspace(displays.indices.contains(focusedDisplay) ? displays[focusedDisplay].workspace : "1") }

    func workspaceOf(_ id: WindowID) -> Workspace? { workspaces.values.first { $0.contains(id) } }

    func displayShowing(_ name: String) -> Int? { displays.firstIndex { $0.workspace == name } }

    func area(of ws: Workspace) -> CGRect {
        let i = displayShowing(ws.name) ?? focusedDisplay
        return displays.indices.contains(i) ? displays[i].area : CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: - Windows

    private func adopt(_ app: NSRunningApplication, state: [WindowID: String]?) {
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        tracker.observe(app)
        if app.isHidden { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        for w in el.elements(kAXWindowsAttribute) { add(w, pid: app.processIdentifier, state: state, initial: true) }
        if state == nil { layoutVisible(animated: true) }
    }

    /// Starts managing a window; nil when it isn't one paw manages.
    @discardableResult
    private func add(_ el: AXUIElement, pid: pid_t, state: [WindowID: String]?, initial: Bool) -> Window? {
        guard let id = el.windowID, windows[id] == nil else { return nil }
        guard el.string(kAXRoleAttribute) == kAXWindowRole else { return nil }
        let subrole = el.string(kAXSubroleAttribute) ?? ""
        guard ["AXStandardWindow", "AXDialog", "AXFloatingWindow"].contains(subrole) else { return nil }
        guard el.bool(kAXMinimizedAttribute) != true, el.bool("AXFullScreen") != true else { return nil }
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        let title = el.string(kAXTitleAttribute) ?? ""
        let rules = config.rules.filter { $0.matches(app: appName, title: title) }
        if rules.contains(where: { $0.manage == false }) { return nil }
        let frame = el.frame ?? .zero
        let w = Window(id: id, element: el, pid: pid, app: appName, frame: frame)
        windows[id] = w
        tracker.watch(window: el, pid: pid)

        let float = rules.contains { $0.float == true } || subrole != "AXStandardWindow" || !el.isSettable(kAXSizeAttribute)
        var presetName = presets.first { $0.value.slot(for: appName) != nil }?.key
        // A new window of an app you already use on this workspace (a second Finder window moved
        // here, then ⌘K) stays with it instead of jumping to the app's preset workspace.
        if !initial, presetName != nil, focusedWorkspace.allWindows.contains(where: { $0 != id && windows[$0]?.pid == pid }) {
            presetName = nil
        }
        var name = state?[id] ?? rules.first(where: { $0.workspace != nil })?.workspace ?? presetName
        if name == nil, initial, let di = displays.indices.first(where: { displays[$0].frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            name = displays[di].workspace
        }
        let ws = workspace(name ?? focusedWorkspace.name)
        if float { w.floatFrame = frame }
        ws.insert(id, area: area(of: ws), floating: float, slot: presets[ws.name]?.slot(for: appName))
        if !initial || ws.focused == nil { ws.focused = id }
        if displayShowing(ws.name) == nil { hide(w, from: ws) }
        if !initial { layout(ws, animated: true) }
        scheduleSave()
        return w
    }

    private func remove(_ id: WindowID, relayout: Bool = true) {
        guard let w = windows.removeValue(forKey: id) else { return }
        animator.cancel(id)
        let ws = workspaceOf(id)
        let wasFocused = ws?.focused == id
        ws?.remove(id)
        _ = w
        if let ws, relayout, displayShowing(ws.name) != nil {
            layout(ws, animated: true)
            if wasFocused {
                // macOS would focus another window of the same app, maybe on a hidden workspace.
                ignoreFocus(0.35)
                focusWindow(ws.focused, warp: false)
            }
        }
        scheduleSave()
    }

    private func appTerminated(_ pid: pid_t) {
        tracker.forget(pid)
        for w in windows.values where w.pid == pid { remove(w.id) }
    }

    /// Drops windows macOS no longer has. Some apps (Find My) quit as their last window closes
    /// without a destroyed element paw can match or a terminate notification reaching it.
    private func pruneDead() {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return }
        let alive = Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        let dead = windows.keys.filter { !alive.contains($0) }
        guard !dead.isEmpty else { return }
        Log.app.info("pruning \(dead.count) closed windows")
        for id in dead { remove(id) }
    }

    private func window(for el: AXUIElement) -> Window? {
        if let id = el.windowID, let w = windows[id] { return w }
        return windows.values.first { CFEqual($0.element, el) }
    }

    // MARK: - Events

    private func handle(_ e: WindowTracker.Event) {
        switch e {
        case .created(let el, let pid):
            windowCreated(el, pid: pid, retries: 3)
        case .destroyed(let el):
            if let w = window(for: el) { remove(w.id) } else { pruneDead() }
        case .minimized(let el):
            if let w = window(for: el) { remove(w.id) }
        case .deminimized(let el):
            if let id = add(el, pid: el.pid, state: nil, initial: false)?.id { focusWindow(id, warp: true) }
        case .appHidden(let pid):
            for w in windows.values where w.pid == pid { remove(w.id) }
        case .appShown(let pid):
            if let app = NSRunningApplication(processIdentifier: pid) { adopt(app, state: nil) }
        case .focused(let pid):
            syncFocus(pid)
        case .moved(let el), .resized(let el):
            if let w = window(for: el) { userMoved(w) }
        case .titleChanged:
            updateIndicators()
        }
    }

    /// Some apps announce a window before it has its role and size; try again shortly.
    private func windowCreated(_ el: AXUIElement, pid: pid_t, retries: Int) {
        if let w = add(el, pid: pid, state: nil, initial: false) {
            if let ws = workspaceOf(w.id), displayShowing(ws.name) != nil { focusWindow(w.id, warp: true) }
        } else if retries > 0, el.windowID.map({ windows[$0] == nil }) ?? true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.windowCreated(el, pid: pid, retries: retries - 1) }
        }
    }

    private func ignoreFocus(_ seconds: Double) { ignoreFocusUntil = Date().addingTimeInterval(seconds) }

    /// Focus moved outside paw (click, ⌘Tab): follow it, switching workspace when needed.
    private func syncFocus(_ pid: pid_t, force: Bool = false) {
        guard force || Date() > ignoreFocusUntil else { return }
        let app = AXUIElementCreateApplication(pid)
        guard let el = app.element(kAXFocusedWindowAttribute), let id = el.windowID, windows[id] != nil,
              let ws = workspaceOf(id) else { return }
        if let di = displayShowing(ws.name) {
            focusedDisplay = di
            ws.focused = id
            ws.activate(id)
            updateIndicators()
            runHook(config.hooks.windowFocused, ["PAW_WINDOW": "\(id)", "PAW_APP": windows[id]?.app ?? ""])
        } else {
            // Right after paw switches (to an empty workspace, say), macOS hands focus to some
            // window it just hid; following that would switch straight back.
            guard force || Date().timeIntervalSince(lastSwitch) > 1.5 else { return }
            ws.focused = id
            show(ws.name)
        }
    }

    /// A tiled window the user dragged: wait for the mouse button, then swap it with the tile
    /// under the pointer, or snap it back.
    private func userMoved(_ w: Window) {
        if let until = suppressMoves[w.id], until > Date() { return }
        if w.isHidden || animator.isRunning { return }
        guard let ws = workspaceOf(w.id), displayShowing(ws.name) != nil else { return }
        if ws.isFloating(w.id) {
            _ = w.readFrame()
            w.floatFrame = w.frame
            return
        }
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] t in
            guard let self, NSEvent.pressedMouseButtons == 0 else { return }
            t.invalidate()
            dragTimer = nil
            let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            // Dropped on another display: the window moves to the workspace shown there, next to
            // the tile under the mouse (instead of snapping back to its old tile).
            if let di = displays.firstIndex(where: { $0.frame.contains(p) }), displays[di].workspace != ws.name {
                let to = workspace(displays[di].workspace)
                let toFrames = TreeLayout.tileFrames(to, in: displays[di].area, gap: config.layout.gap)
                if let under = to.tiles.first(where: { toFrames[ObjectIdentifier($0)]?.contains(p) == true }) {
                    to.focused = under.activeWindow
                }
                focusedDisplay = di
                moveWindow(w.id, to: to.name, follow: true)
                return
            }
            let frames = TreeLayout.tileFrames(ws, in: area(of: ws), gap: config.layout.gap)
            if let own = ws.tile(of: w.id), let target = ws.tiles.first(where: { $0 !== own && frames[ObjectIdentifier($0)]?.contains(p) == true }),
               let other = target.activeWindow, let i = own.windows.firstIndex(of: w.id), let j = target.windows.firstIndex(of: other) {
                own.windows[i] = other
                target.windows[j] = w.id
            }
            _ = w.readFrame()
            layout(ws, animated: true)
        }
    }

    // MARK: - Layout

    func layoutAll(animated: Bool) {
        hideAllExcept(visible: Set(displays.map(\.workspace)))
        layoutVisible(animated: animated)
    }

    func layoutVisible(animated: Bool) {
        for d in displays { layout(workspace(d.workspace), animated: animated) }
        updateIndicators()
    }

    func layout(_ ws: Workspace, animated: Bool) {
        guard let di = displayShowing(ws.name) else { return }
        let area = displays[di].area
        let frames = TreeLayout.windowFrames(ws, in: area, gap: config.layout.gap)
        var targets: [(Window, CGRect)] = []
        let until = Date().addingTimeInterval(config.animation.durationMs / 1000 + 0.35)
        for t in ws.tiles {
            for id in t.windows {
                guard let w = windows[id], let r = frames[id] else { continue }
                suppressMoves[id] = until
                if w.isHidden { w.isHidden = false; w.setFrame(r); continue }
                // Windows behind a stack's top one move without animation.
                if animated && (id == t.activeWindow || ws.zoomed == id) { targets.append((w, r)) } else if w.frame.integral != r.integral { w.setFrame(r) }
            }
        }
        for id in ws.floating {
            guard let w = windows[id], w.isHidden else { continue }
            suppressMoves[id] = until
            w.isHidden = false
            w.setFrame(w.floatFrame ?? CGRect(origin: CGPoint(x: area.midX - w.frame.width / 2, y: area.midY - w.frame.height / 2), size: w.frame.size))
        }
        animator.animate(targets)
        updateIndicators()
        scheduleSave()
    }

    private func hideAllExcept(visible: Set<String>) {
        for (name, ws) in workspaces where !visible.contains(name) {
            for id in ws.allWindows { if let w = windows[id], !w.isHidden { hide(w, from: ws) } }
        }
    }

    /// Parks a window in a corner of its display with one pixel showing (AeroSpace's trick:
    /// macOS keeps windows that are fully off screen from moving).
    private func hide(_ w: Window, from ws: Workspace) {
        if ws.isFloating(w.id), !w.isHidden { _ = w.readFrame(); w.floatFrame = w.frame }
        animator.cancel(w.id)
        guard let origin = parkingSpot(for: w) else { return }
        suppressMoves[w.id] = Date().addingTimeInterval(1)
        w.setPosition(origin)
        w.isHidden = true
    }

    /// A screen corner where the window sticks out by one pixel and covers no other display:
    /// bottom-right or bottom-left of its display first, then of the others.
    private func parkingSpot(for w: Window) -> CGPoint? {
        let home = displays.first { $0.frame.contains(CGPoint(x: w.frame.midX, y: w.frame.midY)) }
        let order = (home.map { [$0] } ?? []) + displays.filter { $0.id != home?.id }
        let size = w.frame.size
        var first: CGPoint?
        for d in order {
            for origin in [CGPoint(x: d.frame.maxX - 1, y: d.frame.maxY - 1), CGPoint(x: d.frame.minX - size.width + 1, y: d.frame.maxY - 1)] {
                first = first ?? origin
                let spill = CGRect(origin: origin, size: size)
                if !displays.contains(where: { $0.id != d.id && $0.frame.intersects(spill) }) { return origin }
            }
        }
        return first
    }

    // MARK: - Focus

    func focusWindow(_ id: WindowID?, warp: Bool) {
        guard let id, let w = windows[id] else { return }
        if let ws = workspaceOf(id) {
            ws.focused = id
            ws.activate(id)
            if let di = displayShowing(ws.name) { focusedDisplay = di }
        }
        w.focus()
        if warp && config.focus.mouseFollowsFocus {
            let primary = NSScreen.screens.first?.frame.height ?? 0
            let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primary)
            if !w.frame.contains(p) {
                CGWarpMouseCursorPosition(CGPoint(x: w.frame.midX, y: w.frame.midY))
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
        updateIndicators()
        runHook(config.hooks.windowFocused, ["PAW_WINDOW": "\(id)", "PAW_APP": w.app])
    }

    private func updateFocusFollowsMouse() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        guard config.focus.focusFollowsMouse else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, Date().timeIntervalSince(lastHover) > 0.08, NSEvent.pressedMouseButtons == 0 else { return }
            lastHover = Date()
            let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            guard let id = topWindow(at: p), id != focusedWorkspace.focused else { return }
            focusWindow(id, warp: false)
        }
    }

    /// The front-most managed window under a point, by window-server order.
    private func topWindow(at p: CGPoint) -> WindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let n = info[kCGWindowNumber as String] as? UInt32, let w = windows[n], !w.isHidden else { continue }
            if w.frame.contains(p) { return n }
        }
        return nil
    }

    // MARK: - Workspaces

    /// Shows a workspace: on the display that already shows it, its preset display, or the focused one.
    func show(_ name: String) {
        let ws = workspace(name)
        if let di = displayShowing(name) {
            focusedDisplay = di
            focusWindow(ws.focused ?? ws.allWindows.first, warp: true)
            return
        }
        let di = homeDisplay(name) ?? focusedDisplay
        guard displays.indices.contains(di) else { return }
        let old = displays[di].workspace
        ignoreFocus(0.5)
        for id in workspace(old).allWindows { if let w = windows[id], !w.isHidden { hide(w, from: workspace(old)) } }
        displays[di].workspace = name
        focusedDisplay = di
        lastSwitch = Date()
        if old != name { lastWorkspace = old }
        layout(ws, animated: false)
        if let f = ws.focused ?? ws.allWindows.first { focusWindow(f, warp: true) } else { updateIndicators() }
        runHook(config.hooks.workspaceChanged, ["PAW_WORKSPACE": label(name), "PAW_PREV_WORKSPACE": label(old)])
        scheduleSave()
    }

    /// The display a workspace belongs to: its preset's pin or the display it was made on.
    func homeDisplay(_ name: String) -> Int? {
        displayIndex(for: presets[name]?.display) ?? extraPins[name].flatMap { id in displays.firstIndex { $0.id == id } }
    }

    /// Workspaces in the order their numbers go: display by display (the display whose first
    /// workspace has the lowest number first), new ones after the rest of their display. Without
    /// pinned workspaces this is just the names in order.
    var numbered: [String] {
        let names = orderedNames
        guard names.contains(where: { homeDisplay($0) != nil }) else { return names }
        func group(_ n: String) -> String { homeDisplay(n).map { "d\($0)" } ?? "w\(n)" }
        var first: [String: String] = [:]
        for n in names where extraPins[n] == nil {
            let g = group(n)
            if first[g].map({ Self.nameOrder(n, $0) }) ?? true { first[g] = n }
        }
        func key(_ n: String) -> (String, Int, String) {
            let g = group(n)
            return (first[g] ?? n, extraPins[n] == nil ? 0 : 1, n)
        }
        return names.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka.0 != kb.0 { return Self.nameOrder(ka.0, kb.0) }
            if ka.1 != kb.1 { return ka.1 < kb.1 }
            return ka.1 == 1 ? (Int(ka.2.dropFirst()) ?? 0) < (Int(kb.2.dropFirst()) ?? 0) : Self.nameOrder(ka.2, kb.2)
        }
    }

    /// The number a workspace shows (sketchybar, `workspace N`): its place in `numbered` when
    /// workspaces are pinned, else its name.
    func label(_ name: String) -> String {
        guard extraPins.isEmpty == false || orderedNames.contains(where: { homeDisplay($0) != nil }) else { return name }
        return numbered.firstIndex(of: name).map { "\($0 + 1)" } ?? name
    }

    private func resolve(_ t: Command.WorkspaceTarget) -> String? {
        let names = numbered
        let cur = focusedWorkspace.name
        switch t {
        case .name(let n):
            if let i = Int(n), names.contains(where: { homeDisplay($0) != nil }) {
                return names.indices.contains(i - 1) ? names[i - 1] : nil
            }
            return n
        case .last: return lastWorkspace
        case .next, .prev:
            guard let i = names.firstIndex(of: cur), names.count > 1 else { return nil }
            let step = t == .next ? 1 : -1
            return names[(i + step + names.count) % names.count]
        }
    }

    /// Turns a key mode on or off: its keys go first, an island at the top of the focused
    /// display shows it, and hooks.modeChanged runs.
    func setMode(_ name: String?) {
        let name = name.flatMap { config.modes[$0] != nil ? $0 : nil }
        guard name != mode else { return }
        mode = name
        hotkeys.mode = name
        updateModeIsland()
        runHook(config.hooks.modeChanged, ["PAW_MODE": name ?? ""])
    }

    private func updateModeIsland() {
        guard let mode, displays.indices.contains(focusedDisplay) else { modePanel.orderOut(nil); return }
        let style = indicators.style
        let c = style.colors
        var segs: [Island.Segment] = [.init(text: style.text(mode.uppercased(), c.accent, font: style.bold), gapAfter: 10)]
        if mode == "resize" {
            segs.append(.init(text: style.text("←↑→↓ grow  ⇧ shrink  e balance  esc done", c.muted)))
        } else {
            segs.append(.init(text: style.text("esc done", c.muted)))
        }
        let l = Island.make(segs, style: style, scale: NSScreen.main?.backingScaleFactor ?? 2)
        let area = displays[focusedDisplay].area
        let w = l.bounds.width, h = l.bounds.height
        let ax = CGRect(x: (area.midX - w / 2).rounded(), y: area.minY + 8, width: w, height: h)
        let primary = NSScreen.screens.first?.frame.height ?? 0
        modePanel.show(l, at: ScreenGeometry.cocoa(fromAX: ax, primaryHeight: primary))
    }

    /// Shows a stack's new top window: puts it back on its tile even when it was left parked in
    /// a corner (the cached frame can't be trusted then), then focuses it.
    private func bringForward(_ id: WindowID, in ws: Workspace) {
        if let w = windows[id] {
            _ = w.readFrame()
            if !displays.contains(where: { $0.area.intersects(w.frame.insetBy(dx: 20, dy: 20)) }) { w.isHidden = true }
        }
        layout(ws, animated: false)
        focusWindow(id, warp: false)
    }

    /// "Initiate workspace": opens the preset apps that aren't running, waits until each has a
    /// window (or the timeout), then arranges every preset workspace.
    private func initiate(setup: String? = nil) {
        if let setup {
            guard config.setups[setup] != nil else { Log.app.error("no setup \(setup, privacy: .public)"); return }
            forcedSetup = setup
            rebuildDisplays()
        }
        let cfg = config.initiate
        let apps = cfg.appsToOpen(presets)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName))
        for app in apps where !running.contains(app) { Shell.run("open -g -a \(Self.shellQuote(app))", env: [:]) }
        let deadline = Date().addingTimeInterval(cfg.timeout)
        func check() {
            for app in NSWorkspace.shared.runningApplications where apps.contains(app.localizedName ?? "") { adopt(app, state: nil) }
            let have = Set(windows.values.map(\.app))
            if apps.allSatisfy({ have.contains($0) }) || Date() > deadline {
                applySetup()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check() }
    }

    /// Puts everything where the presets in effect say: every preset workspace arranged, windows
    /// of other apps on `layout.unassignedWorkspace`, each display on its pinned workspace, then
    /// the setup's (or initiate's) focus.
    func applySetup() {
        setupChanged = false
        arrangeAll()
        for i in displays.indices {
            let pinned = presets.keys.sorted(by: Self.nameOrder).first { displayIndex(for: presets[$0]?.display) == i }
            if let pinned, pinned != displays[i].workspace {
                focusedDisplay = i
                show(pinned)
            }
        }
        let focus = activeSetup.flatMap { config.setups[$0]?.focus }.flatMap { $0.isEmpty ? nil : $0 } ?? config.initiate.focus
        if !focus.isEmpty { show(focus) }
        layoutAll(animated: false)
        runHook(config.hooks.workspaceChanged, ["PAW_WORKSPACE": focusedWorkspace.name, "PAW_PREV_WORKSPACE": focusedWorkspace.name])
    }

    /// Every preset arranged, the rest on the unassigned workspace, leftover empty extras closed.
    private func arrangeAll() {
        for name in presets.keys.sorted(by: Self.nameOrder) { arrange(name) }
        placeUnassigned()
        let keep = Set(presets.keys).union((1...max(1, config.layout.workspaces)).map(String.init)).union(displays.map(\.workspace))
        for (name, ws) in workspaces where ws.allWindows.isEmpty && !keep.contains(name) {
            workspaces[name] = nil
            extraPins[name] = nil
        }
        scheduleSave()
    }

    /// Windows of apps that no preset or rule places go to `layout.unassignedWorkspace`.
    private func placeUnassigned() {
        let target = config.layout.unassignedWorkspace
        guard !target.isEmpty else { return }
        let to = workspace(target)
        for ws in workspaces.values where ws !== to {
            for id in ws.allWindows {
                guard let w = windows[id] else { continue }
                let placed = presets.values.contains { $0.slot(for: w.app) != nil }
                    || config.rules.contains { $0.workspace != nil && $0.matches(app: w.app, title: w.title) }
                guard !placed else { continue }
                let floating = ws.isFloating(id)
                ws.remove(id)
                to.insert(id, area: area(of: to), floating: floating, slot: nil)
                if displayShowing(target) == nil { hide(w, from: to) }
            }
        }
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Applies a workspace preset: pulls its apps' tiled windows from other workspaces, then
    /// rebuilds the tiles in preset order.
    private func arrange(_ name: String) {
        guard let preset = presets[name] else { return }
        let target = workspace(name)
        var touched: [Workspace] = []
        for other in workspaces.values where other !== target {
            let ids = other.allWindows.filter { id in
                !other.isFloating(id) && windows[id].map { preset.slot(for: $0.app) != nil } == true
            }
            guard !ids.isEmpty else { continue }
            for id in ids {
                other.remove(id)
                target.insert(id, area: area(of: target))
                if displayShowing(name) == nil, let w = windows[id] { hide(w, from: target) }
            }
            touched.append(other)
        }
        let list = target.allWindows.compactMap { id in windows[id].map { (id: id, app: $0.app) } }
        target.arrange(preset, windows: list, area: area(of: target))
        layout(target, animated: true)
        for other in touched { layout(other, animated: true) }
        scheduleSave()
    }

    private func moveWindow(_ id: WindowID, to name: String, follow: Bool) {
        guard let from = workspaceOf(id), from.name != name, let w = windows[id] else { return }
        let floating = from.isFloating(id)
        from.remove(id)
        let to = workspace(name)
        to.insert(id, area: area(of: to), floating: floating, slot: presets[name]?.slot(for: w.app))
        to.focused = id
        if displayShowing(name) != nil { layout(to, animated: true) } else { hide(w, from: to) }
        if displayShowing(from.name) != nil { layout(from, animated: true) }
        if follow { show(name); focusWindow(id, warp: true) } else { ignoreFocus(0.35); focusWindow(from.focused, warp: false) }
        scheduleSave()
    }

    private func displayTarget(_ t: Command.DisplayTarget) -> Int? {
        guard !displays.isEmpty else { return nil }
        switch t {
        case .index(let n): return displays.indices.contains(n - 1) ? n - 1 : nil
        case .next: return (focusedDisplay + 1) % displays.count
        case .prev: return (focusedDisplay - 1 + displays.count) % displays.count
        case .dir(let d):
            let others = displays.indices.filter { $0 != focusedDisplay }
            return TreeLayout.nearest(from: displays[focusedDisplay].frame, d, candidates: others.map { displays[$0].frame }).map { others[$0] }
        }
    }

    // MARK: - Commands

    func run(_ cmds: [Command]) {
        Log.app.debug("run \(String(describing: cmds), privacy: .public) on \(self.focusedWorkspace.name, privacy: .public) focused \(String(describing: self.focusedID), privacy: .public)")
        for c in cmds { execute(c) }
    }

    private var focusedID: WindowID? {
        let ws = focusedWorkspace
        if let f = ws.focused, ws.contains(f), windows[f] != nil { return f }
        return ws.tiledWindows.first ?? ws.floating.first
    }

    func execute(_ c: Command) {
        let ws = focusedWorkspace
        let area = self.area(of: ws)
        let fid = focusedID
        func relayout() { layout(ws, animated: true) }
        switch c {
        case .focus(let target):
            switch target {
            case .dir(let d): focus(direction: d)
            case .stackNext: if let id = fid, let n = ws.cycleStack(id, by: 1, wrap: config.focus.wrapStacks) { bringForward(n, in: ws) }
            case .stackPrev: if let id = fid, let n = ws.cycleStack(id, by: -1, wrap: config.focus.wrapStacks) { bringForward(n, in: ws) }
            case .stackFirst: if let id = fid, let t = ws.tile(of: id), let n = t.windows.first { focusWindow(n, warp: false) }
            case .stackLast: if let id = fid, let t = ws.tile(of: id), let n = t.windows.last { focusWindow(n, warp: false) }
            }
        case .swap(let d):
            guard let id = fid else { return }
            if ws.swap(id, d, area: area) { relayout(); focusWindow(id, warp: true) } else { execute(.moveToDisplay(.dir(d), follow: true)) }
        case .swapStack(let by):
            guard let id = fid, ws.moveInStack(id, by: by) else { return }
            relayout()
            focusWindow(id, warp: false)
        case .warp(let d):
            guard let id = fid else { return }
            if ws.warp(id, d, area: area) { relayout(); focusWindow(id, warp: true) }
        case .stack(let d):
            guard let id = fid, ws.stack(id, d, area: area) else { return }
            relayout()
            focusWindow(id, warp: true)
        case .unstack(let all):
            guard let id = fid else { return }
            if all { ws.unstackAll(id, area: area) } else { ws.unstack(id, area: area) }
            relayout()
            focusWindow(id, warp: true)
        case .layout(let k):
            if k == .float { for id in ws.tiledWindows { windows[id].map { _ = $0.readFrame(); $0.floatFrame = $0.frame } } }
            ws.setLayout(k, area: area)
            relayout()
        case .toggle(let t):
            guard let id = fid else { return }
            switch t {
            case .float:
                if !ws.isFloating(id), let w = windows[id] {
                    // Float at two thirds of the area, centred.
                    let r = CGRect(x: area.midX - area.width / 3, y: area.midY - area.height / 3, width: area.width * 2 / 3, height: area.height * 2 / 3).integral
                    ws.toggleFloat(id, area: area)
                    w.floatFrame = r
                    w.setFrame(r)
                } else {
                    ws.toggleFloat(id, area: area)
                }
            case .zoom: ws.toggleZoom(id)
            case .split: ws.toggleSplit(id)
            }
            relayout()
        case .balance:
            ws.balance(); relayout()
        case .rotate(let deg):
            ws.rotate(deg); relayout()
        case .resize(let d, let px):
            guard let id = fid else { return }
            if ws.isFloating(id), let w = windows[id] {
                var r = w.readFrame() ?? w.frame
                switch d {
                case .west: r.origin.x -= px; r.size.width += px
                case .east: r.size.width += px
                case .north: r.origin.y -= px; r.size.height += px
                case .south: r.size.height += px
                }
                w.setFrame(r)
                w.floatFrame = r
            } else if ws.resize(id, d, by: px, area: area) {
                relayout()
            }
        case .grid(let g):
            guard let id = fid, let w = windows[id] else { return }
            if !ws.isFloating(id) { ws.toggleFloat(id, area: area) }
            let r = g.frame(in: area)
            w.floatFrame = r
            w.setFrame(r)
            relayout()
        case .workspace(let t):
            if let n = resolve(t) { show(n) }
        case .workspaceNew:
            if displays.indices.contains(focusedDisplay), orderedNames.contains(where: { homeDisplay($0) == focusedDisplay }) {
                // On this display, numbered after its workspaces; later displays' numbers move up.
                extraSeq += 1
                let name = "+\(extraSeq)"
                extraPins[name] = displays[focusedDisplay].id
                _ = workspace(name)
                show(name)
            } else {
                var n = 1
                while let w = workspaces["\(n)"], !w.isEmpty || displayShowing(w.name) != nil { n += 1 }
                show("\(n)")
            }
        case .workspaceClose:
            closeWorkspace(ws)
        case .moveTo(let t, let follow):
            if let id = fid, let n = resolve(t) { moveWindow(id, to: n, follow: follow) }
        case .focusDisplay(let t):
            if let di = displayTarget(t) {
                focusedDisplay = di
                let target = workspace(displays[di].workspace)
                focusWindow(target.focused ?? target.allWindows.first, warp: true)
            }
        case .moveToDisplay(let t, let follow):
            if let id = fid, let di = displayTarget(t) { moveWindow(id, to: displays[di].workspace, follow: follow) }
        case .initiate(let setup):
            initiate(setup: setup)
        case .mode(let name):
            setMode(name == mode ? nil : name)
        case .arrange(let name):
            if name == "all" { arrangeAll() } else { arrange(name ?? ws.name) }
        case .exec(let cmd):
            Shell.run(cmd, env: [:])
        case .retile:
            layoutAll(animated: true)
        case .recover:
            recover()
        case .reload:
            settings.load()
        }
    }

    private func focus(direction d: Direction) {
        let ws = focusedWorkspace
        let area = self.area(of: ws)
        if let id = focusedID, let t = ws.tile(of: id), let n = ws.neighbor(of: t, d, area: area) {
            focusWindow(n.activeWindow, warp: true)
            return
        }
        if let id = focusedID, ws.isFloating(id), let w = windows[id] {
            let cands = ws.allWindows.filter { $0 != id }.compactMap { c in windows[c].map { (c, $0.frame) } }
            if let i = TreeLayout.nearest(from: w.frame, d, candidates: cands.map(\.1)) { focusWindow(cands[i].0, warp: true); return }
        }
        // Nothing that way: the next display (yabai's `|| display --focus`).
        execute(.focusDisplay(.dir(d)))
    }

    private func closeWorkspace(_ ws: Workspace) {
        let names = numbered
        guard names.count > 1 else { return }
        // Another workspace of the same display first.
        let sameDisplay = names.filter { $0 != ws.name && homeDisplay($0) != nil && homeDisplay($0) == homeDisplay(ws.name) }
        let fallback = sameDisplay.last(where: { Self.nameOrder($0, ws.name) || extraPins[$0] != nil }) ?? sameDisplay.first
            ?? lastWorkspace.flatMap { $0 != ws.name && workspaces[$0] != nil ? $0 : nil }
            ?? names[(names.firstIndex(of: ws.name)! + names.count - 1) % names.count]
        let target = workspace(fallback)
        for id in ws.allWindows {
            let floating = ws.isFloating(id)
            ws.remove(id)
            target.insert(id, area: self.area(of: target), floating: floating)
        }
        show(fallback)
        if Int(ws.name).map({ $0 > config.layout.workspaces }) ?? true, presets[ws.name] == nil {
            workspaces[ws.name] = nil
            extraPins[ws.name] = nil
        }
        layoutAll(animated: true)
    }

    /// Re-reads every app's windows and puts anything stray back where it belongs.
    func recover() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { adopt(app, state: nil) }
        // Visible floating windows that ended up off every screen come back to the middle.
        for d in displays {
            let ws = workspace(d.workspace)
            for id in ws.floating {
                guard let w = windows[id], let f = w.readFrame(), !displays.contains(where: { $0.frame.intersects(f.insetBy(dx: 20, dy: 20)) }) else { continue }
                w.setFrame(CGRect(x: d.area.midX - f.width / 2, y: d.area.midY - f.height / 2, width: f.width, height: f.height).integral)
                w.floatFrame = w.frame
                w.isHidden = false
            }
        }
        layoutAll(animated: true)
    }

    // MARK: - Indicators, hooks, state

    func updateIndicators() {
        var stacks: [Stack] = []
        let focused = NSWorkspace.shared.frontmostApplication.flatMap { _ in focusedID }
        for (di, d) in displays.enumerated() {
            let ws = workspace(d.workspace)
            let frames = TreeLayout.tileFrames(ws, in: d.area, gap: config.layout.gap)
            for t in ws.tiles where t.windows.count > 1 && !(ws.zoomed.map { t.windows.contains($0) } ?? false) {
                guard let f = frames[ObjectIdentifier(t)] else { continue }
                stacks.append(Stack(space: di, frame: f, items: t.windows.map { id in
                    Stack.Item(id: Int(id), app: windows[id]?.app ?? "", title: windows[id]?.title ?? "",
                               isActive: t.activeWindow == id, hasFocus: id == focused && di == focusedDisplay)
                }))
            }
        }
        indicators.apply(stacks)
        if mode != nil { updateModeIsland() }
    }

    private func runHook(_ cmd: String, _ env: [String: String]) {
        guard !cmd.isEmpty else { return }
        Shell.run(cmd, env: env)
    }

    /// Runs hooks.windowsChanged shortly after the workspace → apps picture changes.
    private func scheduleWindowsHook() {
        guard !config.hooks.windowsChanged.isEmpty else { return }
        windowsHookWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let sig = orderedNames.map { name in
                name + ":" + self.workspace(name).allWindows.compactMap { self.windows[$0]?.app }.sorted().joined(separator: ",")
            }.joined(separator: "|")
            guard sig != lastWindowsSignature else { return }
            lastWindowsSignature = sig
            runHook(config.hooks.windowsChanged, [:])
        }
        windowsHookWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func scheduleSave() {
        scheduleWindowsHook()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var map: [WindowID: String] = [:]
            for (name, ws) in workspaces { for id in ws.allWindows { map[id] = name } }
            StateFile.save(map)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Workspaces for `paw query`.
    func query() -> [[String: Any]] {
        numbered.map { name in
            let ws = workspace(name)
            let pinned = homeDisplay(name)
            let home = pinned ?? displayShowing(name)
            return ["name": label(name), "id": name, "visible": displayShowing(name) != nil, "focused": name == focusedWorkspace.name,
                    "displayID": home.map { Int(displays[$0].id) } ?? 0, "pinned": pinned != nil,
                    "arrangement": home.map { Self.arrangement(of: displays[$0].id) } ?? 0,
                    "display": displayShowing(name).map { $0 + 1 } ?? 0, "layout": ws.layout.rawValue,
                    "windows": ws.allWindows.compactMap { id -> [String: Any]? in
                        guard let w = windows[id] else { return nil }
                        let color = AppColors.shared.color(for: w.app, icons: config.icons)?.description ?? ""
                        return ["id": Int(id), "app": w.app, "title": w.title, "color": color, "floating": ws.isFloating(id),
                                "stacked": (ws.tile(of: id)?.windows.count ?? 0) > 1, "focused": ws.focused == id]
                    }]
        }
    }
}

/// Which workspace each window was on, so a restart (or a crash) finds parked windows again.
enum StateFile {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: AppPaths.bundleID).appending(path: "state.json")
    }

    static func load() -> [WindowID: String] {
        guard let data = try? Data(contentsOf: url), let d = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var out: [WindowID: String] = [:]
        for (k, v) in d { if let id = WindowID(k) { out[id] = v } }
        return out
    }

    static func save(_ map: [WindowID: String]) {
        var d: [String: String] = [:]
        for (k, v) in map { d["\(k)"] = v }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(d).write(to: url)
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}

enum Shell {
    static func run(_ cmd: String, env: [String: String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (e["PATH"] ?? "/usr/bin:/bin")
        for (k, v) in env { e[k] = v }
        p.environment = e
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
