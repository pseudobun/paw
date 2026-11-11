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
    private var focusWork: DispatchWorkItem?
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
    /// Workspaces moved to another display (`move-workspace`, the overview), by display id.
    private var movedTo: [String: CGDirectDisplayID] = [:]
    /// When paw last switched a display's workspace itself.
    private var lastSwitch = Date.distantPast
    /// The workspace presets in effect: the active setup's, else `workspaces`.
    var presets: [String: WorkspacePreset] { activeSetup.flatMap { config.setups[$0]?.workspaces } ?? config.workspaces }
    /// The workspace each display showed last, so one plugged in again gets its workspace back.
    private var workspaceByDisplay: [CGDirectDisplayID: String] = [:]
    private(set) var mode: String?
    private let modePanel = TitlePanel()
    private var lastWindowsSignature = ""
    private var mouseMonitors: [Any] = []
    private var lastHover = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var pruneTimer: Timer?
    private var screensAsleep = false
    private var hoverPending = false
    private var lastFocusReported: WindowID?
    private var layoutEventWork: DispatchWorkItem?
    /// The zoom level last reported per workspace (`zoomChanged`).
    private var reportedZoom: [String: Int] = [:]
    /// Per workspace: trees before each layout change (undo) and after undoing (redo).
    private var undoStack: [String: [WorkspaceSnapshot]] = [:]
    private var redoStack: [String: [WorkspaceSnapshot]] = [:]
    private var lastUndoRecord: (name: String, kind: String, at: Date)?
    /// Windows focused, oldest first, for `focus back|forward`.
    private var history: [WindowID] = []
    private var historyIndex = -1
    private var navigatingHistory = false
    /// Where minimized windows and windows of hidden or quit apps were, to put them back.
    private var ghosts: [Ghost] = []
    private struct Ghost {
        let app: String
        let title: String
        let workspace: String
        let anchor: Anchor?
        let floating: Bool
        /// Windows of a quit app come back only for a while; the layout moves on.
        var expires: Date = .distantFuture
    }
    let hud = WorkspaceHUD()
    let moveHUD = MoveHUD()
    let placeholders = Placeholders()
    let border = FocusBorder()
    private var borderRefreshWork: DispatchWorkItem?
    let edges = EdgeMarkers()
    /// Inside a workspace switch: indicators, border and edges wait until switching settles.
    private var settling = false
    private var settleWork: DispatchWorkItem?
    /// The workspace a run of quick switches started from (for one workspaceChanged at the end).
    private var burstPrev: String?
    /// Sizes apps keep their windows at, at least (learned when a window sticks out of its tile).
    private var windowMins: [WindowID: CGSize] = [:]
    private var overflowSuspects: [WindowID: CGSize] = [:]
    private var overflowWork: [String: DispatchWorkItem] = [:]
    private var minimumChecks: [WindowID: (token: UUID, focus: Int?, frontmost: pid_t?)] = [:]
    private var focusRevision = 0
    private var relayingOutClamped = false
    private var droppingSide = false
    /// The window paw just focused, until macOS catches up (the border goes there at once).
    private var pawFocus: (id: WindowID, at: Date)?
    /// The window server and AX calls that focus a window take 20–40 ms; they run here, in
    /// order, while the border, indicators and pointer move at once.
    private let focusQueue = DispatchQueue(label: "paw.focus", qos: .userInteractive)
    let dropPreview = DropPreview()
    private var indicatorsDirty = false
    /// Which workspace each window was on when paw started (from the state file).
    private var launchState: [WindowID: String] = [:]
    lazy var seams = SeamHandles(wm: self)
    lazy var gestures = MouseGestures(wm: self)
    lazy var overview = OverviewController(wm: self)

    init(settings: Settings) {
        self.settings = settings
        indicators = IndicatorController(settings: settings)
    }

    var config: PawConfig { settings.config }

    // MARK: - Lifecycle

    func start() {
        AXUIElementSetMessagingTimeout(AXUIElement.systemWide, 0.5)
        animator.settings = { [unowned self] in config.animation }
        animator.onFinish = { [weak self] in
            self?.updateIndicators()
            self?.scheduleBorderRefresh()
        }
        tracker.onEvent = { [weak self] in self?.handle($0) }
        hotkeys.run = { [weak self] in self?.run($0) }
        indicators.onFocus = { [weak self] id in self?.focusWindow(id, warp: false) }
        edges.onClick = { [weak self] name in self?.show(name) }
        configChanged()
        gestures.start()
        if !hotkeys.start() { Log.app.error("key bindings: event tap not allowed (Accessibility)") }

        rebuildDisplays()
        let state = StateFile.load()
        launchState = state.windows
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            adopt(app, state: state.windows)
        }
        // The trees as they were when paw quit or crashed: tiles, sizes, stacks.
        for (name, snap) in state.trees {
            guard let ws = workspaces[name], !ws.isEmpty else { continue }
            ws.restore(snap, area: area(of: ws))
        }
        migrateOldExtras()
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Give the app a moment to make its first window.
            // Some (Brave) make it after a window-created notification could reach paw; look again.
            for delay in [0.4, 1.5, 4.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.adopt(app, state: nil, fresh: true) }
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
            // Not right away: listing every window waits on the window server, and an app comes
            // forward with every workspace switch.
            self?.schedulePrune()
            self?.syncFocus(app.processIdentifier)
            // Another app in front (one paw doesn't manage, say): the border follows at once.
            self?.updateIndicators()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.scheduleDisplaysChanged()
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleDisplaysChanged()
        })
        // While the screen is locked, accessibility lists placeholders instead of an app's
        // windows: paw started then (a login item, a restart over SSH) knows none of them. Once
        // it's unlocked, take on every window it doesn't have yet.
        let unlocked: (Notification) -> Void = { [weak self] _ in
            for delay in [0.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.adoptAll() }
            }
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                                                             object: nil, queue: .main, using: unlocked))
        observers.append(ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main,
                                        using: unlocked))
        // Catches windows that vanish without any notification (see pruneDead).
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pruneDead() }
        pruneTimer?.tolerance = 0.5
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
        })
        layoutAll(animated: false)
        if setupChanged { applySetup() }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { syncFocus(pid, force: true) }
        Log.app.info("managing \(self.windows.count) windows on \(self.displays.count) displays")
    }

    func configChanged() {
        for w in windows.values { w.invalidateCornerRadius(); w.borderNeedsRefresh = true }
        DockBridge.shared.enabled = config.layout.windowServer
        hotkeys.set(config.bindings, modes: config.modes)
        gestures.configChanged()
        if let m = mode, config.modes[m] == nil { setMode(nil) }
        for p in hotkeys.problems { Log.app.warning("bindings: \(p, privacy: .public)") }
        indicators.configChanged()
        updateFocusFollowsMouse()
        for ws in workspaces.values {
            ws.canvasMin = CGSize(width: config.layout.minTileWidth, height: config.layout.minTileHeight)
            ws.placeholderMin = placeholderMin
        }
        // Windows a rule now leaves alone (manage: false) are let go, where they are.
        for w in windows.values where config.rules.contains(where: { $0.manage == false && $0.matches(app: w.app, title: w.title) }) {
            if w.isHidden { w.isHidden = false; w.setFrame(w.floatFrame ?? w.frame) }
            remove(w.id)
        }
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
        // Kept, so paw started again (just install, a login) puts everything back as it was.
        saveWork?.cancel()
        saveState()
    }

    // MARK: - Displays and workspaces

    static func axFrame(_ r: CGRect) -> CGRect {
        ScreenGeometry.axFrame(ofScreen: r, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// Screen padding widened so a stack indicator outside its window fits between the window
    /// and the screen edge, with `indicator.offsetX` on both sides of it.
    private func indicatorPadding(_ p: Padding) -> Padding {
        let i = config.indicator
        var p = p
        if i.enabled {
            let room = i.width + 2 * i.offsetX
            if [.auto, .left].contains(i.side) { p.left = max(p.left, room) }
            if [.auto, .right].contains(i.side) { p.right = max(p.right, room) }
        }
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
        let prevWorkspace = displays.isEmpty ? "" : label(focusedWorkspace.name)
        // Workspaces that live on each display now: shown there, pinned there, or made there.
        var onDisplay: [CGDirectDisplayID: Set<String>] = [:]
        for (i, d) in displays.enumerated() {
            var names: Set<String> = [d.workspace]
            for name in workspaces.keys where homeDisplay(name) == i { names.insert(name) }
            onDisplay[d.id] = names
        }
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
        let gone = Set(onDisplay.keys).subtracting(displays.map(\.id))
        if !gone.isEmpty { setAside(Set(gone.flatMap { onDisplay[$0] ?? [] })) }
        if before != after {
            emitWorkspaceChanged(prev: prevWorkspace)
            runHook(config.hooks.displaysChanged, ["PAW_DISPLAYS": "\(displays.count)"])
            publish("displaysChanged", ["displays": displays.count, "workspaces": query()])
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
        if !lastDisplayIDs.isEmpty, displaysNow != lastDisplayIDs { forcedSetup = nil; movedTo = [:] }
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
            let name = match?.name ?? ""
            DispatchQueue.main.async { [weak self] in self?.publish("setupChanged", ["setup": name]) }
        }
        for n in 1...max(1, l.workspaces) { _ = workspace("\(n)") }
        for name in presets.keys { _ = workspace(name) }
        for i in displays.indices where displays[i].workspace.isEmpty {
            let preset = presets.keys.sorted(by: Self.nameOrder).first { displayIndex(for: presets[$0]?.display) == i && !used.contains($0) }
            let name = preset ?? orderedNames.first { !used.contains($0) && $0 != Self.side } ?? "\(displays.count + i)"
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
        w.canvasMin = CGSize(width: config.layout.minTileWidth, height: config.layout.minTileHeight)
        w.placeholderMin = placeholderMin
        w.windowMins = windowMins
        workspaces[name] = w
        return w
    }

    var orderedNames: [String] { workspaces.keys.sorted(by: Self.nameOrder) }

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

    /// Every running app's windows paw doesn't manage yet (after the screen unlocks).
    /// Each goes back to the workspace the state file has it on, as at launch.
    func adoptAll() {
        let before = windows.count
        // Started while locked, paw has since saved a state without these windows: where they were
        // at launch counts too.
        let state = StateFile.load().windows.merging(launchState) { now, _ in now }
        AXQueue.run {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                adopt(app, state: state)
            }
            guard windows.count != before else { return }
            layoutVisible(animated: false)
        }
        if windows.count != before { Log.app.info("adopted \(self.windows.count - before) more windows") }
    }

    /// `fresh`: the app just launched, so its windows are new ones: they go next to the focused
    /// window and take focus, like any window opened later.
    private func adopt(_ app: NSRunningApplication, state: [WindowID: String]?, fresh: Bool = false) {
        guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        tracker.observe(app)
        if app.isHidden { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var added: [WindowID] = []
        for w in el.elements(kAXWindowsAttribute) {
            if let win = add(w, pid: app.processIdentifier, state: state, initial: !fresh) { added.append(win.id) }
        }
        if state == nil, !added.isEmpty { layoutVisible(animated: true) }
        if fresh, let id = added.last, let ws = workspaceOf(id), displayShowing(ws.name) != nil { focusWindow(id, warp: true) }
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
        var presetName = presets.first { $0.value.slot(for: appName, title: title) != nil }?.key
        // A new window of an app you already use on this workspace (a second Finder window moved
        // here, then ⌘K) stays with it instead of jumping to the app's preset workspace.
        if !initial, presetName != nil, focusedWorkspace.allWindows.contains(where: { $0 != id && windows[$0]?.pid == pid }) {
            presetName = nil
        }
        var name = state?[id] ?? rules.first(where: { $0.workspace != nil })?.workspace ?? presetName
        if name == nil, initial, let di = displays.indices.first(where: { displays[$0].frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            name = displays[di].workspace
        }
        // Back where it was before it was minimized, hidden or its app quit.
        let ghost = state == nil && !rules.contains(where: { $0.workspace != nil }) ? takeGhost(app: appName, title: title) : nil
        if let ghost { name = ghost.workspace }
        let ws = workspace(name ?? focusedWorkspace.name)
        if float { w.floatFrame = frame }
        if let a = ghost?.anchor, !float, ghost?.floating == false, ws.insert(id, at: a) {
            // placed by its anchor
        } else {
            ws.insert(id, area: area(of: ws), floating: float || ghost?.floating == true,
                      slot: presets[ws.name]?.slot(for: appName, title: title))
        }
        if !initial || ws.focused == nil { ws.focused = id }
        if displayShowing(ws.name) == nil { hide(w, from: ws) }
        if !initial { layout(ws, animated: true) }
        scheduleSave()
        return w
    }

    private func remove(_ id: WindowID, relayout: Bool = true, closed: Bool = false) {
        guard let w = windows.removeValue(forKey: id) else { return }
        suppressMoves[id] = nil
        minimumBackoff[id] = nil
        if lastFocusReported == id { lastFocusReported = nil }
        windowMins[id] = nil
        overflowSuspects[id] = nil
        minimumChecks[id] = nil
        for ws in workspaces.values { ws.windowMins[id] = nil }
        animator.cancel(id)
        let ws = workspaceOf(id)
        let wasFocused = ws?.focused == id && (!closed || ws === focusedWorkspace)
        ws?.remove(id)
        if let ws, relayout, displayShowing(ws.name) != nil {
            // Hit-test before retiling, ignoring the closed window's lingering animation.
            let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            let hovered = closed && wasFocused ? topWindow(at: p, ignoring: [id]) : nil
            if wasFocused {
                let appFocused = AXUIElementCreateApplication(w.pid).element(kAXFocusedWindowAttribute)?.windowID
                let target = Self.focusAfterRemoval(in: ws, hovered: hovered, appFocused: appFocused) {
                    windows[$0]?.pid == w.pid
                }
                ignoreFocus(0.35)
                focusWindow(target, warp: false)
            }
            layout(ws, animated: true)
        }
        scheduleSave()
    }

    private func appTerminated(_ pid: pid_t) {
        tracker.forget(pid)
        let gone = windows.values.filter { $0.pid == pid }.map(\.id)
        for id in gone { remember(id, for: 300) }
        removeAll(gone)
        AXQueue.forget(pid)
        AXHealth.forget(pid)
    }

    /// Drops windows macOS no longer has. Some apps (Find My) quit as their last window closes
    /// without a destroyed element paw can match or a terminate notification reaching it.
    private var pruneWork: DispatchWorkItem?

    private func schedulePrune() {
        pruneWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pruneDead() }
        pruneWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func pruneDead() {
        if screensAsleep { return }
        let alive = Self.liveWindows(Array(windows.keys))
        let dead = windows.keys.filter { !alive.contains($0) }
        guard !dead.isEmpty else { return }
        Log.app.info("pruning \(dead.count) closed windows")
        removeAll(dead)
    }

    /// Which of `ids` the window server still has. Asks about these windows only (about 0.2 ms
    /// for 30), not for the list of every window on the system (about 5 ms).
    static func liveWindows(_ ids: [WindowID]) -> Set<WindowID> {
        guard !ids.isEmpty else { return [] }
        var ptrs = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
              let list = CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    /// Several windows gone at once (an app quit, a prune): each workspace is laid out once, after
    /// the last of its windows goes, instead of once per window.
    private func removeAll(_ ids: [WindowID]) {
        var last: [String: WindowID] = [:]
        let removing = Set(ids)
        for id in ids {
            if let ws = workspaceOf(id) {
                last[ws.name] = ws.focused.flatMap { removing.contains($0) ? $0 : nil } ?? id
            }
        }
        let final = Set(last.values)
        AXQueue.run {
            for id in ids where !final.contains(id) {
                assert(workspaceOf(id)?.focused != id, "The focused window must be removed last for close recovery")
                remove(id, relayout: false, closed: true)
            }
            for id in ids where final.contains(id) { remove(id, closed: true) }
        }
    }

    private func window(for el: AXUIElement) -> Window? {
        // Comparing elements stays in paw; asking for the window number goes to the app (and
        // every window paw moves sends a notification).
        if let w = windows.values.first(where: { CFEqual($0.element, el) }) { return w }
        if let id = el.windowID, let w = windows[id] { return w }
        return nil
    }

    // MARK: - Events

    private func handle(_ e: WindowTracker.Event) {
        AXQueue.run { handleEvent(e) }
    }

    private func handleEvent(_ e: WindowTracker.Event) {
        switch e {
        case .created(let el, let pid):
            windowCreated(el, pid: pid, retries: 3)
        case .destroyed(let el):
            if let w = window(for: el) { remove(w.id, closed: true) } else { pruneDead() }
        case .minimized(let el):
            if let w = window(for: el) { remember(w.id); remove(w.id) }
        case .deminimized(let el):
            if let id = add(el, pid: el.pid, state: nil, initial: false)?.id { focusWindow(id, warp: true) }
        case .appHidden(let pid):
            for w in windows.values where w.pid == pid { remember(w.id); remove(w.id) }
        case .appShown(let pid):
            if let app = NSRunningApplication(processIdentifier: pid) { adopt(app, state: nil) }
        case .focused(let pid):
            syncFocus(pid)
        case .moved(let el):
            if let w = window(for: el) { w.borderNeedsRefresh = true; userMoved(w) }
        case .resized(let el):
            if let w = window(for: el) {
                w.invalidateCornerRadius()
                w.borderNeedsRefresh = true
                userMoved(w)
            }
        case .titleChanged(let el):
            if let w = window(for: el), w.refreshTitle() {
                retryMinimum(w, fromTitle: true)
                // Titles show in stack indicators and placeholders only: a ticking title elsewhere
                // (a terminal's spinner, an unread count) redraws nothing.
                if let ws = workspaceOf(w.id), (ws.tile(of: w.id)?.windows.count ?? 0) > 1 || windowMins[w.id] != nil {
                    updateIndicators()
                }
            }
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
        focusWork?.cancel()
        // Taking the keyboard for a placeholder has no native window and preserves its size retry.
        if pid != getpid() || NSApp.keyWindow != nil { focusRevision += 1 }
        if force { applyFocus(pid, force: true); return }
        // Let close notifications arrive before accepting macOS's automatic replacement.
        let work = DispatchWorkItem { [weak self] in
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self?.applyFocus(pid)
        }
        focusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func applyFocus(_ pid: pid_t, force: Bool = false) {
        guard force || Date() > ignoreFocusUntil else { return }
        // A process exit can activate its replacement before destruction/termination is reported.
        if !force, !screensAsleep, let previous = focusedWorkspace.focused, windows[previous] != nil,
           !Self.liveWindows([previous]).contains(previous) {
            AXQueue.run { remove(previous, closed: true) }
            return
        }
        let app = AXUIElementCreateApplication(pid)
        guard let el = app.element(kAXFocusedWindowAttribute), let id = el.windowID else { return }
        if windows[id] == nil {
            // A window paw never heard about (some apps, ChatGPT among them, make theirs before
            // their accessibility notifications work): take it on now that it has focus.
            guard let running = NSRunningApplication(processIdentifier: pid), running.activationPolicy == .regular else { return }
            tracker.observe(running)
            guard add(el, pid: pid, state: nil, initial: false) != nil else { return }
        }
        guard windows[id] != nil, let ws = workspaceOf(id) else { return }
        if let di = displayShowing(ws.name) {
            focusedDisplay = di
            ws.focused = id
            ws.activate(id)
            if let w = windows[id] { retryMinimum(w, focus: true) }
            if ws.frameCamera(on: id, area: displays[di].area, gap: config.layout.gap) { layout(ws, animated: true) }
            updateIndicators()
            focusChanged(id)
        } else {
            // Right after paw switches (to an empty workspace, say), macOS hands focus to some
            // window it just hid; following that would switch straight back.
            guard force || Date().timeIntervalSince(lastSwitch) > 1.5 else { return }
            ws.focused = id
            show(ws.name)
        }
    }

    /// A tiled window the user dragged or resized: follow it until the mouse button is up.
    /// Moving shows where it would land (drop zones) and puts it there; resizing an edge
    /// changes the tile sizes; anything else snaps back.
    private func userMoved(_ w: Window) {
        if let until = suppressMoves[w.id], until > Date() {
            if w.id == focusedID { scheduleBorderRefresh() }
            return
        }
        if w.isHidden || animator.isRunning { return }
        guard let ws = workspaceOf(w.id), displayShowing(ws.name) != nil else { return }
        if ws.isFloating(w.id) {
            _ = w.readFrame()
            w.floatFrame = w.frame
            if w.id == focusedID { updateBorder(cramped: []) }
            return
        }
        guard dragTimer == nil else { return }
        // Only a drag with the mouse counts; an app moving or clamping its own window snaps back.
        var sawMouse = NSEvent.pressedMouseButtons != 0
        let expected = TreeLayout.windowFrames(ws, in: area(of: ws), gap: config.layout.gap)[w.id] ?? w.frame
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let current = w.readFrame() ?? w.frame
            // A resize keeps the opposite edge where it was. Moving to another display can change
            // the size too (macOS fits the window to it), but then every edge moves.
            let sized = abs(current.width - expected.width) > 2 || abs(current.height - expected.height) > 2
            let xKept = abs(current.minX - expected.minX) <= 2 || abs(current.maxX - expected.maxX) <= 2
            let yKept = abs(current.minY - expected.minY) <= 2 || abs(current.maxY - expected.maxY) <= 2
            let resized = sized && xKept && yKept
            let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            if NSEvent.pressedMouseButtons != 0 {
                sawMouse = true
                guard config.mouse.dropZones, !resized, let hit = dropTarget(at: p, dragging: w.id), let target = hit.target,
                      let area = displayArea(hit.display),
                      let f = DropZones.preview(target, in: hit.ws, area: area, gap: config.layout.gap, dragging: w.id) else {
                    dropPreview.hide()
                    return
                }
                dropPreview.show(f, style: indicators.style)
                return
            }
            t.invalidate()
            dragTimer = nil
            dropPreview.hide()
            guard let ws = workspaceOf(w.id) else { return }
            guard sawMouse else { layout(ws, animated: true); return }
            if resized {
                // An edge (or corner) dragged: the tile sizes follow it.
                recordUndo(ws, kind: "command")
                let a = area(of: ws)
                if abs(current.minX - expected.minX) > 2 { _ = ws.resize(w.id, .west, by: expected.minX - current.minX, area: a) }
                if abs(current.maxX - expected.maxX) > 2 { _ = ws.resize(w.id, .east, by: current.maxX - expected.maxX, area: a) }
                if abs(current.minY - expected.minY) > 2 { _ = ws.resize(w.id, .north, by: expected.minY - current.minY, area: a) }
                if abs(current.maxY - expected.maxY) > 2 { _ = ws.resize(w.id, .south, by: current.maxY - expected.maxY, area: a) }
                layout(ws, animated: true)
                return
            }
            guard let hit = dropTarget(at: p, dragging: w.id) else { layout(ws, animated: true); return }
            if hit.ws !== ws {
                // Dropped on another display: it moves to the workspace shown there.
                focusedDisplay = hit.display
                drop(w.id, on: config.mouse.dropZones ? hit.target : nil, in: hit.ws)
                focusWindow(w.id, warp: false)
                return
            }
            if config.mouse.dropZones {
                drop(w.id, on: hit.target, in: ws)
            } else {
                // Without drop zones: swap with the tile under the pointer.
                let frames = TreeLayout.tileFrames(ws, in: area(of: ws), gap: config.layout.gap)
                if let own = ws.tile(of: w.id), let under = ws.tiles.first(where: { $0 !== own && frames[ObjectIdentifier($0)]?.contains(p) == true }),
                   let other = under.activeWindow {
                    drop(w.id, on: .swap(tile: other), in: ws)
                } else {
                    layout(ws, animated: true)
                }
            }
            focusWindow(w.id, warp: false)
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
        // A canvas keeps the focused window on screen with its tiles at their minimum size.
        if let f = ws.focused, ws.tile(of: f) != nil { ws.frameCamera(on: f, area: area, gap: config.layout.gap) }
        let frames = TreeLayout.windowFrames(ws, in: area, gap: config.layout.gap)
        var targets: [(Window, CGRect)] = []
        var clamped = false
        let until = Date().addingTimeInterval(config.animation.durationMs / 1000 + 0.35)
        for t in ws.tiles {
            // The window on top can't get this small: the whole stack waits out of sight and a
            // placeholder takes the tile (the stack's indicator still goes through it).
            let topCramped = t.activeWindow.map { isCramped($0, in: frames) } ?? false
            for id in t.windows {
                guard let w = windows[id], let r = frames[id] else { continue }
                if topCramped || isCramped(id, in: frames) {
                    if !w.isHidden { hide(w, from: ws) }
                    continue
                }
                _ = r
                suppressMoves[id] = until
                if w.isHidden { w.isHidden = false; w.setFrame(r); if learnClamp(w, r) { clamped = true }; continue }
                // Windows behind a stack's top one move without animation.
                if animated && (id == t.activeWindow || ws.zoomed == id) {
                    targets.append((w, r))
                } else if w.frame.integral != r.integral {
                    w.setFrame(r)
                    if learnClamp(w, r) { clamped = true }
                }
            }
        }
        // A window its app kept bigger than its tile: lay out again now, with a placeholder there.
        if clamped, !relayingOutClamped {
            relayingOutClamped = true
            layout(ws, animated: animated)
            relayingOutClamped = false
            return
        }
        // Zoomed into a branch: the rest of the tree waits out of sight.
        for id in ws.tiledWindows where frames[id] == nil {
            if let w = windows[id], !w.isHidden { hide(w, from: ws) }
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
        scheduleLayoutEvent(ws.name)
        reportZoom(ws)
        if !targets.isEmpty { scheduleOverflowCheck(ws.name, after: config.animation.durationMs / 1000 + 0.05) }
    }

    /// After a layout settles: windows larger than their tile (apps with a minimum size) are
    /// remembered at that size, once it shows twice in a row, and the workspace is laid out again.
    private func scheduleOverflowCheck(_ name: String, after delay: Double) {
        overflowWork[name]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkOverflow(name) }
        overflowWork[name] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func checkOverflow(_ name: String) {
        guard let di = displayShowing(name) else { return }
        // Windows still moving: look again once they've landed.
        if animator.isRunning { scheduleOverflowCheck(name, after: 0.15); return }
        let ws = workspace(name)
        let frames = TreeLayout.windowFrames(ws, in: displays[di].area, gap: config.layout.gap)
        var learned = false, suspect = false
        for t in ws.tiles {
            guard let id = t.activeWindow, let w = windows[id], !w.isHidden, let r = frames[id], ws.zoomed != id,
                  let actual = w.element.frame else { continue }
            let over = CGSize(width: actual.width > r.width + 4 ? actual.width : 0, height: actual.height > r.height + 4 ? actual.height : 0)
            guard over.width > 0 || over.height > 0 else { overflowSuspects[id] = nil; continue }
            // After an animation the app has had its frames; a second look only when it's still resizing.
            if overflowSuspects[id] == nil || abs(overflowSuspects[id]!.width - over.width) < 4 && abs(overflowSuspects[id]!.height - over.height) < 4 {
                let old = windowMins[id] ?? .zero
                let m = CGSize(width: max(old.width, over.width), height: max(old.height, over.height))
                windowMins[id] = m
                for other in workspaces.values { other.windowMins[id] = m }
                overflowSuspects[id] = nil
                learned = true
                Log.app.info("\(w.app, privacy: .public) needs at least \(Int(m.width))×\(Int(m.height))")
            } else {
                overflowSuspects[id] = over
                suspect = true
            }
        }
        if learned { layout(ws, animated: false) } else if suspect { scheduleOverflowCheck(name, after: 0.4) }
    }

    /// A Chromium window can later accept a size it refused during startup or a transition.
    /// Retry while parked so a genuine minimum never flashes over its neighbours.
    /// Title changes retry a parked window's size with growing pauses (1 s, 2 s … 60 s): a window
    /// whose title ticks would otherwise be resized every time it does.
    private var minimumBackoff: [WindowID: (next: Date, interval: TimeInterval)] = [:]

    static func nextBackoff(_ interval: TimeInterval?) -> TimeInterval { min(60, (interval ?? 0.5) * 2) }

    private func retryMinimum(_ w: Window, focus: Bool = false, fromTitle: Bool = false) {
        if fromTitle {
            let now = Date()
            if let b = minimumBackoff[w.id], now < b.next { return }
            let interval = Self.nextBackoff(minimumBackoff[w.id]?.interval)
            minimumBackoff[w.id] = (now.addingTimeInterval(interval), interval)
        } else if focus {
            minimumBackoff[w.id] = nil
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if var pending = minimumChecks[w.id] {
            if focus {
                pending.focus = focusRevision
                pending.frontmost = frontmost
                minimumChecks[w.id] = pending
            }
            return
        }
        guard w.isHidden,
              let ws = workspaceOf(w.id), let di = displayShowing(ws.name),
              let target = TreeLayout.windowFrames(ws, in: displays[di].area, gap: config.layout.gap)[w.id],
              isCramped(w.id) else { return }
        let token = UUID()
        minimumChecks[w.id] = (token, focus ? focusRevision : nil, frontmost)
        w.element.setSize(target.size)
        // Left-corner parking depends on the actual width, which the probe may have changed.
        _ = w.readFrame()
        hide(w, from: ws)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let check = self.minimumChecks[w.id], check.token == token else { return }
            defer { self.minimumChecks[w.id] = nil }
            guard self.windows[w.id] === w, w.isHidden, let parkedWorkspace = self.workspaceOf(w.id) else { return }
            // An asynchronous resize must be reparked even when recovery is no longer valid.
            let actual = w.readFrame()?.size
            self.hide(w, from: parkedWorkspace)
            guard parkedWorkspace === ws,
                  let di = self.displayShowing(ws.name),
                  let current = TreeLayout.windowFrames(ws, in: self.displays[di].area, gap: self.config.layout.gap)[w.id],
                  current.size == target.size, let actual,
                  actual.width > 0, actual.height > 0,
                  actual.width <= target.width + 4, actual.height <= target.height + 4 else { return }
            self.windowMins[w.id] = nil
            self.overflowSuspects[w.id] = nil
            for workspace in self.workspaces.values { workspace.windowMins[w.id] = nil }
            self.layout(ws, animated: false)
            if check.focus == self.focusRevision,
               check.frontmost == NSWorkspace.shared.frontmostApplication?.processIdentifier,
               self.focusedWorkspace === ws, ws.focused == w.id, !w.isHidden {
                self.focusWindow(w.id, warp: false)
            }
        }
    }

    /// Reconcile queued moves once they settle; coalesced, with no idle polling.
    private func scheduleBorderRefresh() {
        guard config.border.enabled else { return }
        borderRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.animator.isRunning, !AXQueue.deferring,
                  let id = self.focusedID, let w = self.windows[id], !w.isMoving else { return }
            self.updateBorder(cramped: self.isCramped(id) ? [id] : [])
        }
        borderRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// The focus border follows the window's observed bounds, or the placeholder's tile.
    private func updateBorder(cramped: Set<WindowID>) {
        guard config.border.enabled, !overview.isOpen, let id = focusedID, let w = windows[id],
              let ws = workspaceOf(id), let di = displayShowing(ws.name) else { border.hide(); return }
        let placeholder = cramped.contains(id)
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let justFocused = pawFocus.map { $0.id == id && Date().timeIntervalSince($0.at) < 1 } ?? false
        guard placeholder || justFocused || frontPid == w.pid else { border.hide(); return }
        if border.windowID != id {
            w.invalidateCornerRadius()
            w.borderNeedsRefresh = true
        }
        if !placeholder, w.borderNeedsRefresh {
            if !animator.isRunning, !AXQueue.deferring, !w.isMoving {
                w.borderFrame = SkyLight.frame(id)
                w.borderNeedsRefresh = false
            } else { scheduleBorderRefresh() }
        }
        let tile = placeholder || (w.borderFrame == nil && !ws.isFloating(id))
            ? TreeLayout.windowFrames(ws, in: displays[di].area, gap: config.layout.gap)[id] : nil
        let frame = w.frameForBorder(tile: tile, placeholder: placeholder)
        let radius = !placeholder && config.border.autoRadius ? w.radiusForBorder() : nil
        border.show(frame, window: id, above: !placeholder, screen: displays[di].frame, config: config.border, radius: radius)
    }

    private var placeholderMin: CGSize {
        guard config.layout.placeholders else { return .zero }
        return CGSize(width: max(1, config.layout.placeholderMinWidth), height: max(1, config.layout.placeholderMinHeight))
    }

    private func isCramped(_ id: WindowID, in frames: [WindowID: CGRect]) -> Bool {
        guard config.layout.placeholders, let m = windowMins[id], let r = frames[id] else { return false }
        return m.width > r.width + 2 || m.height > r.height + 2
    }

    /// Whether `id` is shown as a placeholder right now.
    func isCramped(_ id: WindowID) -> Bool {
        guard windowMins[id] != nil, let ws = workspaceOf(id), let di = displayShowing(ws.name) else { return false }
        return isCramped(id, in: TreeLayout.windowFrames(ws, in: displays[di].area, gap: config.layout.gap))
    }

    /// A placeholder dragged: the same drop zones as a window.
    func placeholderDragged(_ id: WindowID, to p: CGPoint) {
        guard let hit = dropTarget(at: p, dragging: id), let target = hit.target, let area = displayArea(hit.display),
              let f = DropZones.preview(target, in: hit.ws, area: area, gap: config.layout.gap, dragging: id) else {
            dropPreview.hide()
            return
        }
        dropPreview.show(f, style: indicators.style)
    }

    func placeholderDropped(_ id: WindowID, at p: CGPoint) {
        dropPreview.hide()
        guard let hit = dropTarget(at: p, dragging: id) else { return }
        if let from = workspaceOf(id), from !== hit.ws { focusedDisplay = hit.display }
        drop(id, on: hit.target, in: hit.ws)
        focusWindow(id, warp: false)
    }

    /// One step through the tree towards `id` (in) or back out, with the HUD saying how deep.
    func zoom(inward: Bool, toward id: WindowID) {
        guard let ws = workspaceOf(id), let di = displayShowing(ws.name) else { return }
        let area = displays[di].area, gap = config.layout.gap
        let before = TreeLayout.cameraFrames(ws, in: area, gap: gap)
        guard inward ? ws.zoomIn(toward: id) : ws.zoomOut() else { return }
        recordUndo(ws, kind: "command")
        animateCamera(ws, from: before, on: di)
        let d = ws.zoomDepth(of: id)
        hud.style = indicators.style
        var apps: [String] = []
        for a in ws.tiledWindows.filter(ws.shownWindows.contains).compactMap({ windows[$0]?.app }) where !apps.contains(a) { apps.append(a) }
        hud.show(label: d.level == 0 ? label(ws.name) : "\(label(ws.name))  \(d.level)/\(d.levels)", apps: apps,
                 in: displays[di].area, icons: settings.icons, config: config, duration: config.hud.durationMs / 1000)
        focusWindow(id, warp: false)
    }

    /// The camera moved: windows glide from where the old camera had them to where the new one
    /// puts them, those coming in from off screen, those leaving out of it (then parked).
    /// Off screen past an edge another display shares, a glide would cross that display:
    /// those windows are parked or put in place at once instead.
    private func animateCamera(_ ws: Workspace, from before: [WindowID: CGRect], on di: Int) {
        guard config.animation.enabled else { layout(ws, animated: false); return }
        let area = displays[di].area, home = displays[di].frame
        let after = TreeLayout.cameraFrames(ws, in: area, gap: config.layout.gap)
        func crossesOther(_ r: CGRect) -> Bool {
            displays.contains { $0.frame != home && $0.frame.intersects(r.insetBy(dx: 1, dy: 1)) }
        }
        let shown = ws.shownWindows
        let until = Date().addingTimeInterval(config.animation.durationMs / 1000 + 0.4)
        var targets: [(Window, CGRect)] = []
        for t in ws.tiles {
            // Only each stack's top window moves; the rest follow at the end.
            guard let id = t.activeWindow, let w = windows[id], let to = after[id] else { continue }
            if isCramped(id) { continue }
            suppressMoves[id] = until
            if w.isHidden {
                guard shown.contains(id), let from = before[id] else { continue }
                w.isHidden = false
                if crossesOther(from) { w.setFrame(to); continue }
                w.setFrame(from)
            } else if !shown.contains(id), crossesOther(to) {
                hide(w, from: ws)
                continue
            }
            targets.append((w, to))
        }
        animator.animate(targets)
        DispatchQueue.main.asyncAfter(deadline: .now() + config.animation.durationMs / 1000 + 0.03) { [weak self] in
            self?.layout(ws, animated: false)
        }
    }

    /// An empty workspace has nothing to focus: paw takes the keyboard (so no window elsewhere
    /// keeps it), the pointer goes there and the HUD says where you are.
    private func focusEmpty(_ di: Int) {
        guard displays.indices.contains(di) else { return }
        let prev = displays.indices.contains(focusedDisplay) ? label(displays[focusedDisplay].workspace) : ""
        focusedDisplay = di
        ignoreFocus(0.5)
        NSApp.activate(ignoringOtherApps: true)
        if config.focus.mouseFollowsFocus {
            let a = displays[di].area
            CGWarpMouseCursorPosition(CGPoint(x: a.midX, y: a.midY))
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        showHUD(displays[di].workspace, on: di)
        updateIndicators()
        emitWorkspaceChanged(prev: prev)
    }

    /// From the overview: work in the region holding these windows.
    func focusArea(_ ids: [WindowID], in name: String) {
        let ws = workspace(name)
        let inRegion = ids.filter { ws.tile(of: $0) != nil }
        guard !inRegion.isEmpty else { return }
        let target = ws.focused.flatMap { inRegion.contains($0) ? $0 : nil } ?? inRegion[0]
        if let di = displayShowing(name) {
            let before = TreeLayout.cameraFrames(ws, in: displays[di].area, gap: config.layout.gap)
            guard ws.setView(containing: inRegion) else { return }
            ws.focused = target
            animateCamera(ws, from: before, on: di)
            focusWindow(target, warp: true)
        } else {
            ws.focused = target
            show(name)
            ws.setView(containing: inRegion)
            layout(ws, animated: false)
            focusWindow(target, warp: true)
        }
    }

    /// ⌥-scroll / ⌥-pinch: zoom towards the window under the pointer (AX point).
    func zoom(inward: Bool, at p: CGPoint) {
        let id = topWindow(at: p) ?? focusedID
        if let id { zoom(inward: inward, toward: id) }
    }

    /// Right after paw set a window's frame: AX set calls return once the app has applied them,
    /// so a bigger size read back now is the app's own minimum. Learns it; true when new.
    private func learnClamp(_ w: Window, _ r: CGRect) -> Bool {
        // Moves still waiting to go out: look once they have.
        if AXQueue.deferring || w.isMoving {
            if let ws = workspaceOf(w.id) { scheduleOverflowCheck(ws.name, after: 0.15) }
            return false
        }
        guard let s = w.element.size else { return false }
        let over = CGSize(width: s.width > r.width + 4 ? s.width : 0, height: s.height > r.height + 4 ? s.height : 0)
        guard over.width > 0 || over.height > 0 else { return false }
        // Some apps (Chromium) apply a size a moment later: a second look confirms it.
        overflowSuspects[w.id] = over
        if let ws = workspaceOf(w.id) { scheduleOverflowCheck(ws.name, after: 0.12) }
        return false
    }

    /// From a placeholder: zoom in towards the window until its tile is big enough for it.
    func makeRoom(for id: WindowID) {
        guard let ws = workspaceOf(id), let di = displayShowing(ws.name) else { return }
        let area = displays[di].area
        func fitsNow() -> Bool {
            guard let r = TreeLayout.windowFrames(ws, in: area, gap: config.layout.gap)[id] else { return false }
            let m = windowMins[id] ?? .zero
            return r.width + 2 >= m.width && r.height + 2 >= m.height
        }
        ws.focused = id
        ws.activate(id)
        while !fitsNow(), ws.zoomIn(toward: id) {}
        layout(ws, animated: true)
        focusWindow(id, warp: true)
    }

    private func hideAllExcept(visible: Set<String>) {
        for (name, ws) in workspaces where !visible.contains(name) {
            for id in ws.allWindows { if let w = windows[id], !w.isHidden { hide(w, from: ws) } }
        }
    }

    /// Parks a window in a corner of its display with one pixel showing (AeroSpace's trick:
    /// macOS keeps windows that are fully off screen from moving).
    private func hide(_ w: Window, from ws: Workspace) {
        if ws.isFloating(w.id), !w.isHidden {
            // Still on its way somewhere: where it's going is where it is.
            if !w.isMoving { _ = w.readFrame() }
            w.floatFrame = w.frame
        }
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

    static func focusAfterRemoval(in ws: Workspace, hovered: WindowID?, appFocused: WindowID?,
                                  sameApp: (WindowID) -> Bool) -> WindowID? {
        hovered ?? appFocused.flatMap { ws.contains($0) ? $0 : nil }
            ?? ws.allWindows.first(where: sameApp) ?? ws.focused
    }

    func focusWindow(_ id: WindowID?, warp: Bool) {
        guard let id, let w = windows[id] else { return }
        focusWork?.cancel()
        focusRevision += 1
        let ticket = FocusTicket.shared.issue()
        if let ws = workspaceOf(id) {
            ws.focused = id
            ws.activate(id)
            if let di = displayShowing(ws.name) {
                focusedDisplay = di
                // Out of a zoom or off a canvas's screen: bring it into view first.
                if ws.frameCamera(on: id, area: displays[di].area, gap: config.layout.gap) { layout(ws, animated: true) }
            }
        }
        // A placeholder: focus is paw's (moves, swaps); the window itself waits out of sight.
        if isCramped(id) {
            NSApp.activate(ignoringOtherApps: true)
            retryMinimum(w, focus: true)
            minimumChecks[id]?.frontmost = getpid()
            if warp && config.focus.mouseFollowsFocus, let ws = workspaceOf(id), let di = displayShowing(ws.name),
               let r = TreeLayout.windowFrames(ws, in: displays[di].area, gap: config.layout.gap)[id] {
                let primary = NSScreen.screens.first?.frame.height ?? 0
                if !r.contains(ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primary)) {
                    CGWarpMouseCursorPosition(CGPoint(x: r.midX, y: r.midY))
                    CGAssociateMouseAndMouseCursorPosition(1)
                }
            }
            updateIndicators()
            focusChanged(id)
            return
        }
        let (pid, element) = (w.pid, w.element)
        // Requests pile up behind a slow app: only the newest one still goes.
        focusQueue.async {
            guard FocusTicket.shared.isLatest(ticket) else { return }
            SkyLight.focus(pid: pid, windowID: id, element: element)
        }
        pawFocus = (id, Date())
        if warp && config.focus.mouseFollowsFocus {
            let primary = NSScreen.screens.first?.frame.height ?? 0
            let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: primary)
            if !w.frame.contains(p) {
                CGWarpMouseCursorPosition(CGPoint(x: w.frame.midX, y: w.frame.midY))
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
        updateIndicators()
        focusChanged(id)
    }

    private func updateFocusFollowsMouse() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
        guard config.focus.focusFollowsMouse else { return }
        // Global monitoring excludes events sent to paw while a placeholder owns focus.
        mouseMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.hovered() },
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.hovered()
                return event
            },
        ].compactMap { $0 }
    }

    /// At most one look every 80 ms while the pointer moves, and one more once it stops: the
    /// last position always counts, even when it came between two looks.
    private func hovered() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let wait = 0.08 - Date().timeIntervalSince(lastHover)
        guard wait <= 0 else {
            guard !hoverPending else { return }
            hoverPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.hoverPending = false
                self?.hovered()
            }
            return
        }
        lastHover = Date()
        let p = ScreenGeometry.cocoa(fromAX: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        guard let id = topWindow(at: p), id != focusedWorkspace.focused else { return }
        focusWindow(id, warp: false)
    }

    /// The front-most window under a point, only if paw manages it.
    func topWindow(at p: CGPoint, ignoring ignored: Set<WindowID> = []) -> WindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ignored = ignored.union(NSApp.windows.filter(\.ignoresMouseEvents).compactMap { WindowID(exactly: $0.windowNumber) })
        return Self.topWindow(at: p, in: list, ignoring: ignored,
                              standIns: placeholders.standIns.filter { windows[$0.value] != nil }) {
            windows[$0]?.isHidden == false
        }
    }

    static func topWindow(at p: CGPoint, in list: [[String: Any]], ignoring ignored: Set<WindowID> = [],
                          standIns: [WindowID: WindowID] = [:],
                          isManaged: (WindowID) -> Bool) -> WindowID? {
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let id = info[kCGWindowNumber as String] as? UInt32, !ignored.contains(id),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.contains(p) else { continue }
            if let standIn = standIns[id] {
                if ignored.contains(standIn) { continue }
                return standIn
            }
            guard layer >= 0 else { continue }
            // Unmanaged dialogs still occlude windows behind them.
            return isManaged(id) ? id : nil
        }
        return nil
    }

    // MARK: - Workspaces

    /// Shows a workspace: on the display that already shows it, its preset display, or the focused one.
    func show(_ name: String) {
        let ws = workspace(name)
        if let di = displayShowing(name) {
            if let id = ws.focused ?? ws.allWindows.first {
                focusedDisplay = di
                focusWindow(id, warp: true)
            } else {
                focusEmpty(di)
            }
            return
        }
        let di = homeDisplay(name) ?? focusedDisplay
        guard displays.indices.contains(di) else { return }
        let old = displays[di].workspace
        workspace(old).clearZoom()
        ignoreFocus(0.5)
        // Switching through workspaces quickly: what isn't the windows themselves (indicators,
        // border, edges, the workspaceChanged event) catches up once it stops.
        settling = true
        defer { settling = false; scheduleSettle() }
        if burstPrev == nil { burstPrev = label(old) }
        displays[di].workspace = name
        focusedDisplay = di
        lastSwitch = Date()
        if old != name { lastWorkspace = old }
        // The new windows come up and the old ones go away together, every app at once.
        AXQueue.run {
            layout(ws, animated: false)
            for id in workspace(old).allWindows { if let w = windows[id], !w.isHidden { hide(w, from: workspace(old)) } }
        }
        if let f = ws.focused ?? ws.allWindows.first {
            focusWindow(f, warp: true)
        } else {
            // Nothing there: no window on another workspace keeps the keys.
            NSApp.activate(ignoringOtherApps: true)
        }
        showHUD(name, on: di)
        scheduleSave()
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            updateIndicators()
            if let prev = burstPrev {
                burstPrev = nil
                emitWorkspaceChanged(prev: prev)
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// The display a workspace belongs to: its preset's pin or the display it was made on.
    func homeDisplay(_ name: String) -> Int? {
        if let id = movedTo[name], let i = displays.firstIndex(where: { $0.id == id }) { return i }
        return displayIndex(for: presets[name]?.display) ?? extraPins[name].flatMap { id in displays.firstIndex { $0.id == id } }
    }

    /// The workspace `move-workspace` trades contents with: next/prev in the bar's order (no
    /// wrapping, the side workspace left out), or a number.
    private func resolveMoveTarget(_ t: Command.WorkspaceTarget, from name: String) -> String? {
        let order = numberedWorkspaces
        switch t {
        case .next, .prev:
            guard let i = order.firstIndex(of: name) else { return nil }
            let j = i + (t == .next ? 1 : -1)
            return order.indices.contains(j) ? order[j] : nil
        default:
            guard let n = resolve(t), n != name, n != Self.side else { return nil }
            return n
        }
    }

    /// Trades the contents of two workspaces (windows, tiles, layout); focus follows the
    /// contents of `from` to `to`, on whichever display shows it.
    func swapWorkspaces(_ from: String, _ to: String, showMove: Bool = false) {
        // The side workspace stays put: it's where windows wait, not a place in the order.
        guard from != to, from != Self.side, to != Self.side, let a = workspaces[from] else { return }
        let b = workspace(to)
        let prev = label(focusedWorkspace.name)
        a.swapContents(with: b)
        undoStack[from] = nil; undoStack[to] = nil; redoStack[from] = nil; redoStack[to] = nil
        // Windows now on a workspace that isn't shown wait out of sight; shown ones are laid out.
        for ws in [a, b] {
            if displayShowing(ws.name) == nil {
                for id in ws.allWindows { if let w = windows[id], !w.isHidden { hide(w, from: ws) } }
            }
        }
        if displayShowing(to) == nil { show(to) } else { layout(b, animated: true) }
        if displayShowing(from) != nil { layout(a, animated: true) }
        if let f = b.focused ?? b.allWindows.first { focusWindow(f, warp: true) }
        if showMove { showMoveHUD(around: to) } else if let di = displayShowing(to) { showHUD(to, on: di) }
        emitWorkspaceChanged(prev: prev)
        scheduleSave()
    }

    /// The strip that shows where a moving workspace is: its neighbours in the bar's order.
    private func showMoveHUD(around name: String) {
        let order = numberedWorkspaces
        guard let i = order.firstIndex(of: name), let di = displayShowing(name) else { return }
        func cell(_ n: String) -> MoveHUD.Cell {
            var apps: [String] = []
            for a in workspace(n).allWindows.compactMap({ windows[$0]?.app }) where !apps.contains(a) { apps.append(a) }
            return .init(label: label(n), apps: apps)
        }
        hud.hide()
        moveHUD.style = indicators.style
        moveHUD.show(prev: i > 0 ? cell(order[i - 1]) : nil, current: cell(name),
                     next: i + 1 < order.count ? cell(order[i + 1]) : nil,
                     side: workspaces[Self.side] != nil ? cell(Self.side) : nil,
                     in: displays[di].area, icons: settings.icons, config: config)
    }

    /// Moves a workspace, windows and all, to display `di`, where it shows; the display it left
    /// shows another of its workspaces. It stays there until the displays change.
    func moveWorkspace(_ name: String, to di: Int) {
        guard displays.indices.contains(di), workspaces[name] != nil, name != Self.side else { return }
        let from = displayShowing(name)
        guard from != di else { return }
        movedTo[name] = displays[di].id
        if let from {
            // The display it leaves: its next workspace, or a new empty one.
            let next = numberedWorkspaces.first { homeDisplay($0) == from && displayShowing($0) == nil && $0 != name }
                ?? orderedNames.first { $0 != Self.side && $0 != name && displayShowing($0) == nil && homeDisplay($0) == nil }
            if let next {
                displays[from].workspace = next
                layout(workspace(next), animated: false)
            }
        }
        // The display it goes to puts its own workspace away.
        let old = displays[di].workspace
        for id in workspace(old).allWindows { if let w = windows[id], !w.isHidden { hide(w, from: workspace(old)) } }
        displays[di].workspace = name
        focusedDisplay = di
        let ws = workspace(name)
        layout(ws, animated: true)
        if let f = ws.focused ?? ws.allWindows.first { focusWindow(f, warp: true) } else { focusEmpty(di) }
        emitWorkspaceChanged(prev: label(old))
        showHUD(name, on: di)
        scheduleSave()
    }

    /// Workspaces in the order their numbers go: display by display (the display whose first
    /// workspace has the lowest number first), new ones after the rest of their display. Without
    /// pinned workspaces this is just the names in order.
    var numbered: [String] { (workspaces[Self.side] != nil ? [Self.side] : []) + numberedWorkspaces }

    /// The numbered workspaces (everything but the side one).
    private var numberedWorkspaces: [String] {
        let names = orderedNames.filter { $0 != Self.side }
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
        if name == Self.side { return "+\(workspaces[name]?.allWindows.count ?? 0)" }
        guard extraPins.isEmpty == false || orderedNames.contains(where: { homeDisplay($0) != nil }) else { return name }
        return numberedWorkspaces.firstIndex(of: name).map { "\($0 + 1)" } ?? name
    }

    private func resolve(_ t: Command.WorkspaceTarget, making: Bool = false) -> String? {
        let names = numbered
        let cur = focusedWorkspace.name
        switch t {
        case .name(let n):
            // "+N" (as the bar shows it) or "side": the side workspace.
            if n.hasPrefix("+") || n == Self.side { return workspaces[Self.side] != nil || making ? Self.side : nil }
            let core = numberedWorkspaces
            if let i = Int(n), core.contains(where: { homeDisplay($0) != nil }) {
                return core.indices.contains(i - 1) ? core[i - 1] : nil
            }
            return n
        case .last: return lastWorkspace
        case .next, .prev:
            guard let i = names.firstIndex(of: cur), names.count > 1 else { return nil }
            let step = t == .next ? 1 : -1
            if !config.focus.wrapWorkspaces, !names.indices.contains(i + step) { return nil }
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
        publish("modeChanged", ["mode": name ?? ""])
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
        // Tiles with `launch` run it when no window matches (a terminal in a project folder, say).
        var launched = Set<String>()
        for preset in presets.values {
            for t in preset.tiles {
                guard let cmd = t.launch, !cmd.isEmpty,
                      !windows.values.contains(where: { t.matches(app: $0.app, title: $0.title) }) else { continue }
                Shell.run(cmd, env: [:])
                for a in t.apps { launched.insert(a) }
            }
        }
        for app in apps where !running.contains(app) && !launched.contains(app) { Shell.run("open -g -a \(Self.shellQuote(app))", env: [:]) }
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
        let prevWorkspace = displays.isEmpty ? "" : label(focusedWorkspace.name)
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
        emitWorkspaceChanged(prev: prevWorkspace)
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
                let placed = presets.values.contains { $0.slot(for: w.app, title: w.title) != nil }
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
                !other.isFloating(id) && windows[id].map { preset.slot(for: $0.app, title: $0.title) != nil } == true
            }
            guard !ids.isEmpty else { continue }
            for id in ids {
                other.remove(id)
                target.insert(id, area: area(of: target))
                if displayShowing(name) == nil, let w = windows[id] { hide(w, from: target) }
            }
            touched.append(other)
        }
        let list = target.allWindows.compactMap { id in windows[id].map { (id: id, app: $0.app, title: $0.title) } }
        recordUndo(target, kind: "arrange")
        target.arrange(preset, windows: list, area: area(of: target))
        layout(target, animated: true)
        for other in touched { layout(other, animated: true) }
        scheduleSave()
    }

    private func moveWindow(_ id: WindowID, to name: String, follow: Bool) {
        guard let from = workspaceOf(id), from.name != name, let w = windows[id] else { return }
        recordUndo(from, kind: "move")
        recordUndo(workspace(name), kind: "move")
        let floating = from.isFloating(id)
        from.remove(id)
        let to = workspace(name)
        to.insert(id, area: area(of: to), floating: floating, slot: presets[name]?.slot(for: w.app, title: w.title))
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
        // Window moves go to each app's own queue: the main thread never waits on a slow app.
        AXQueue.run { for c in cmds { execute(c) } }
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
        if Self.changesLayout(c) { recordUndo(ws, kind: Self.undoKind(c)) }
        switch c {
        case .focus(let target):
            switch target {
            case .dir(let d): focus(direction: d)
            case .stackNext: if let id = fid, let n = ws.cycleStack(id, by: 1, wrap: config.focus.wrapStacks) { bringForward(n, in: ws) }
            case .stackPrev: if let id = fid, let n = ws.cycleStack(id, by: -1, wrap: config.focus.wrapStacks) { bringForward(n, in: ws) }
            case .stackFirst: if let id = fid, let t = ws.tile(of: id), let n = t.windows.first { focusWindow(n, warp: false) }
            case .stackLast: if let id = fid, let t = ws.tile(of: id), let n = t.windows.last { focusWindow(n, warp: false) }
            case .back: stepHistory(-1)
            case .forward: stepHistory(1)
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
        case .join(let d, let first):
            guard let id = fid else { return }
            if ws.join(id, d, area: area, first: first) { relayout(); focusWindow(id, warp: true) }
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
            focusWindow(id, warp: false)
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
                let name = "x\(extraSeq)"
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
            // Sending a window to the side workspace makes it when there is none.
            if let id = fid, let n = resolve(t, making: true) { moveWindow(id, to: n, follow: follow) }
        case .focusDisplay(let t):
            if let di = displayTarget(t) {
                focusedDisplay = di
                let target = workspace(displays[di].workspace)
                if let id = target.focused.flatMap({ target.contains($0) ? $0 : nil }) ?? target.allWindows.first {
                    focusWindow(id, warp: true)
                } else {
                    focusEmpty(di)
                }
            }
        case .moveWorkspace(let t):
            if let target = resolveMoveTarget(t, from: ws.name) {
                swapWorkspaces(ws.name, target, showMove: true)
            } else if ws.name != Self.side, t == .next || t == .prev {
                showMoveHUD(around: ws.name)   // at the end: show the wall
            }
        case .moveWorkspaceToDisplay(let t):
            if let di = displayTarget(t) { moveWorkspace(ws.name, to: di) }
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
        case .undo:
            undo(ws, redo: false)
        case .redo:
            undo(ws, redo: true)
        case .find(let q):
            if let id = bestMatch(q) { goTo(id) }
        case .overview:
            overview.toggle()
        case .zoom(let inward):
            if let id = fid { zoom(inward: inward, toward: id) }
        case .retile:
            // Forget the minimum sizes learned from apps; they are measured again.
            windowMins = [:]
            overflowSuspects = [:]
            minimumChecks = [:]
            ghosts = []
            for w in workspaces.values { w.windowMins = [:] }
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
            // Zoomed in by hand: tiles outside the zoom stay out of reach, so the edge of the
            // zoom acts like the edge of the workspace and focus moves on to the next display.
            if !(ws.isZoomedByHand && !ws.isShown(n)) {
                focusWindow(n.activeWindow, warp: true)
                return
            }
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

    // MARK: - Undo

    static func changesLayout(_ c: Command) -> Bool {
        switch c {
        case .swap, .swapStack, .warp, .join, .stack, .unstack, .layout, .toggle, .balance, .rotate, .resize, .grid: return true
        default: return false
        }
    }

    static func undoKind(_ c: Command) -> String {
        if case .resize = c { return "resize" }
        return "command"
    }

    /// Remembers the workspace's tree before a change. Repeated resizes (holding a key) and seam
    /// drags count as one change.
    func recordUndo(_ ws: Workspace, kind: String) {
        if kind != "command", let last = lastUndoRecord, last.name == ws.name, last.kind == kind,
           Date().timeIntervalSince(last.at) < 1.0 {
            lastUndoRecord = (ws.name, kind, Date())
            return
        }
        lastUndoRecord = (ws.name, kind, Date())
        var stack = undoStack[ws.name] ?? []
        let snap = ws.snapshot()
        if stack.last == snap { return }
        stack.append(snap)
        if stack.count > 50 { stack.removeFirst(stack.count - 50) }
        undoStack[ws.name] = stack
        redoStack[ws.name] = []
    }

    func undo(_ ws: Workspace, redo: Bool) {
        var from = (redo ? redoStack : undoStack)[ws.name] ?? []
        guard let snap = from.popLast() else { return }
        var to = (redo ? undoStack : redoStack)[ws.name] ?? []
        to.append(ws.snapshot())
        if redo { redoStack[ws.name] = from; undoStack[ws.name] = to } else { undoStack[ws.name] = from; redoStack[ws.name] = to }
        lastUndoRecord = nil
        ws.restore(snap, area: area(of: ws))
        layout(ws, animated: true)
        if displayShowing(ws.name) != nil, let f = ws.focused { focusWindow(f, warp: false) }
    }

    // MARK: - Focus history and search

    private func focusChanged(_ id: WindowID) {
        // One focus change reaches here up to three times (paw's own focus, the app's
        // focused-window notification, its activation): the hook and event go out once.
        guard id != lastFocusReported else { return }
        lastFocusReported = id
        runHook(config.hooks.windowFocused, ["PAW_WINDOW": "\(id)", "PAW_APP": windows[id]?.app ?? ""])
        if let w = windows[id] {
            publish("windowFocused", ["window": Int(id), "app": w.app, "title": w.title,
                                      "workspace": workspaceOf(id).map { label($0.name) } ?? ""])
        }
        guard !navigatingHistory else { return }
        if historyIndex >= 0, history.indices.contains(historyIndex), history[historyIndex] == id { return }
        if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
        history.removeAll { $0 == id }
        history.append(id)
        if history.count > 100 { history.removeFirst(history.count - 100) }
        historyIndex = history.count - 1
    }

    /// `focus back|forward`: through the windows focused before, across workspaces.
    private func stepHistory(_ step: Int) {
        history.removeAll { windows[$0] == nil }
        historyIndex = min(historyIndex, history.count - 1)
        var i = historyIndex + step
        while history.indices.contains(i), windows[history[i]] == nil { i += step }
        guard history.indices.contains(i) else { return }
        historyIndex = i
        navigatingHistory = true
        goTo(history[i])
        navigatingHistory = false
    }

    /// Shows the window's workspace (if hidden), brings it forward in its stack and focuses it.
    func goTo(_ id: WindowID) {
        guard let ws = workspaceOf(id) else { return }
        ws.focused = id
        ws.activate(id)
        if displayShowing(ws.name) == nil {
            show(ws.name)
        } else {
            layout(ws, animated: false)
        }
        focusWindow(id, warp: true)
    }

    /// The window `find` goes to: app name first, then title, then letters in order; the most
    /// recently focused wins a tie.
    func bestMatch(_ q: String) -> WindowID? {
        let ranked = windows.values.compactMap { w -> (WindowID, Double)? in
            let s = Self.matchScore(q, app: w.app, title: w.title)
            guard s > 0 else { return nil }
            let recent = history.lastIndex(of: w.id).map { Double($0) / 1000 } ?? 0
            return (w.id, s + recent)
        }
        return ranked.max { $0.1 < $1.1 }?.0
    }

    static func matchScore(_ q: String, app: String, title: String) -> Double {
        let q = q.lowercased(), a = app.lowercased(), t = title.lowercased()
        if a == q { return 6 }
        if a.hasPrefix(q) { return 5 }
        if a.contains(q) { return 4 }
        if t.contains(q) { return 3 }
        func subsequence(_ s: String) -> Bool {
            var it = s.makeIterator()
            return q.allSatisfy { c in while let n = it.next() { if n == c { return true } }; return false }
        }
        if subsequence(a) { return 2 }
        if subsequence(t) { return 1 }
        return 0
    }

    // MARK: - Putting windows back

    private func remember(_ id: WindowID, for seconds: TimeInterval? = nil) {
        guard let w = windows[id], let ws = workspaceOf(id) else { return }
        let title = w.title
        ghosts.removeAll { $0.app == w.app && $0.title == title }
        var g = Ghost(app: w.app, title: title, workspace: ws.name, anchor: ws.anchor(of: id), floating: ws.isFloating(id))
        if let seconds { g.expires = Date().addingTimeInterval(seconds) }
        ghosts.insert(g, at: 0)
        if ghosts.count > 40 { ghosts.removeLast(ghosts.count - 40) }
    }

    private func takeGhost(app: String, title: String) -> Ghost? {
        ghosts.removeAll { $0.expires < Date() }
        guard let i = ghosts.firstIndex(where: { $0.app == app && $0.title == title }) ?? ghosts.firstIndex(where: { $0.app == app })
        else { return nil }
        return ghosts.remove(at: i)
    }

    // MARK: - Events

    /// The payload is only built when something listens (`query()` costs a layout per display).
    func publish(_ event: String, _ data: @autoclosure () -> [String: Any]) {
        guard EventBus.shared.hasSubscribers else { return }
        EventBus.shared.publish(event, data())
    }

    private func emitWorkspaceChanged(prev: String) {
        let now = label(focusedWorkspace.name)
        runHook(config.hooks.workspaceChanged, ["PAW_WORKSPACE": now, "PAW_PREV_WORKSPACE": prev])
        publish("workspaceChanged", ["workspace": now, "prev": prev, "display": focusedDisplay + 1, "workspaces": query()])
    }

    /// Everything a new subscriber needs before the first event.
    func snapshotEvent() -> [String: Any] {
        [
            "workspaces": query(),
            "workspace": displays.isEmpty ? "" : label(focusedWorkspace.name),
            "window": focusedID.map { Int($0) } ?? 0,
            "mode": mode ?? "",
            "setup": activeSetup ?? "",
            "displays": displays.enumerated().map { i, d in
                ["index": i + 1, "id": Int(d.id), "name": d.name, "workspace": label(d.workspace), "focused": i == focusedDisplay] as [String: Any]
            },
        ]
    }

    /// `zoomChanged` when how far a workspace is zoomed in changes (sketchybar shows it).
    private func reportZoom(_ ws: Workspace) {
        let z = ws.zoomLevel
        guard reportedZoom[ws.name, default: 0] != z.level else { return }
        reportedZoom[ws.name] = z.level
        publish("zoomChanged", ["workspace": label(ws.name), "level": z.level, "levels": z.levels,
                                "display": displayShowing(ws.name).map { $0 + 1 } ?? 0, "workspaces": query()])
    }

    /// `layoutChanged` once tiles settle: every window's frame on the workspace.
    private func scheduleLayoutEvent(_ name: String) {
        guard EventBus.shared.hasSubscribers else { return }
        layoutEventWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let di = displayShowing(name) else { return }
            let ws = workspace(name)
            let frames = TreeLayout.windowFrames(ws, in: displays[di].area, gap: config.layout.gap)
            let tiles = frames.map { id, f in
                ["window": Int(id), "x": f.minX, "y": f.minY, "w": f.width, "h": f.height] as [String: Any]
            }.sorted { ($0["window"] as! Int) < ($1["window"] as! Int) }
            publish("layoutChanged", ["workspace": label(name), "layout": ws.layout.rawValue, "tiles": tiles])
        }
        layoutEventWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func showHUD(_ name: String, on di: Int) {
        guard config.hud.workspace, displays.indices.contains(di), overview.isOpen == false else { return }
        hud.style = indicators.style
        let apps = workspace(name).allWindows.compactMap { windows[$0]?.app }
        var unique: [String] = []
        for a in apps where !unique.contains(a) { unique.append(a) }
        hud.show(label: label(name), apps: unique, in: displays[di].area, icons: settings.icons, config: config,
                 duration: config.hud.durationMs / 1000)
    }

    // MARK: - Dragging

    /// The workspace and drop target under a point (AX coordinates), for a window being dragged.
    func dropTarget(at p: CGPoint, dragging id: WindowID) -> (ws: Workspace, display: Int, target: DropTarget?)? {
        guard let di = displays.firstIndex(where: { $0.frame.contains(p) }) else { return nil }
        let ws = workspace(displays[di].workspace)
        guard ws.layout.isTiled || ws.layout == .stack else { return (ws, di, nil) }
        let mods = NSEvent.modifierFlags
        let stackKey: NSEvent.ModifierFlags = switch config.mouse.stackModifier {
        case "cmd": .command
        case "ctrl": .control
        case "shift": .shift
        default: .option
        }
        let t = DropZones.target(at: p, in: ws, area: displays[di].area, gap: config.layout.gap, dragging: id,
                                 stack: mods.contains(stackKey))
        return (ws, di, t)
    }

    /// Drops a window (from any workspace) on `target` in `to`, then lays both out.
    func drop(_ id: WindowID, on target: DropTarget?, in to: Workspace) {
        guard let from = workspaceOf(id) else { return }
        recordUndo(from, kind: "drop")
        if from !== to { recordUndo(to, kind: "drop") }
        if from !== to {
            let floating = from.isFloating(id)
            from.remove(id)
            var t = target
            if case .swap(let a)? = t { t = .stack(tile: a) }
            if let t, !floating, to.move(id, to: t, area: area(of: to)) {
            } else {
                to.insert(id, area: area(of: to), floating: floating, slot: nil)
            }
            to.focused = id
            if displayShowing(to.name) == nil, let w = windows[id] { hide(w, from: to) }
            layout(from, animated: true)
            layout(to, animated: true)
        } else if let target {
            to.move(id, to: target, area: area(of: to))
            layout(to, animated: true)
        } else {
            layout(to, animated: true)
        }
        scheduleSave()
    }

    // MARK: - Seams

    struct SeamInfo: Equatable {
        let key: String
        let workspace: String
        let split: ObjectIdentifier
        let index: Int
        let axis: Axis
        let frame: CGRect
        let splitFrame: CGRect
    }

    /// Seams between tiles on every shown workspace (AX coordinates).
    func visibleSeams() -> [SeamInfo] {
        guard config.mouse.seamHandles else { return [] }
        var out: [SeamInfo] = []
        for d in displays {
            let ws = workspace(d.workspace)
            guard ws.layout.isTiled, ws.zoomed == nil else { continue }
            for s in TreeLayout.seams(ws, in: d.area, gap: config.layout.gap) {
                out.append(SeamInfo(key: "\(ws.name):\(s.split.hashValue):\(s.index)", workspace: ws.name, split: s.split,
                                    index: s.index, axis: s.axis, frame: s.frame, splitFrame: s.splitFrame))
            }
        }
        return out
    }

    func seamBegan(_ s: SeamInfo) {
        recordUndo(workspace(s.workspace), kind: "seam")
    }

    /// Moves a seam so it sits at `p` (AX), live.
    func seamDragged(_ s: SeamInfo, to p: CGPoint) {
        let ws = workspace(s.workspace)
        guard let node = ws.splits.first(where: { ObjectIdentifier($0) == s.split }) else { return }
        let r = s.splitFrame
        let gaps = config.layout.gap * Double(node.children.count - 1)
        let pos = s.axis == .horizontal ? (p.x - r.minX - config.layout.gap * (Double(s.index) + 0.5)) / max(1, r.width - gaps)
                                        : (p.y - r.minY - config.layout.gap * (Double(s.index) + 0.5)) / max(1, r.height - gaps)
        ws.setSeam(node, s.index, at: min(1, max(0, pos)), length: s.axis == .horizontal ? r.width : r.height)
        AXQueue.run { layout(ws, animated: false) }
    }

    func seamEnded(_ s: SeamInfo) {
        AXQueue.run { layout(workspace(s.workspace), animated: false) }
        scheduleSave()
    }

    func seamEqualize(_ s: SeamInfo) {
        let ws = workspace(s.workspace)
        guard let node = ws.splits.first(where: { ObjectIdentifier($0) == s.split }) else { return }
        recordUndo(ws, kind: "command")
        ws.equalizeSeam(node, s.index)
        layout(ws, animated: true)
    }

    // MARK: - Overview

    struct OverviewWorkspace {
        let name: String
        let label: String
        let display: Int
        let visible: Bool
        let focused: Bool
        let layout: LayoutKind
        /// Window frames relative to the workspace's whole tree (0…1), tiled ones first.
        let windows: [OverviewWindow]
        /// The whole tree's rect (AX): the display's area, or a larger canvas.
        let area: CGRect
        /// What's on screen when zoomed or on a canvas (relative, like the windows); nil: all of it.
        let camera: CGRect?
    }

    struct OverviewWindow {
        let id: WindowID
        let app: String
        let title: String
        let frame: CGRect
        let floating: Bool
        /// Other windows in its stack, top one first (empty when alone).
        let stack: [WindowID]
        let isActive: Bool
        let focused: Bool
        /// On screen now (not outside a zoom or off a canvas's screen).
        let inCamera: Bool
    }

    /// The workspaces each display owns, in number order, with every window's place.
    func overviewModel() -> [OverviewWorkspace] {
        numbered.map { name in
            let ws = workspace(name)
            let di = displayShowing(name) ?? homeDisplay(name) ?? focusedDisplay
            let screen = displays.indices.contains(di) ? displays[di].area : CGRect(x: 0, y: 0, width: 1440, height: 900)
            let area = TreeLayout.canvas(ws, in: screen, gap: config.layout.gap)
            let frames = TreeLayout.windowFrames(ws, in: screen, gap: config.layout.gap, full: true)
            let shown = ws.shownWindows
            var camera: CGRect?
            let fullFrames = TreeLayout.nodeFrames(ws, in: screen, gap: config.layout.gap, full: true)
            var camRect = ws.shownRoot.flatMap { fullFrames[ObjectIdentifier($0)] }
            if let s = ws.shownRoot, let r = ws.shownRange {
                camRect = s.children[r].compactMap { fullFrames[ObjectIdentifier($0)] }.reduce(CGRect.null) { $0.union($1) }
            }
            if let s = ws.shownRoot, s !== ws.root || area != screen || ws.shownRange != nil, let f = camRect {
                camera = CGRect(x: (f.minX - area.minX) / area.width, y: (f.minY - area.minY) / area.height,
                                width: f.width / area.width, height: f.height / area.height)
            }
            var list: [OverviewWindow] = []
            func rel(_ f: CGRect) -> CGRect {
                CGRect(x: (f.minX - area.minX) / area.width, y: (f.minY - area.minY) / area.height,
                       width: f.width / area.width, height: f.height / area.height)
            }
            for t in ws.tiles {
                for id in t.windows {
                    guard let w = windows[id], let f = frames[id] else { continue }
                    list.append(OverviewWindow(id: id, app: w.app, title: w.title, frame: rel(f), floating: false,
                                               stack: t.windows.count > 1 ? t.windows : [], isActive: t.activeWindow == id,
                                               focused: ws.focused == id, inCamera: shown.contains(id)))
                }
            }
            for id in ws.floating {
                guard let w = windows[id] else { continue }
                let f = w.isHidden ? (w.floatFrame ?? CGRect(x: area.midX - 300, y: area.midY - 200, width: 600, height: 400)) : w.frame
                list.append(OverviewWindow(id: id, app: w.app, title: w.title, frame: rel(f), floating: true, stack: [],
                                           isActive: true, focused: ws.focused == id, inCamera: true))
            }
            return OverviewWorkspace(name: name, label: label(name), display: di, visible: displayShowing(name) != nil,
                                     focused: name == focusedWorkspace.name, layout: ws.layout, windows: list, area: area,
                                     camera: camera)
        }
    }

    var displayCount: Int { displays.count }
    func displayName(_ i: Int) -> String { displays.indices.contains(i) ? displays[i].name : "" }
    var focusedWorkspaceFocus: WindowID? { focusedID }
    var focusedDisplayIndex: Int { focusedDisplay }
    func displayFrame(_ i: Int) -> CGRect? { displays.indices.contains(i) ? displays[i].frame : nil }
    func displayArea(_ i: Int) -> CGRect? { displays.indices.contains(i) ? displays[i].area : nil }
    func workspaceNamed(_ name: String) -> Workspace { workspace(name) }

    /// From the overview: send a window to a workspace without focusing anything.
    func sendWindow(_ id: WindowID, to name: String) {
        guard let from = workspaceOf(id), from.name != name, let w = windows[id] else { return }
        recordUndo(from, kind: "move")
        recordUndo(workspace(name), kind: "move")
        let floating = from.isFloating(id)
        from.remove(id)
        let to = workspace(name)
        to.insert(id, area: area(of: to), floating: floating, slot: presets[name]?.slot(for: w.app, title: w.title))
        to.focused = id
        if displayShowing(name) != nil { layout(to, animated: true) } else { hide(w, from: to) }
        if displayShowing(from.name) != nil { layout(from, animated: true) }
        scheduleSave()
    }

    func newWorkspaceFromOverview() -> String {
        execute(.workspaceNew)
        return focusedWorkspace.name
    }

    // MARK: - Indicators, hooks, state

    /// Indicators, placeholders, seams, edges and the border, redrawn once per run-loop turn
    /// however many changes ask for it (a focus change alone asks three times: paw's own focus,
    /// the app's focused-window notification and its activation).
    func updateIndicators() {
        guard !indicatorsDirty else { return }
        indicatorsDirty = true
        DispatchQueue.main.async { [weak self] in self?.flushIndicators() }
    }

    /// Redraws now if a redraw is waiting.
    func flushIndicators() {
        guard indicatorsDirty else { return }
        indicatorsDirty = false
        refreshIndicators()
    }

    private(set) var indicatorRefreshes = 0

    private func refreshIndicators() {
        if settling { return }
        indicatorRefreshes += 1
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
        // Placeholders for windows too big for their tile.
        var holders: [Placeholders.Item] = []
        for d in displays {
            let ws = workspace(d.workspace)
            guard config.layout.placeholders, !windowMins.isEmpty, ws.layout.isTiled else { continue }
            let frames = TreeLayout.windowFrames(ws, in: d.area, gap: config.layout.gap)
            for t in ws.tiles {
                guard let id = t.activeWindow, let m = windowMins[id], let r = frames[id], let w = windows[id],
                      m.width > r.width + 2 || m.height > r.height + 2 else { continue }
                holders.append(.init(id: id, app: w.app, title: w.title, frame: r, focused: ws.focused == id && focusedWorkspace === ws))
            }
        }
        updateBorder(cramped: Set(holders.map(\.id)))
        placeholders.apply(holders, style: indicators.style, focusFollowsMouse: config.focus.focusFollowsMouse, focusBorder: border, actions: .init(
            focus: { [weak self] id in self?.focusWindow(id, warp: false) },
            zoom: { [weak self] id in self?.makeRoom(for: id) },
            drag: { [weak self] id, p in self?.placeholderDragged(id, to: p) },
            drop: { [weak self] id, p in self?.placeholderDropped(id, at: p) }))
        seams.update()
        updateEdges()
    }

    /// The edge islands: on each display, the workspaces `workspace prev|next` would show there.
    private func updateEdges() {
        guard config.hud.edges else { edges.hideAll(); return }
        let names = numbered
        var markers: [EdgeMarkers.Marker] = []
        for (di, d) in displays.enumerated() {
            guard let i = names.firstIndex(of: d.workspace), names.count > 1 else { continue }
            for step in [-1, 1] {
                var j = i + step
                if !names.indices.contains(j) {
                    guard config.focus.wrapWorkspaces else { continue }
                    j = (j + names.count) % names.count
                }
                let n = names[j]
                // Only a workspace that would come up on this very display.
                guard n != d.workspace, displayShowing(n) == nil, (homeDisplay(n) ?? focusedDisplay) == di else { continue }
                var apps: [String] = []
                for a in workspace(n).allWindows.compactMap({ windows[$0]?.app }) where !apps.contains(a) { apps.append(a) }
                markers.append(.init(display: d.id, left: step < 0, name: n, label: label(n), apps: apps, area: d.area, screen: d.frame))
            }
        }
        edges.style = indicators.style
        edges.apply(markers, icons: settings.icons, config: config)
    }

    private func runHook(_ cmd: String, _ env: [String: String]) {
        guard !cmd.isEmpty else { return }
        Shell.run(cmd, env: env)
    }

    /// Runs hooks.windowsChanged shortly after the workspace → apps picture changes.
    private func scheduleWindowsHook() {
        guard !config.hooks.windowsChanged.isEmpty || EventBus.shared.hasSubscribers else { return }
        windowsHookWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let sig = orderedNames.map { name in
                name + ":" + self.workspace(name).allWindows.compactMap { self.windows[$0]?.app }.sorted().joined(separator: ",")
            }.joined(separator: "|")
            guard sig != lastWindowsSignature else { return }
            lastWindowsSignature = sig
            runHook(config.hooks.windowsChanged, [:])
            publish("windowsChanged", ["workspaces": query()])
        }
        windowsHookWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - The side workspace

    /// Where windows of unplugged displays wait to be put somewhere ("+N" in the bar, first).
    static let side = "side"

    /// Workspaces of displays that went away: windows a preset places go there, the rest to the
    /// side workspace; workspaces that only existed for that display go.
    private func setAside(_ names: Set<String>) {
        var moved = false
        for name in names.sorted(by: Self.nameOrder) where name != Self.side {
            guard let ws = workspaces[name] else { continue }
            // Still on screen or pinned in the arrangement now: it stays as it is.
            if displayShowing(name) != nil || homeDisplay(name) != nil { continue }
            for id in ws.allWindows {
                guard let w = windows[id] else { continue }
                if let home = presets.first(where: { $0.value.slot(for: w.app, title: w.title) != nil })?.key, home != name {
                    moveQuietly(id, from: ws, to: workspace(home))
                } else {
                    moveQuietly(id, from: ws, to: workspace(Self.side))
                }
                moved = true
            }
            if ws.isEmpty, !isPermanent(name) {
                workspaces[name] = nil
                extraPins[name] = nil
            }
        }
        if moved {
            for name in presets.keys { if displayShowing(name) != nil { layout(workspace(name), animated: false) } }
            Log.app.info("set aside: \(self.workspaces[Self.side]?.allWindows.count ?? 0) windows on the side")
        }
        dropEmptySide()
    }

    /// Workspaces that always exist: 1…layout.workspaces and the presets in effect.
    private func isPermanent(_ name: String) -> Bool {
        if presets[name] != nil { return true }
        if let n = Int(name), (1...max(1, config.layout.workspaces)).contains(n) { return true }
        return false
    }

    /// Moves a window between workspaces without focusing anything; out of sight unless shown.
    private func moveQuietly(_ id: WindowID, from: Workspace, to: Workspace) {
        guard let w = windows[id] else { return }
        let floating = from.isFloating(id)
        from.remove(id)
        to.insert(id, area: area(of: to), floating: floating, slot: presets[to.name]?.slot(for: w.app, title: w.title))
        if displayShowing(to.name) == nil { hide(w, from: to) }
    }

    /// The side workspace goes once everything on it has a place (and it isn't on screen).
    private func dropEmptySide() {
        guard let s = workspaces[Self.side], s.isEmpty else { return }
        if displayShowing(Self.side) != nil {
            // Sorted while looking at it: back to where you were, then it goes.
            guard !droppingSide else { return }
            droppingSide = true
            let back = lastWorkspace.flatMap { $0 != Self.side && workspaces[$0] != nil ? $0 : nil } ?? numberedWorkspaces.first ?? "1"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { droppingSide = false }
                guard workspaces[Self.side]?.isEmpty == true, displayShowing(Self.side) != nil else { return }
                show(back)
                if displayShowing(Self.side) == nil { workspaces[Self.side] = nil }
                publish("windowsChanged", ["workspaces": query()])
                runHook(config.hooks.windowsChanged, [:])
            }
            return
        }
        workspaces[Self.side] = nil
    }

    /// paw 0.1 named extra workspaces "+1", "+2"…; without their display they are set aside.
    private func migrateOldExtras() {
        let old = workspaces.keys.filter { $0.hasPrefix("+") }
        guard !old.isEmpty else { return }
        for name in old {
            guard let ws = workspaces[name] else { continue }
            for id in ws.allWindows { moveQuietly(id, from: ws, to: workspace(Self.side)) }
            if displayShowing(name) == nil { workspaces[name] = nil }
        }
    }

    private func scheduleSave() {
        dropEmptySide()
        scheduleWindowsHook()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveState() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func saveState() {
        do {
            var map: [WindowID: String] = [:]
            var trees: [String: WorkspaceSnapshot] = [:]
            for (name, ws) in workspaces where !ws.isEmpty {
                for id in ws.allWindows { map[id] = name }
                trees[name] = ws.snapshot()
            }
            StateFile.save(map, trees: trees)
        }
    }

    /// Workspaces for `paw query`.
    func query() -> [[String: Any]] {
        // Labels once for all (each `label` call works out the whole order again).
        let core = numberedWorkspaces
        let byNumber = extraPins.isEmpty == false || orderedNames.contains(where: { homeDisplay($0) != nil })
        let index = Dictionary(core.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func label(_ name: String) -> String {
            if name == Self.side { return "+\(workspaces[name]?.allWindows.count ?? 0)" }
            return byNumber ? index[name].map { "\($0 + 1)" } ?? name : name
        }
        let focusedName = focusedWorkspace.name
        // sketchybar's arrangement-id for a display: its 1-based position among the window
        // server's managed displays (NSScreen.screens and CGGetActiveDisplayList use other
        // orders). One window-server call for all, not one per workspace.
        let uuids = SkyLight.managedDisplayUUIDs()
        var arrangement: [CGDirectDisplayID: Int] = [:]
        for d in displays {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(d.id)?.takeRetainedValue(),
                  let text = CFUUIDCreateString(nil, uuid) as String? else { continue }
            arrangement[d.id] = uuids.firstIndex { $0.caseInsensitiveCompare(text) == .orderedSame }.map { $0 + 1 } ?? 0
        }
        let names = (workspaces[Self.side] != nil ? [Self.side] : []) + core
        return names.map { name -> [String: Any] in
            let ws = workspace(name)
            let pinned = homeDisplay(name)
            let showing = displayShowing(name)
            let home = pinned ?? showing
            let shown = showing.map { TreeLayout.windowFrames(ws, in: displays[$0].area, gap: config.layout.gap) } ?? [:]
            return ["name": label(name), "id": name, "visible": showing != nil, "focused": name == focusedName,
                    "displayID": home.map { Int(displays[$0].id) } ?? 0, "pinned": pinned != nil,
                    "arrangement": home.flatMap { arrangement[displays[$0].id] } ?? 0,
                    "display": showing.map { $0 + 1 } ?? 0, "layout": ws.layout.rawValue,
                    "zoom": ws.zoomLevel.level, "zoomLevels": ws.zoomLevel.levels,
                    "windows": ws.allWindows.compactMap { id -> [String: Any]? in
                        guard let w = windows[id] else { return nil }
                        let color = AppColors.shared.color(for: w.app, icons: config.icons)?.description ?? ""
                        let f = shown[id] ?? w.frame
                        return ["id": Int(id), "app": w.app, "title": w.title, "color": color, "floating": ws.isFloating(id),
                                "frame": ["x": f.minX, "y": f.minY, "w": f.width, "h": f.height], "onScreen": !w.isHidden,
                                "stacked": (ws.tile(of: id)?.windows.count ?? 0) > 1, "focused": ws.focused == id]
                    }]
        }
    }
}

/// Which workspace each window was on and every workspace's tree, so a restart (or a crash)
/// finds parked windows again and puts tiles back as they were.
enum StateFile {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: AppPaths.bundleID).appending(path: "state.json")
    }

    struct State {
        var windows: [WindowID: String] = [:]
        var trees: [String: WorkspaceSnapshot] = [:]
    }

    private struct File: Codable {
        var version = 2
        var savedAt = Date().timeIntervalSince1970
        var windows: [String: String]
        var trees: [String: WorkspaceSnapshot]
    }

    static func load() -> State {
        guard let data = try? Data(contentsOf: url) else { return State() }
        var out = State()
        if let f = try? JSONDecoder().decode(File.self, from: data) {
            // Older than half a day (paw quit and the windows lived on without it): start fresh.
            guard Date().timeIntervalSince1970 - f.savedAt < 12 * 3600 else { return State() }
            for (k, v) in f.windows { if let id = WindowID(k) { out.windows[id] = v } }
            out.trees = f.trees
        } else if let d = try? JSONDecoder().decode([String: String].self, from: data) {
            // paw 0.1: only the workspace of each window.
            for (k, v) in d { if let id = WindowID(k) { out.windows[id] = v } }
        }
        return out
    }

    static func save(_ map: [WindowID: String], trees: [String: WorkspaceSnapshot]) {
        var d: [String: String] = [:]
        for (k, v) in map { d["\(k)"] = v }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(File(windows: d, trees: trees)).write(to: url, options: .atomic)
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}

enum Shell {
    /// Hooks and `exec` start from here, in order, never on the main thread: starting a process
    /// copies the environment and waits on fork.
    private static let queue = DispatchQueue(label: "paw.shell", qos: .userInitiated)

    static func run(_ cmd: String, env: [String: String]) {
        queue.async { start(cmd, env: env) }
    }

    private static func start(_ cmd: String, env: [String: String]) {
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


/// The newest focus request: focus calls run in order on their own queue, and one waiting behind
/// a slow app is dropped when a newer one came in meanwhile.
final class FocusTicket: @unchecked Sendable {
    static let shared = FocusTicket()
    private let lock = NSLock()
    private var latest = 0

    func issue() -> Int { lock.withLock { latest += 1; return latest } }
    func isLatest(_ t: Int) -> Bool { lock.withLock { t == latest } }
}
