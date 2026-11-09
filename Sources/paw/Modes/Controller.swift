import AppKit
import Carbon.HIToolbox
import PawCore

/// A mode while it is open: it gets every key through the tap.
protocol Mode: AnyObject {
    var kind: Controller.Kind { get }
    /// Return true to swallow the key.
    func handle(_ key: KeyTap.Key) -> Bool
    func flagsChanged(_ flags: CGEventFlags)
    func tearDown()
}

extension Mode {
    func flagsChanged(_ flags: CGEventFlags) {}
}

/// Owns the overlay, the key tap and the collector, and runs one mode at a time.
final class Controller {
    enum Kind: String, CaseIterable { case hint, search, scroll }

    let settings: Settings
    let overlay = Overlay()
    let tap = KeyTap()
    let collector = Collector()
    private(set) var style: Style
    private var mode: Mode?
    /// After a click: the key and point, so typing that key again double-clicks.
    private var repeatWindow: (char: Character, element: Element, until: Date)?
    private var lastNotice: DispatchWorkItem?
    /// A hotkey the tap already handled; the Carbon handler may report the same press too.
    private var tapHotkey: (kind: Kind, at: Date)?

    init(settings: Settings) {
        self.settings = settings
        style = Style(settings.config.appearance)
        tap.onKey = { [weak self] key in self?.route(key) ?? false }
        tap.onFlags = { [weak self] flags in self?.mode?.flagsChanged(flags) }
        tap.onMouseDown = { [weak self] in self?.dismiss() }
    }

    var config: PawConfig { settings.config }

    func configChanged() {
        style = Style(settings.config.appearance)
    }

    func screensChanged() {
        dismiss()
        overlay.rebuild()
    }

    // MARK: - Opening and closing

    func toggle(_ kind: Kind) {
        if let t = tapHotkey, t.kind == kind, Date().timeIntervalSince(t.at) < 0.3 { return }
        repeatWindow = nil
        if let mode, mode.kind == kind { dismiss(); return }
        dismiss()
        guard AX.isTrusted else {
            AX.requestTrust()
            notice("Accessibility permission needed", color: style.colors.bad)
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if isExcluded(front) { return }
        guard tap.enable() else {
            notice("Can't read keys: check Accessibility", color: style.colors.bad)
            return
        }
        let target = Target(app: front, glyph: settings.icons.glyph(for: front.localizedName ?? ""))
        switch kind {
        case .hint: mode = HintMode(controller: self, target: target)
        case .search: mode = SearchMode(controller: self, target: target)
        case .scroll: mode = ScrollMode(controller: self, target: target)
        }
    }

    func dismiss() {
        lastNotice?.cancel()
        mode?.tearDown()
        mode = nil
        overlay.hide()
        if repeatWindow == nil { tap.disable() }
    }

    /// Closes the mode and clicks; the tap stays on briefly so the same key again double-clicks.
    func click(_ e: Element, kind: Clicker.Kind, key: Character?) {
        mode?.tearDown()
        mode = nil
        overlay.hide()
        Clicker.perform(kind, on: e, restoreCursor: config.hint.restoreCursor)
        let ms = config.hint.doubleTapMs
        if kind == .primary, let key, ms > 0 {
            let until = Date().addingTimeInterval(Double(ms) / 1000)
            repeatWindow = (key, e, until)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms + 10)) { [weak self] in
                guard let self, let w = repeatWindow, w.until <= Date() else { return }
                repeatWindow = nil
                if mode == nil { tap.disable() }
            }
        } else {
            tap.disable()
        }
    }

    private func route(_ key: KeyTap.Key) -> Bool {
        if let w = repeatWindow, mode == nil {
            if key.down, key.char == w.char, Date() < w.until {
                repeatWindow = nil
                tap.disable()
                Clicker.perform(.double, on: w.element, restoreCursor: config.hint.restoreCursor)
                return true
            }
            if !key.down, key.char == w.char { return true }
            repeatWindow = nil
            tap.disable()
            return false
        }
        guard let mode else { return false }
        if key.down, let other = hotkeyKind(key) {
            if other == mode.kind { dismiss() } else { toggle(other) }
            tapHotkey = (other, Date())
            return true
        }
        if key.down, key.code == UInt16(kVK_Escape) {
            dismiss()
            return true
        }
        return mode.handle(key)
    }

    /// Which mode's hotkey a key press is, so pressing it again while open closes or switches.
    private func hotkeyKind(_ key: KeyTap.Key) -> Kind? {
        var mods: UInt32 = 0
        if key.command { mods |= UInt32(cmdKey) }
        if key.shift { mods |= UInt32(shiftKey) }
        if key.option { mods |= UInt32(optionKey) }
        if key.control { mods |= UInt32(controlKey) }
        guard mods != 0 else { return nil }
        let pairs: [(Kind, String)] = [(.hint, config.hint.hotkey), (.search, config.search.hotkey), (.scroll, config.scroll.hotkey)]
        for (kind, text) in pairs {
            if let spec = HotkeySpec.parse(text), spec.keyCode == UInt32(key.code), spec.modifiers == mods { return kind }
        }
        return nil
    }

    private func isExcluded(_ app: NSRunningApplication) -> Bool {
        let ids = [app.bundleIdentifier, app.localizedName].compactMap { $0?.lowercased() }
        return config.excludedApps.contains { ids.contains($0.lowercased()) }
    }

    // MARK: - Shared helpers for modes

    struct Target {
        let app: NSRunningApplication
        let glyph: String
        var name: String { app.localizedName ?? app.bundleIdentifier ?? "app" }
    }

    func collectorOptions(_ purpose: Collector.Purpose) -> Collector.Options {
        var o = Collector.Options()
        o.purpose = purpose
        o.maxElements = max(1, config.hint.maxElements)
        o.timeout = Float(max(0.05, min(2, config.axTimeout)))
        o.enhancedUI = config.hint.enhancedUI
        o.screens = overlay.screens.map(\.ax)
        if purpose == .hint {
            o.menuBar = SystemUI.wantsMenuBar(config.hint.menuBar)
            if SystemUI.wantsDock(config.hint.dock) {
                o.dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            }
            if config.hint.menuBarExtras == .on {
                o.extrasPIDs = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
            }
        } else if purpose == .search {
            o.menuBar = SystemUI.wantsMenuBar(config.hint.menuBar)
        }
        return o
    }

    /// The island at the top: app icon, app name, mode and a note.
    func modeIsland(_ target: Target, mode: String, note: String?, noteColor: ARGB? = nil, screen: Int) -> CALayer {
        let c = style.colors
        var segs: [Island.Segment] = []
        if let g = style.appGlyph(target.glyph) { segs.append(.init(text: g, gapAfter: 6)) }
        segs.append(.init(text: style.text(target.name, c.fg, font: style.islandBold), gapAfter: 10))
        segs.append(.init(text: style.text(mode, c.muted), gapAfter: 8))
        if let note { segs.append(.init(text: style.text(note, noteColor ?? c.dim))) }
        return Island.make(segs, style: style, scale: overlay.screens[safe: screen]?.scale ?? 2)
    }

    /// A short message in an island that goes away by itself.
    func notice(_ text: String, color: ARGB) {
        let i = overlay.pointerScreen
        overlay.clear()
        let island = Island.make([.init(text: style.text(text, color, font: style.islandBold))], style: style,
                                 scale: overlay.screens[safe: i]?.scale ?? 2)
        overlay.addIsland(island, top: style.a.islandTop, screen: i)
        overlay.show()
        let work = DispatchWorkItem { [weak self] in
            guard let self, mode == nil else { return }
            overlay.hide()
        }
        lastNotice = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

/// Whether macOS shows the menu bar and Dock (labels on hidden ones would float over nothing).
enum SystemUI {
    static func wantsMenuBar(_ t: PawConfig.Toggle) -> Bool {
        switch t {
        case .on: true
        case .off: false
        case .auto: !(CFPreferencesCopyAppValue("_HIHideMenuBar" as CFString, kCFPreferencesAnyApplication) as? Bool ?? false)
        }
    }

    static func wantsDock(_ t: PawConfig.Toggle) -> Bool {
        switch t {
        case .on: true
        case .off: false
        case .auto: !(CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
