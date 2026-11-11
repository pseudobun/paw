import AppKit
import PawCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var wm: WindowManager!
    private var signalSources: [DispatchSourceSignal] = []
    private var trustTimer: Timer?
    private var statusItem: NSStatusItem?
    private var ipc: IPC.Server?
    private var ipcRetry: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAlreadyRunning() {
            Log.app.info("another paw is running; exiting")
            exit(0)
        }
        installSignalHandlers()
        Theme.registerFonts() // bundled fonts, for themes' indicators and the settings window
        settings.start()
        wm = WindowManager(settings: settings)
        settings.onChange = { [weak self] in self?.apply() }
        let server = IPC.Server(handler: { [weak self] text in self?.command(text) ?? ["error": "paw is shutting down"] },
                                subscribe: { [weak self] fd, text in
            guard let self, let wm = self.wm else { close(fd); return }
            EventBus.shared.add(fd: fd, request: text, snapshot: wm.snapshotEvent())
        })
        startIPC(server)
        // Window management needs Accessibility; wait for the grant instead of quitting.
        if AX.isTrusted {
            wm.start()
        } else {
            // Right after login (or a fresh grant) Accessibility can read false for a moment:
            // ask only if it still does a little later, so a granted paw never opens the prompt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Self.askForTrustOnce() }
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard AX.isTrusted else { return }
                t.invalidate()
                self?.wm.start()
            }
        }
        updateLoginItem(settings.config.openAtLogin)
        MainActor.assumeIsolated {
            Updater.shared.start(settings.config.updates)
            Updater.shared.onResult = { [weak self] state in self?.showUpdateResult(state) }
        }
        setUpStatusItem()
        Log.app.info("paw \(AppPaths.version, privacy: .public) ready, trusted: \(AX.isTrusted)")
    }

    /// macOS's Accessibility prompt, at most once per build and only while access is missing:
    /// reopening paw never asks again (Settings → Permissions has the button).
    static func askForTrustOnce(defaults: UserDefaults = .standard, build: String = AppPaths.version,
                                isTrusted: () -> Bool = { AX.isTrusted }, request: () -> Void = { AX.requestTrust() }) {
        let key = "accessibilityPromptedBuild"
        guard !isTrusted(), defaults.string(forKey: key) != build else { return }
        defaults.set(build, forKey: key)
        request()
    }

    /// Starts the CLI socket, and keeps trying every 5 s while it can't, so a passing problem
    /// (something squatting on the socket path) doesn't leave the CLI dead until a restart.
    private func startIPC(_ server: IPC.Server) {
        do {
            try server.start()
            ipc = server
            ipcRetry?.invalidate()
            ipcRetry = nil
        } catch {
            Log.app.error("ipc: \(String(describing: error), privacy: .public); the CLI cannot reach paw, retrying")
            guard ipcRetry == nil else { return }
            ipcRetry = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self, self.ipc == nil else { return }
                self.startIPC(server)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcRetry?.invalidate()
        ipc?.stop()
        EventBus.shared.closeAll()
        wm?.restoreAll()
    }

    private func isAlreadyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let myLaunch = NSRunningApplication.current.launchDate ?? .distantFuture
        // Only the newer of two instances quits: when `open` and launchd start paw at the same
        // moment, each sees the other, and quitting on any match left none running.
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { other in
            guard other.processIdentifier != me, !other.isTerminated else { return false }
            let theirs = other.launchDate ?? .distantFuture
            return theirs < myLaunch || (theirs == myLaunch && other.processIdentifier < me)
        }
    }

    /// SIGTERM (pkill, launchd) and SIGINT quit through AppKit, so hidden windows come back.
    /// SIGPIPE is ignored: a CLI client that hangs up before its reply is written must cost a
    /// failed write (EPIPE), not the whole app. SO_NOSIGPIPE alone can't promise that, because
    /// macOS refuses to set it on a socket whose peer already closed.
    private func installSignalHandlers() {
        signal(SIGPIPE, SIG_IGN)
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { NSApp.terminate(nil) }
            s.resume()
            signalSources.append(s)
        }
    }

    private func apply() {
        wm.configChanged()
        wm.publish("configReloaded", ["error": settings.error ?? "", "warnings": settings.warnings])
        if let e = settings.error { Log.app.error("config: \(e, privacy: .public)") }
        for w in settings.warnings { Log.app.warning("config: \(w, privacy: .public)") }
        updateLoginItem(settings.config.openAtLogin)
        MainActor.assumeIsolated {
            Updater.shared.apply(settings.config.updates)
            SettingsWindowController.shared.configDidChange()
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = Self.menuBarPaw() ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "paw")
        image?.isTemplate = true
        image?.accessibilityDescription = "paw"
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Resources/menubar.svg as an 18 pt template image (light facets → opaque, like hop's bunny).
    static func menuBarPaw(points: Int = 18) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "menubar", withExtension: "svg"),
              let svg = NSImage(contentsOf: url) else { return nil }
        let image = NSImage(size: NSSize(width: points, height: points))
        for scale in [1, 2] {
            let px = points * scale
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep), let p = rep.bitmapData
            else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            for _ in 0..<3 { svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px)) }
            NSGraphicsContext.restoreGraphicsState()
            for i in stride(from: 0, to: rep.bytesPerRow * px, by: 4) where p[i + 3] > 0 {
                let alpha = Double(p[i + 3]) / 255
                let lightness = (Double(p[i]) + Double(p[i + 1]) + Double(p[i + 2])) / 765 / alpha
                let keep = min(max((lightness - 0.3) / 0.4, 0), 1)
                (p[i], p[i + 1], p[i + 2], p[i + 3]) = (0, 0, 0, UInt8((alpha * keep * 255).rounded()))
            }
            rep.size = image.size
            image.addRepresentation(rep)
        }
        return image
    }

    @objc private func openSettings() {
        MainActor.assumeIsolated { SettingsWindowController.shared.show(settings: settings) }
    }

    @objc private func pickSetup(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        wm.run([.initiate(name)])
    }

    /// Update answers as the workspace HUD, which doesn't block like an alert.
    private func showUpdateResult(_ state: Updater.State) {
        guard let wm, let display = wm.displays.first else { return }
        wm.hud.show(label: state.text, apps: [], in: display.area, icons: settings.icons,
                    config: settings.config, duration: 2.5)
    }

    @objc private func checkForUpdates() { MainActor.assumeIsolated { Updater.shared.installNow() } }
    @objc private func initiateCurrent() { wm.run([.initiate(nil)]) }
    @objc private func reloadConfig() { settings.load() }
    @objc private func openConfig() { NSWorkspace.shared.open(settings.url) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateLoginItem(_ on: Bool) {
        // A dev build never starts at login; the release paw does.
        guard AppPaths.isAppBundle, !AppPaths.isDev else { return }
        let service = SMAppService.mainApp
        do {
            if on, service.status != .enabled { try service.register() }
            if !on, service.status == .enabled { try service.unregister() }
        } catch {
            Log.app.error("login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Requests from the CLI: "run <command>", "reload", "quit", "status", "query"; returns the reply.
    private func command(_ text: String) -> [String: Any] {
        let (name, rest) = text.firstIndex(of: " ").map { (String(text[..<$0]), String(text[text.index(after: $0)...])) } ?? (text, "")
        switch name {
        case "perf":
            if (rest == "begin" || rest == "end"), !AXQueue.isIdle { return ["error": "AX moves still pending"] }
            var reply = Performance.control(rest)
            reply["axIdle"] = AXQueue.isIdle
            return reply
        case "run":
            do { wm.run(try Command.parseAll(rest)) } catch {
                Log.app.error("cli: \(error.localizedDescription, privacy: .public)")
                return ["error": "\(error)"]
            }
        case "hide": wm.indicators.setHidden(true)
        case "show": wm.indicators.setHidden(false)
        case "reload":
            settings.load()
            return ["error": settings.error ?? "", "warnings": settings.warnings.joined(separator: "\n")]
        case "quit":
            // Answer first; terminating here would close the connection without a reply.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        case "settings":
            MainActor.assumeIsolated { SettingsWindowController.shared.show(settings: settings, page: rest.isEmpty ? nil : rest) }
        case "update":
            let available = MainActor.assumeIsolated { Updater.shared.isAvailable }
            guard available else {
                return ["error": "this build has no updater (built from source?); use git pull && just install, or brew upgrade --cask pseudobun/tap/paw"]
            }
            // "update": install now; "update check": look only; "update status": what's going on.
            let (state, pending) = MainActor.assumeIsolated { () -> (Updater.State, String?) in
                switch rest {
                case "check": Updater.shared.checkOnly()
                case "status": break
                default: Updater.shared.installNow()
                }
                return (Updater.shared.state, Updater.shared.pending)
            }
            return ["state": state == .checking ? "checking" : "done", "message": state.text, "pending": pending ?? ""]
        case "status":
            let names = wm.displays.map { wm.label($0.workspace) }.joined(separator: ", ")
            return ["version": AppPaths.version, "pid": "\(ProcessInfo.processInfo.processIdentifier)",
                    "trusted": AX.isTrusted ? "yes" : "no", "windows": "\(wm.windows.count)",
                    "workspaces": names, "stacks": "\(wm.indicators.snapshot.count)",
                    "config": settings.url.path, "error": settings.error ?? "",
                    "bindings": wm.hotkeys.problems.isEmpty ? "ok" : wm.hotkeys.problems.joined(separator: "; "),
                    "iconFont": wm.indicators.style.appFont == nil ? "missing (\(settings.config.appearance.appFont))" : "ok",
                    "windowMoves": DockBridge.shared.statusLine]
        case "query":
            // Encoded by the IPC thread (IPC.Server.serve), not here on the main thread.
            return [IPC.jsonObjectKey: wm.query()]
        default:
            Log.app.error("unknown command \(name, privacy: .public)")
            return ["error": "unknown command \(name)"]
        }
        return ["ok": true]
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Built when it opens, so setups and the active one are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let setups = settings.config.setups.keys.sorted()
        if !setups.isEmpty {
            menu.addItem(NSMenuItem(title: "Set Workspace", action: nil, keyEquivalent: ""))
            for name in setups {
                let item = NSMenuItem(title: "  " + name.capitalized, action: #selector(pickSetup(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                item.state = wm?.activeSetup == name ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        for (title, action, key) in [("Arrange Apps", #selector(initiateCurrent), ""), ("Settings…", #selector(openSettings), ","),
                                     ("Open Config File", #selector(openConfig), ""), ("Reload Config", #selector(reloadConfig), "r")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        if MainActor.assumeIsolated({ Updater.shared.isAvailable }) {
            let pending = MainActor.assumeIsolated { Updater.shared.pending }
            let item = NSMenuItem(title: pending.map { "Update to paw \($0)" } ?? "Check for Updates…",
                                  action: #selector(checkForUpdates), keyEquivalent: "")
            item.target = self
            item.isEnabled = MainActor.assumeIsolated { Updater.shared.state != .checking }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "paw \(AppPaths.version)", action: nil, keyEquivalent: ""))
        let quit = NSMenuItem(title: "Quit paw", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }
}
