import AppKit
import PawCore

/// `paw <command>`: the app binary doubles as its CLI (yabai signals run `paw refresh`).
enum CLI {
    static let commands: [String: ([String]) -> Int32] = [
        "help": { _ in help() }, "--help": { _ in help() }, "-h": { _ in help() },
        "version": { _ in print(AppPaths.version); return 0 }, "--version": { _ in print(AppPaths.version); return 0 },
        "refresh": { _ in post("refresh") },
        "hide": { _ in post("hide") },
        "show": { _ in post("show") },
        "quit": { _ in post("quit") },
        "reload": reload,
        "status": status,
        "stacks": stacks,
        "signals": signals,
        "config": config,
        "icon": icon,
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
        paw: yabai stack indicators in the style of sketchybar. Usage: paw <command> [options]

          refresh                  Redraw now (what paw's yabai signals run); quiet when paw isn't running
          hide | show              Hide all indicators / show them again
          reload                   Reload ~/.config/paw/config.json5 and print problems
          status                   Version, stacks on screen, signals, icon font
          stacks [--json]          The stacks paw sees right now (queries yabai itself)
          signals list | add | remove   paw's yabai signals (paw adds them on launch, removes on quit)
          config path | check | show | template   The config file; template prints the defaults
          icon <app name>          The sketchybar-app-font glyph paw shows for an app
          preview <out.png> [--fonts=DIR] [--scale=2]   Render indicators with your config
          quit                     Quit the running paw
          version
        """)
        return 0
    }

    // MARK: - Talking to the running app

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: AppPaths.bundleID).isEmpty }

    /// Fire and forget; paw not running is fine (signals call this all the time).
    static func post(_ command: String) -> Int32 {
        guard isRunning else { return 0 }
        DistributedNotificationCenter.default().postNotificationName(AppPaths.commandNotification, object: command,
                                                                     userInfo: nil, deliverImmediately: true)
        return 0
    }

    /// Sends a command and waits for the app's reply file.
    static func request(_ command: String, timeout: TimeInterval) -> [String: Any]? {
        guard isRunning else { fputs("paw is not running (open -a paw)\n", stderr); return nil }
        let url = AppPaths.cacheDir.appending(path: "reply-\(command).json")
        try? FileManager.default.removeItem(at: url)
        var got = false
        let observer = DistributedNotificationCenter.default().addObserver(forName: AppPaths.replyNotification, object: command,
                                                                           queue: nil) { _ in got = true }
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
        guard let r = request("reload", timeout: 3) else { return 1 }
        if let w = r["warnings"] as? String, !w.isEmpty { w.split(separator: "\n").forEach { print("warning: \($0)") } }
        if let e = r["error"] as? String, !e.isEmpty { print("error: \(e) (keeping the last good config)"); return 1 }
        print("reloaded")
        return 0
    }

    static func status(_ args: [String]) -> Int32 {
        guard let r = request("status", timeout: 3) else { return 1 }
        for k in ["version", "pid", "stacks", "signals", "iconFont", "config", "error"] {
            if let v = r[k] as? String, !v.isEmpty { print("\(k): \(v)") }
        }
        return 0
    }

    // MARK: - Local commands

    static func stacks(_ args: [String]) -> Int32 {
        let s = Settings(url: Settings.defaultURL)
        let client = YabaiClient(path: s.config.yabai.path)
        guard let r = client.query() else { fputs("yabai did not answer (\(s.config.yabai.path))\n", stderr); return 1 }
        let excluded = Set(s.config.excludedApps.map { $0.lowercased() })
        let stacks = StackBuilder.stacks(windows: r.windows.filter { !excluded.contains($0.app.lowercased()) }, spaces: r.spaces,
                                         fuzz: s.config.yabai.fuzz)
        if args.contains("--json") {
            let list = stacks.map { st -> [String: Any] in
                ["space": st.space, "frame": [st.frame.minX, st.frame.minY, st.frame.width, st.frame.height].map { Int($0) },
                 "windows": st.items.map { ["id": $0.id, "app": $0.app, "title": $0.title, "glyph": s.icons.glyph(for: $0.app),
                                            "active": $0.isActive, "focus": $0.hasFocus] as [String: Any] }]
            }
            let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            print(String(decoding: data, as: UTF8.self))
            return 0
        }
        if stacks.isEmpty { print("no stacks on visible spaces") }
        for st in stacks {
            print("space \(st.space) @ \(Int(st.frame.minX)),\(Int(st.frame.minY)) \(Int(st.frame.width))×\(Int(st.frame.height))")
            for i in st.items {
                let mark = i.hasFocus ? "●" : i.isActive ? "○" : " "
                print("  \(mark) \(i.app)  \(s.icons.glyph(for: i.app))  \(i.title)")
            }
        }
        return 0
    }

    static func signals(_ args: [String]) -> Int32 {
        let client = YabaiClient(path: Settings(url: Settings.defaultURL).config.yabai.path)
        switch args.first ?? "list" {
        case "list": client.listSignals().forEach { print($0) }
        case "add": print("\(client.addSignals(action: "\(AppPaths.cliPath) refresh"))/\(YabaiClient.signalEvents.count) added")
        case "remove": client.removeSignals(); print("removed")
        default: fputs("paw signals list | add | remove\n", stderr); return 64
        }
        return 0
    }

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
            let data = (try? Data(contentsOf: url)) ?? Data()
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
}
