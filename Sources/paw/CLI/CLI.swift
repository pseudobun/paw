import AppKit
import PawCore

/// `paw <command>`: the app binary doubles as its CLI.
enum CLI {
    static let commands: [String: ([String]) -> Int32] = [
        "help": { _ in help() }, "--help": { _ in help() }, "-h": { _ in help() },
        "version": { _ in print(AppPaths.version); return 0 }, "--version": { _ in print(AppPaths.version); return 0 },
        "hide": { _ in post("hide") },
        "show": { _ in post("show") },
        "quit": { _ in post("quit") },
        "reload": reload,
        "status": status,
        "query": query,
        "config": config,
        "icon": icon,
        "preview": Preview.run,
    ]

    static func runIfRequested(_ argv: [String]) {
        guard argv.count > 1 else { return }
        // Launch arguments macOS passes to apps (-NSDocumentRevisionsDebugMode, -psn_…) are not commands.
        if argv[1].hasPrefix("-"), commands[argv[1]] == nil { return }
        let code: Int32
        if let command = commands[argv[1]] {
            code = command(Array(argv.dropFirst(2)))
        } else {
            code = runWM(Array(argv.dropFirst()))
        }
        fflush(stdout)
        exit(code)
    }

    static func help() -> Int32 {
        print("""
        paw: tiling window manager with stack indicators, in the style of sketchybar.
        Usage: paw <command> [options]

        Window commands (the same as in config bindings; chain with ";"):
          focus west|east|north|south|stack.next|stack.prev|stack.first|stack.last
          swap <dir>          swap with the window that way (another display when there is none)
          warp <dir>          move the window into that tile's place, splitting it
          stack <dir>         put the window on the stack that way
          unstack [all]       take the window (or every window) out of its stack
          layout bsp|stack|float      toggle float|zoom|split      balance      rotate 90|180|270
          resize <dir> <points>       grid rows:cols:x:y:w:h
          workspace <n>|next|prev|last|new|close      move-to <n>|next|prev [--follow]
          display <dir>|next|prev|<n>                 move-to-display <dir>|<n> [--follow]
          arrange [workspace|all]     put windows where the workspace presets say
          initiate            open the preset apps (config `initiate`) and arrange every workspace
          retile | recover | reload | exec <shell command>

        paw itself:
          status              version, windows, workspaces per display, binding problems
          query [--json]      workspaces and their windows (for sketchybar)
          hide | show         hide / show the stack indicators
          reload              reload ~/.config/paw/config.json5 and print problems
          config path | check | show | template
          icon <app name>     the sketchybar-app-font glyph for an app
          preview <out.png> [--fonts=DIR]   render stack indicators with your config
          quit                quit (puts hidden windows back on screen)
          version
        """)
        return 0
    }

    static func runWM(_ words: [String]) -> Int32 {
        let text = words.joined(separator: " ")
        do { _ = try Command.parseAll(text) } catch {
            fputs("paw: \(error); see paw help\n", stderr)
            return 64
        }
        guard isRunning else { fputs("paw is not running (open -a paw)\n", stderr); return 1 }
        return post("run \(text)")
    }

    // MARK: - Talking to the running app

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: AppPaths.bundleID).isEmpty }

    /// Fire and forget.
    static func post(_ command: String) -> Int32 {
        guard isRunning else { fputs("paw is not running (open -a paw)\n", stderr); return 1 }
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
        for k in ["version", "pid", "trusted", "windows", "workspaces", "stacks", "bindings", "iconFont", "config", "error"] {
            if let v = r[k] as? String, !v.isEmpty { print("\(k): \(v)") }
        }
        return 0
    }

    // MARK: - Local commands

    static func query(_ args: [String]) -> Int32 {
        guard let r = request("query", timeout: 3), let json = r["json"] as? String else { return 1 }
        if args.contains("--json") { print(json); return 0 }
        guard let list = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else { return 1 }
        for ws in list {
            let wins = ws["windows"] as? [[String: Any]] ?? []
            if wins.isEmpty, ws["visible"] as? Bool != true { continue }
            let mark = ws["focused"] as? Bool == true ? "●" : (ws["visible"] as? Bool == true ? "○" : " ")
            print("\(mark) \(ws["name"] ?? "")  \(ws["layout"] ?? "")  \(wins.map { "\($0["app"] ?? "")" }.joined(separator: ", "))")
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
