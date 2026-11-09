import AppKit
import PawCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var wm: WindowManager!
    private var observers: [NSObjectProtocol] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAlreadyRunning() {
            Log.app.info("another paw is running; exiting")
            exit(0)
        }
        installSignalHandlers()
        settings.start()
        wm = WindowManager(settings: settings)
        settings.onChange = { [weak self] in self?.apply() }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: AppPaths.commandNotification, object: nil,
                                                                             queue: .main) { [weak self] note in
            self?.command(note.object as? String ?? "")
        })
        // Window management needs Accessibility; wait for the grant instead of quitting.
        if AX.isTrusted {
            wm.start()
        } else {
            AX.requestTrust()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard AX.isTrusted else { return }
                t.invalidate()
                self?.wm.start()
            }
        }
        updateLoginItem(settings.config.openAtLogin)
        Log.app.info("paw \(AppPaths.version, privacy: .public) ready, trusted: \(AX.isTrusted)")
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        wm.configChanged()
        if let e = settings.error { Log.app.error("config: \(e, privacy: .public)") }
        for w in settings.warnings { Log.app.warning("config: \(w, privacy: .public)") }
        updateLoginItem(settings.config.openAtLogin)
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

    /// Messages from the CLI: "run <command>", "reload", "quit", "status", "query".
    private func command(_ text: String) {
        let (name, rest) = text.firstIndex(of: " ").map { (String(text[..<$0]), String(text[text.index(after: $0)...])) } ?? (text, "")
        switch name {
        case "run":
            do { wm.run(try Command.parseAll(rest)) } catch { Log.app.error("cli: \(error.localizedDescription, privacy: .public)") }
        case "hide": wm.indicators.setHidden(true)
        case "show": wm.indicators.setHidden(false)
        case "reload":
            settings.load()
            reply("reload", ["error": settings.error ?? "", "warnings": settings.warnings.joined(separator: "\n")])
        case "quit":
            NSApp.terminate(nil)
        case "status":
            let names = wm.displays.map(\.workspace).joined(separator: ", ")
            reply("status", ["version": AppPaths.version, "pid": "\(ProcessInfo.processInfo.processIdentifier)",
                             "trusted": AX.isTrusted ? "yes" : "no", "windows": "\(wm.windows.count)",
                             "workspaces": names, "stacks": "\(wm.indicators.snapshot.count)",
                             "config": settings.url.path, "error": settings.error ?? "",
                             "bindings": wm.hotkeys.problems.isEmpty ? "ok" : wm.hotkeys.problems.joined(separator: "; "),
                             "iconFont": wm.indicators.style.appFont == nil ? "missing (\(settings.config.appearance.appFont))" : "ok"])
        case "query":
            let data = (try? JSONSerialization.data(withJSONObject: wm.query(), options: [.prettyPrinted, .sortedKeys])) ?? Data()
            reply("query", ["json": String(decoding: data, as: UTF8.self)])
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
