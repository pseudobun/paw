import AppKit
import PawCore

/// `paw <command>`: the app binary doubles as its CLI (bind `paw hint` in skhd or sketchybar).
enum CLI {
    static let commands: [String: ([String]) -> Int32] = [
        "help": { _ in help() }, "--help": { _ in help() }, "-h": { _ in help() },
        "version": { _ in print(AppPaths.version); return 0 }, "--version": { _ in print(AppPaths.version); return 0 },
        "hint": { _ in send("hint") },
        "search": { _ in send("search") },
        "scroll": { _ in send("scroll") },
        "reload": reload,
        "quit": { _ in send("quit", launch: false) },
        "status": status,
        "dump": dump,
        "config": config,
        "icon": icon,
        "labels": labels,
        "preview": Preview.run,
    ]

    static func runIfRequested(_ argv: [String]) {
        guard argv.count > 1 else { return }
        guard let command = commands[argv[1]] else {
            // Launch arguments macOS passes to apps (-NSDocumentRevisionsDebugMode, -psn_…) are not commands.
            if argv[1].hasPrefix("-") { return }
            fputs("paw: unknown command “\(argv[1])”; see paw help\n", stderr)
            exit(64)
        }
        let code = command(Array(argv.dropFirst(2)))
        fflush(stdout)
        exit(code)
    }

    static func help() -> Int32 {
        print("""
        paw: keyboard-driven clicking for macOS. Usage: paw <command> [options]

          hint                     Label everything clickable in the frontmost app (like the hotkey)
          search                   Open search: type to find an element, ↵ clicks it
          scroll                   Open scroll mode: h/j/k/l, shift for speed, digits/Tab switch areas
          reload                   Reload ~/.config/paw/config.json5 and print problems
          status                   Is paw running, does it have Accessibility
          dump [hint|search|scroll] [--delay=S] [--local [--app=NAME]]   What paw finds in the frontmost app, as
                                   JSON with timings (--delay: switch to the app first; --local:
                                   collect in this terminal's process instead of paw.app)
          config path | check | show | template   The config file; template prints the defaults
          icon <app name>          The sketchybar-app-font glyph paw shows for an app
          labels <n> [--charset=asdf]   The labels paw would give n elements
          preview <out.png> [--fonts=DIR] [--scale=2]   Render labels and islands with your config
          quit                     Quit the running paw
          version

        hint, search and scroll start paw.app when it isn't running.
        """)
        return 0
    }

    // MARK: - Talking to the running app

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: AppPaths.bundleID).isEmpty }

    static func send(_ command: String, launch: Bool = true) -> Int32 {
        if !isRunning {
            guard launch else { fputs("paw is not running\n", stderr); return 1 }
            guard startApp() else { return 1 }
        }
        DistributedNotificationCenter.default().postNotificationName(AppPaths.commandNotification, object: command,
                                                                     userInfo: nil, deliverImmediately: true)
        return 0
    }

    private static func startApp() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppPaths.bundleID) else {
            fputs("paw is not running and paw.app was not found (just install)\n", stderr)
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 5)
        for _ in 0..<50 where !isRunning { usleep(50_000) }
        // Give it a moment to start listening.
        usleep(300_000)
        return isRunning
    }

    /// Sends a command and waits for the app's reply file.
    static func request(_ command: String, name: String, timeout: TimeInterval) -> [String: Any]? {
        guard isRunning else { fputs("paw is not running (open -a paw)\n", stderr); return nil }
        let url = AppPaths.cacheDir.appending(path: "reply-\(name).json")
        try? FileManager.default.removeItem(at: url)
        var got = false
        let observer = DistributedNotificationCenter.default().addObserver(forName: AppPaths.replyNotification, object: name, queue: nil) { _ in
            got = true
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }
        DistributedNotificationCenter.default().postNotificationName(AppPaths.commandNotification, object: command,
                                                                     userInfo: nil, deliverImmediately: true)
        let deadline = Date().addingTimeInterval(timeout)
        while !got, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        guard got, let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fputs("paw did not answer\n", stderr)
            return nil
        }
        return obj
    }

    static func reload(_ args: [String]) -> Int32 {
        guard let r = request("reload", name: "reload", timeout: 3) else { return 1 }
        if let e = r["error"] as? String, !e.isEmpty { print("error: \(e) (keeping the last good config)"); return 1 }
        if let w = r["warnings"] as? String, !w.isEmpty { w.split(separator: "\n").forEach { print("warning: \($0)") } }
        print("reloaded")
        return 0
    }

    static func status(_ args: [String]) -> Int32 {
        guard let r = request("status", name: "status", timeout: 3) else { return 1 }
        for k in ["version", "pid", "trusted", "config", "error"] { if let v = r[k] as? String, !v.isEmpty { print("\(k): \(v)") } }
        return (r["trusted"] as? String) == "yes" ? 0 : 2
    }

    static func dump(_ args: [String]) -> Int32 {
        let purpose = args.first { !$0.hasPrefix("--") } ?? "hint"
        if let d = args.first(where: { $0.hasPrefix("--delay=") }), let s = Double(d.dropFirst(8)) {
            fputs("collecting in \(s) s: switch to the app\n", stderr)
            usleep(UInt32(s * 1_000_000))
        }
        if args.contains("--local") {
            let app = args.first { $0.hasPrefix("--app=") }.map { String($0.dropFirst(6)) }
            return dumpLocal(purpose, app: app)
        }
        guard let r = request("dump \(purpose)", name: "dump", timeout: 10), let path = r["path"] as? String,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return 1 }
        print(text)
        return 0
    }

    /// Collects in this process: needs Accessibility for the terminal running `paw`.
    static func dumpLocal(_ purpose: String, app: String?) -> Int32 {
        guard AX.isTrusted else { fputs("this terminal has no Accessibility permission\n", stderr); return 1 }
        let front: NSRunningApplication?
        if let app {
            front = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier?.lowercased() == app.lowercased() || $0.localizedName?.lowercased() == app.lowercased()
            }
        } else {
            front = NSWorkspace.shared.frontmostApplication
        }
        guard let front else { fputs("no such app running\n", stderr); return 1 }
        let p: Collector.Purpose = purpose == "search" ? .search : purpose == "scroll" ? .scroll : .hint
        let config = Settings(url: Settings.defaultURL).config
        var o = Collector.Options()
        o.purpose = p
        o.maxElements = config.hint.maxElements
        o.timeout = Float(config.axTimeout)
        o.enhancedUI = config.hint.enhancedUI
        let primary = NSScreen.screens.first?.frame.height ?? 0
        o.screens = NSScreen.screens.map { ScreenGeometry.axFrame(ofScreen: $0.frame, primaryHeight: primary) }
        o.menuBar = p != .scroll && SystemUI.wantsMenuBar(config.hint.menuBar)
        if p == .hint, SystemUI.wantsDock(config.hint.dock) {
            o.dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        }
        let r = Collector().run(pid: front.processIdentifier, bundleID: front.bundleIdentifier, options: o)
        print(String(decoding: Dump.json(r, app: front, purpose: p), as: UTF8.self))
        return 0
    }

    // MARK: - Local commands

    static func config(_ args: [String]) -> Int32 {
        let url = Settings.defaultURL
        switch args.first ?? "path" {
        case "path":
            print(url.path)
        case "template":
            print(ConfigTemplate.text, terminator: "")
        case "show":
            let s = Settings(url: url)
            if let e = s.error { fputs("error: \(e)\n", stderr) }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: (try? enc.encode(s.config)) ?? Data(), as: UTF8.self))
        case "check":
            guard let data = try? Data(contentsOf: url) else { print("\(url.path): missing, defaults apply"); return 0 }
            do {
                let c = try ConfigLoader.decode(data)
                let problems = ConfigLoader.unknownKeys(data).map { "unknown key \($0)" } + ConfigLoader.warnings(c)
                problems.forEach { print("warning: \($0)") }
                print(problems.isEmpty ? "ok" : "ok with \(problems.count) warning(s)")
            } catch {
                print("error: \(error)")
                return 1
            }
        default:
            fputs("paw config path | check | show | template\n", stderr)
            return 64
        }
        return 0
    }

    static func icon(_ args: [String]) -> Int32 {
        let name = args.joined(separator: " ")
        guard !name.isEmpty else { fputs("paw icon <app name>\n", stderr); return 64 }
        print(Settings(url: Settings.defaultURL).icons.glyph(for: name))
        return 0
    }

    static func labels(_ args: [String]) -> Int32 {
        let charset = args.first { $0.hasPrefix("--charset=") }.map { String($0.dropFirst(10)) }
            ?? Settings(url: Settings.defaultURL).config.hint.charset
        guard let n = args.first(where: { !$0.hasPrefix("--") }).flatMap(Int.init), n > 0 else {
            fputs("paw labels <n> [--charset=…]\n", stderr)
            return 64
        }
        print(LabelGenerator.labels(count: n, charset: charset).joined(separator: " "))
        return 0
    }
}
