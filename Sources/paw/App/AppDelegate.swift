import AppKit
import PawCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private var controller: Controller!
    private var hotkeys: [Controller.Kind: GlobalHotkey] = [:]
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAlreadyRunning() {
            Log.app.info("another paw is running; exiting")
            exit(0)
        }
        settings.start()
        controller = Controller(settings: settings)
        settings.onChange = { [weak self] in self?.apply() }

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: AppPaths.commandNotification, object: nil, queue: .main) { [weak self] note in
            self?.command(note.object as? String ?? "")
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.controller.screensChanged()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
            self?.controller.dismiss()
        })
        if !AX.isTrusted { AX.requestTrust() }
        apply()
        Log.app.info("paw \(AppPaths.version, privacy: .public) ready, trusted: \(AX.isTrusted)")
    }

    private func isAlreadyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != me }
    }

    private func apply() {
        controller.configChanged()
        let c = settings.config
        for (kind, text) in [(Controller.Kind.hint, c.hint.hotkey), (.search, c.search.hotkey), (.scroll, c.scroll.hotkey)] {
            hotkeys[kind]?.unregister()
            hotkeys[kind] = nil
            guard !text.isEmpty else { continue }
            guard let spec = HotkeySpec.parse(text) else {
                Log.app.error("\(kind.rawValue, privacy: .public).hotkey: “\(text, privacy: .public)” is not a hotkey")
                continue
            }
            let hk = GlobalHotkey { [weak self] in self?.controller.toggle(kind) }
            if hk.register(spec) { hotkeys[kind] = hk } else {
                Log.app.error("\(kind.rawValue, privacy: .public).hotkey \(text, privacy: .public) is taken")
            }
        }
        if let e = settings.error { controller.notice("Config: \(e)", color: controller.style.colors.bad) }
        for w in settings.warnings { Log.app.warning("config: \(w, privacy: .public)") }
        updateLoginItem(c.openAtLogin)
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

    /// Commands from the CLI (`paw hint`, `paw reload`…).
    private func command(_ text: String) {
        let parts = text.split(separator: " ").map(String.init)
        guard let name = parts.first else { return }
        switch name {
        case "hint", "search", "scroll":
            controller.toggle(Controller.Kind(rawValue: name)!)
        case "reload":
            settings.load()
            reply("reload", ["error": settings.error ?? "", "warnings": settings.warnings.joined(separator: "\n")])
        case "quit":
            NSApp.terminate(nil)
        case "status":
            reply("status", ["trusted": AX.isTrusted ? "yes" : "no", "version": AppPaths.version, "pid": "\(ProcessInfo.processInfo.processIdentifier)",
                             "config": settings.url.path, "error": settings.error ?? ""])
        case "dump":
            dump(purpose: parts.dropFirst().first ?? "hint")
        default:
            Log.app.error("unknown command \(name, privacy: .public)")
        }
    }

    /// Collects the frontmost app like a mode would and writes what it found to a file.
    private func dump(purpose: String) {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let p: Collector.Purpose = purpose == "search" ? .search : purpose == "scroll" ? .scroll : .hint
        let options = controller.collectorOptions(p)
        controller.collector.collect(pid: front.processIdentifier, bundleID: front.bundleIdentifier, options: options) { [weak self] r in
            let out = Dump.json(r, app: front, purpose: p)
            let url = AppPaths.cacheDir.appending(path: "dump.json")
            try? FileManager.default.createDirectory(at: AppPaths.cacheDir, withIntermediateDirectories: true)
            try? out.write(to: url)
            self?.reply("dump", ["path": url.path])
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
