import AppKit
import ApplicationServices
import PawCore

/// Finds what to label in the frontmost app: the focused window (or an open menu), its menu
/// bar, the Dock and status items. Runs on its own queue with a short messaging timeout, so a
/// hung app costs at most the timeout and never blocks the main thread.
final class Collector {
    enum Purpose { case hint, search, scroll }

    struct Options {
        var purpose = Purpose.hint
        var menuBar = false
        var dockPID: pid_t?
        var extrasPIDs: [pid_t] = []
        var maxElements = 800
        var maxNodes = 6000
        var timeout: Float = 0.25
        var enhancedUI = true
        /// AX frames of every screen.
        var screens: [CGRect] = []
    }

    struct Result {
        var elements: [Element] = []
        var scrollAreas: [Element] = []
        var windowFrame: CGRect?
        var nodes = 0
        var ms = 0.0
        var menuOpen = false
    }

    static let queue = DispatchQueue(label: "dev.paw.ax", qos: .userInteractive)
    private static let side = DispatchQueue(label: "dev.paw.ax.side", qos: .userInteractive, attributes: .concurrent)

    /// Apps already switched into full accessibility (only touched on `queue`).
    private var prepared = Set<pid_t>()

    func collect(pid: pid_t, bundleID: String?, options: Options, completion: @escaping (Result) -> Void) {
        Self.queue.async { [self] in
            let r = run(pid: pid, bundleID: bundleID, options: options)
            DispatchQueue.main.async { completion(r) }
        }
    }

    /// Synchronous; call on `queue` (or from the CLI's dump).
    func run(pid: pid_t, bundleID: String?, options o: Options) -> Result {
        let start = DispatchTime.now().uptimeNanoseconds
        AXUIElementSetMessagingTimeout(AXUIElement.systemWide, o.timeout)
        let app = AXUIElement.app(pid, timeout: o.timeout)
        let fresh = prepare(app, pid: pid, bundleID: bundleID, enhancedUI: o.enhancedUI)

        // Dock and status items live in other processes: collect them alongside.
        let group = DispatchGroup()
        let lock = NSLock()
        var side: [Element] = []
        if o.purpose != .scroll {
            if let dock = o.dockPID {
                group.enter()
                Self.side.async {
                    let items = Self.dockItems(pid: dock, timeout: o.timeout)
                    lock.withLock { side += items }
                    group.leave()
                }
            }
            if !o.extrasPIDs.isEmpty {
                group.enter()
                Self.side.async {
                    let items = Self.extras(pids: o.extrasPIDs)
                    lock.withLock { side += items }
                    group.leave()
                }
            }
        }

        var result = Result()
        var walker = Walker(options: o)
        if o.purpose != .scroll, let menu = Self.openMenu(app) {
            result.menuOpen = true
            walker.walkMenu(menu)
        } else {
            let window = app.element(kAXFocusedWindowAttribute) ?? app.element(kAXMainWindowAttribute)
                ?? app.elements(kAXWindowsAttribute).first
            if let window, let wf = window.frame {
                result.windowFrame = wf
                walker.walk(window, clip: wf, source: .window)
                if fresh, walker.out.count < 3, o.purpose != .scroll {
                    // Electron/Chromium build their tree after the first request.
                    usleep(150_000)
                    walker = Walker(options: o)
                    walker.walk(window, clip: wf, source: .window)
                }
            }
            if o.menuBar, o.purpose != .scroll { walker.walkMenuBar(app) }
        }
        _ = group.wait(timeout: .now() + .milliseconds(Int(o.timeout * 1000) + 150))
        let extra = lock.withLock { side }

        let onScreen: (CGRect) -> Bool = { f in o.screens.isEmpty || o.screens.contains { $0.intersects(f) } }
        var all = (walker.out + extra).filter { onScreen($0.frame) }
        // Controls first so they win over rows and groups when two labels would collide.
        all = all.enumerated().sorted {
            let a = ElementRules.priority(role: $0.element.role), b = ElementRules.priority(role: $1.element.role)
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
        let keep = ScreenGeometry.dedupe(all.map(\.frame))
        var elements = keep.prefix(o.maxElements).map { all[$0] }
        // Reading order: top to bottom in 10 pt bands, then left to right.
        elements.sort {
            let ya = ($0.frame.minY / 10).rounded(.down), yb = ($1.frame.minY / 10).rounded(.down)
            return ya != yb ? ya < yb : $0.frame.minX < $1.frame.minX
        }
        result.elements = elements
        result.scrollAreas = walker.scrollAreas.filter { onScreen($0.frame) }
        result.nodes = walker.nodes
        result.ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        return result
    }

    /// Electron needs AXManualAccessibility, Chromium AXEnhancedUserInterface, before their
    /// trees have content. True when this is the first time for the process.
    private func prepare(_ app: AXUIElement, pid: pid_t, bundleID: String?, enhancedUI: Bool) -> Bool {
        guard !prepared.contains(pid) else { return false }
        prepared.insert(pid)
        let manual = app.set("AXManualAccessibility", kCFBooleanTrue)
        var enhanced = false
        if enhancedUI, let bundleID, ElementRules.chromiumBundleIDs.contains(bundleID) {
            enhanced = app.set("AXEnhancedUserInterface", kCFBooleanTrue)
        }
        if manual || enhanced { Log.ax.info("enabled accessibility for \(bundleID ?? "?", privacy: .public)") }
        return manual || enhanced
    }

    /// A context menu (child of the app) or a menu bar menu that is open right now.
    static func openMenu(_ app: AXUIElement) -> AXUIElement? {
        for c in app.elements(kAXChildrenAttribute) where c.string(kAXRoleAttribute) == "AXMenu" { return c }
        guard let bar = app.element(kAXMenuBarAttribute) else { return nil }
        for item in bar.elements(kAXChildrenAttribute) where item.bool(kAXSelectedAttribute) == true {
            if let menu = item.elements(kAXChildrenAttribute).first(where: { $0.string(kAXRoleAttribute) == "AXMenu" }) {
                return menu
            }
        }
        return nil
    }

    static func dockItems(pid: pid_t, timeout: Float) -> [Element] {
        let dock = AXUIElement.app(pid, timeout: timeout)
        var out: [Element] = []
        for list in dock.elements(kAXChildrenAttribute) {
            for item in list.elements(kAXChildrenAttribute) {
                let v = item.values([kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute])
                guard let role = v[0] as? String, role == "AXDockItem", let f = AX.frame(position: v[2], size: v[3]) else { continue }
                // Separators have no title.
                guard let title = AX.text(v[4]) else { continue }
                out.append(Element(ref: item, frame: f, role: role, subrole: v[1] as? String, title: title,
                                   source: .dock, clip: f, canPress: true))
            }
        }
        return out
    }

    static func extras(pids: [pid_t]) -> [Element] {
        let lock = NSLock()
        var out: [Element] = []
        DispatchQueue.concurrentPerform(iterations: pids.count) { i in
            let app = AXUIElement.app(pids[i], timeout: 0.1)
            guard let bar = app.element("AXExtrasMenuBar") else { return }
            var found: [Element] = []
            for item in bar.elements(kAXChildrenAttribute) {
                let v = item.values([kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXDescriptionAttribute])
                guard let role = v[0] as? String, let f = AX.frame(position: v[1], size: v[2]), f.width > 0 else { continue }
                found.append(Element(ref: item, frame: f, role: role, subrole: nil, title: AX.text(v[3]), desc: AX.text(v[4]),
                                     source: .extras, clip: f, canPress: true))
            }
            lock.withLock { out += found }
        }
        return out
    }
}

/// Depth-first walk over one subtree, in document order, pruning what is off screen.
struct Walker {
    let options: Collector.Options
    var out: [Element] = []
    var scrollAreas: [Element] = []
    var nodes = 0

    init(options: Collector.Options) { self.options = options }

    static let webSearchKeys = [
        "AXButtonSearchKey", "AXLinkSearchKey", "AXControlSearchKey", "AXTextFieldSearchKey",
        "AXCheckBoxSearchKey", "AXRadioGroupSearchKey", "AXGraphicSearchKey",
    ]

    private var wantsText: Bool { options.purpose == .search }

    private var attrs: [String] {
        let base = [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                    kAXTitleAttribute, kAXDescriptionAttribute, kAXEnabledAttribute]
        return wantsText ? base + [kAXRoleDescriptionAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute] : base
    }

    /// The walk also reads children in the same round trip (one IPC per node).
    private var walkAttrs: [String] { attrs + [kAXChildrenAttribute]
    }

    private static let valueRoles: Set<String> = ["AXTextField", "AXComboBox", "AXSearchField", "AXPopUpButton", "AXMenuButton", "AXStaticText"]

    private var full: Bool { nodes >= options.maxNodes || out.count >= options.maxElements * 2 }

    mutating func walk(_ root: AXUIElement, clip: CGRect, source: Element.Source) {
        let attrs = walkAttrs
        var stack: [(node: AXUIElement, parentRole: String?, parentClickable: Bool, clip: CGRect, depth: Int)] =
            [(root, nil, false, clip, 0)]
        while let item = stack.popLast() {
            let (node, parentRole, parentClickable, clip, depth) = item
            if full { break }
            nodes += 1
            let v = node.values(attrs)
            guard let role = v[0] as? String else { continue }
            let subrole = v[1] as? String
            let frame = AX.frame(position: v[2], size: v[3])
            if let f = frame, f.width > 0, f.height > 0, !f.intersects(clip) { continue }
            var childClip = clip
            if role == "AXScrollArea", let f = frame, f.width > 0, f.height > 0 {
                childClip = clip.intersection(f)
                if options.purpose == .scroll, childClip.width >= 60, childClip.height >= 60 {
                    scrollAreas.append(Element(ref: node, frame: childClip, role: role, subrole: subrole,
                                               title: AX.text(v[4]), desc: AX.text(v[5]), source: source, clip: childClip))
                }
            }

            if options.purpose == .scroll {
                if role == "AXWebArea" || ElementRules.leafRoles.contains(role) || depth > 40 { continue }
            } else {
                if role == "AXWebArea", let hits = node.search(keys: Self.webSearchKeys, limit: options.maxElements), !hits.isEmpty {
                    for h in hits where !full { addWebResult(h, clip: childClip, source: source) }
                    continue
                }
                let enabled = (v[6] as? NSNumber)?.boolValue ?? true
                if enabled, let f = frame, f.width > 1, f.height > 1, f.intersects(clip) {
                    var actions: [String]? = nil
                    if !parentClickable, ElementRules.maybePressableRoles.contains(role),
                       role != "AXGroup" || (f.width <= 480 && f.height <= 160) {
                        actions = node.actions
                    }
                    if ElementRules.isClickable(role: role, subrole: subrole, actions: actions, parentRole: parentRole) {
                        add(node, role: role, subrole: subrole, frame: f, values: v, clip: clip, source: source,
                            canPress: actions.map { $0.contains("AXPress") })
                    }
                }
                if ElementRules.leafRoles.contains(role) || depth > 60 { continue }
            }

            let all = (v.last as? [AnyObject])?.compactMap(AX.element) ?? []
            var children = all
            // Long tables and lists: only what is on screen.
            if all.count > 40 {
                switch role {
                case "AXTable", "AXOutline":
                    let rows = node.elements(kAXVisibleRowsAttribute)
                    if !rows.isEmpty { children = [node.element(kAXHeaderAttribute)].compactMap { $0 } + rows }
                case "AXList", "AXBrowser", "AXGrid":
                    let visible = node.elements(kAXVisibleChildrenAttribute)
                    if !visible.isEmpty { children = visible }
                default:
                    break
                }
            }
            let clickable = ElementRules.clickableRoles.contains(role)
            for c in children.reversed() { stack.append((c, role, clickable, childClip, depth + 1)) }
        }
    }

    private mutating func add(_ node: AXUIElement, role: String, subrole: String?, frame: CGRect, values v: [AnyObject?],
                              clip: CGRect, source: Element.Source, canPress: Bool?) {
        var e = Element(ref: node, frame: frame, role: role, subrole: subrole, title: AX.text(v[4]), desc: AX.text(v[5]),
                        source: source, clip: clip, canPress: canPress)
        if wantsText, v.count >= 10 {
            e.roleDescription = AX.text(v[7])
            e.placeholder = AX.text(v[8])
            if e.desc == nil { e.desc = AX.text(v[9]) }
            if Self.valueRoles.contains(role) { e.value = AX.text(node.value(kAXValueAttribute)) }
        }
        out.append(e)
    }

    private mutating func addWebResult(_ node: AXUIElement, clip: CGRect, source: Element.Source) {
        nodes += 1
        let v = node.values(attrs)
        guard let role = v[0] as? String, let f = AX.frame(position: v[2], size: v[3]), f.width > 1, f.height > 1,
              f.intersects(clip), !ElementRules.ignoredRoles.contains(role) else { return }
        if (v[6] as? NSNumber)?.boolValue == false { return }
        var canPress: Bool? = nil
        if role == "AXImage" || role == "AXGroup" {
            let a = node.actions
            canPress = a.contains("AXPress")
            if canPress != true { return }
        }
        add(node, role: role, subrole: v[1] as? String, frame: f, values: v, clip: clip, source: source, canPress: canPress)
    }

    /// An open menu: its enabled items, and the items of an open submenu.
    mutating func walkMenu(_ menu: AXUIElement, depth: Int = 0) {
        guard depth < 6 else { return }
        for item in menu.elements(kAXChildrenAttribute) {
            nodes += 1
            let v = item.values(attrs + [kAXSelectedAttribute])
            guard let role = v[0] as? String, role == "AXMenuItem", let f = AX.frame(position: v[2], size: v[3]),
                  f.width > 0, f.height > 0 else { continue }
            if (v[6] as? NSNumber)?.boolValue != false {
                add(item, role: role, subrole: v[1] as? String, frame: f, values: v, clip: f, source: .menu, canPress: true)
            }
            if (v.last as? NSNumber)?.boolValue == true,
               let sub = item.elements(kAXChildrenAttribute).first(where: { $0.string(kAXRoleAttribute) == "AXMenu" }) {
                walkMenu(sub, depth: depth + 1)
            }
        }
    }

    mutating func walkMenuBar(_ app: AXUIElement) {
        guard let bar = app.element(kAXMenuBarAttribute) else { return }
        for item in bar.elements(kAXChildrenAttribute) {
            nodes += 1
            let v = item.values(attrs)
            guard let role = v[0] as? String, role == "AXMenuBarItem", let f = AX.frame(position: v[2], size: v[3]),
                  f.width > 0 else { continue }
            add(item, role: role, subrole: v[1] as? String, frame: f, values: v, clip: f, source: .menuBar, canPress: true)
        }
    }
}
