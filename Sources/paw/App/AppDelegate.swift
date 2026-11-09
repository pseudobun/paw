import AppKit
import PawCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var controller: StackController!
    private var observers: [NSObjectProtocol] = []
    private var poll: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var signalsInstalled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAlreadyRunning() {
            Log.app.info("another paw is running; exiting")
            exit(0)
        }
        installSignalHandlers()
        settings.start()
        controller = StackController(settings: settings)
        settings.onChange = { [weak self] in self?.apply() }

        observers.append(DistributedNotificationCenter.default().addObserver(forName: AppPaths.commandNotification, object: nil,
                                                                             queue: .main) { [weak self] note in
            self?.command(note.object as? String ?? "")
        })
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.controller.refresh() })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.controller.refresh()
        })
        apply()
        Log.app.info("paw \(AppPaths.version, privacy: .public) ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if signalsInstalled { controller.yabai.removeSignals() }
    }

    private func isAlreadyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }

    /// SIGTERM (pkill, launchd) and SIGINT quit through AppKit so the yabai signals get removed.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { NSApp.terminate(nil) }
            s.resume()
            signalSources.append(s)
        }
    }

    private func apply() {
        let c = settings.config
        controller.configChanged()
        poll?.invalidate()
        poll = nil
        if c.yabai.pollSeconds > 0 {
            poll = Timer.scheduledTimer(withTimeInterval: max(0.5, c.yabai.pollSeconds), repeats: true) { [weak self] _ in
                self?.controller.refresh()
            }
        }
        updateSignals(c.yabai.signals)
        if let e = settings.error { Log.app.error("config: \(e, privacy: .public)") }
        for w in settings.warnings { Log.app.warning("config: \(w, privacy: .public)") }
        updateLoginItem(c.openAtLogin)
    }

    private func updateSignals(_ on: Bool) {
        let client = controller.yabai
        let action = "\(AppPaths.cliPath) refresh"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            if on {
                let n = client.addSignals(action: action)
                Log.app.info("yabai signals: \(n)/\(YabaiClient.signalEvents.count) added")
                DispatchQueue.main.async { self?.signalsInstalled = n > 0 }
            } else {
                client.removeSignals()
                DispatchQueue.main.async { self?.signalsInstalled = false }
            }
        }
    }

    private func updateLoginItem(_ on: Bool) {
        guard AppPaths.isAppBundle else { return }
        let service = SMAppService.mainApp
        do {
            if on, service.status != .enabled { try service.register() }
            if !on, service.status == .enabled { try service.unregister() }
        } catch {
            Log.app.error("login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Commands from the CLI (`paw refresh`, `paw reload`…).
    private func command(_ name: String) {
        switch name {
        case "refresh":
            controller.refresh()
        case "hide":
            controller.hideAll()
        case "show":
            controller.showAll()
        case "reload":
            settings.load()
            reply("reload", ["error": settings.error ?? "", "warnings": settings.warnings.joined(separator: "\n")])
        case "quit":
            NSApp.terminate(nil)
        case "status":
            let stacks = controller.snapshot
            reply("status", ["version": AppPaths.version, "pid": "\(ProcessInfo.processInfo.processIdentifier)",
                             "config": settings.url.path, "error": settings.error ?? controller.lastError ?? "",
                             "stacks": "\(stacks.count) (\(stacks.map { "\($0.items.count)" }.joined(separator: ", ")))",
                             "signals": signalsInstalled ? "on" : "off",
                             "iconFont": controller.style.appFont == nil ? "missing (\(settings.config.appearance.appFont))" : "ok"])
        default:
            Log.app.error("unknown command \(name, privacy: .public)")
        }
    }

    private func reply(_ command: String, _ info: [String: String]) {
        let url = AppPaths.cacheDir.appending(path: "reply-\(command).json")
        try? FileManager.default.createDirectory(at: AppPaths.cacheDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) { try? data.write(to: url) }
        DistributedNotificationCenter.default().postNotificationName(AppPaths.replyNotification, object: command, userInfo: nil,
                                                                     deliverImmediately: true)
    }
}
