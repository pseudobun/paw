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
        "settings": { args in post((["settings"] + args.prefix(1)).joined(separator: " ")) },
        "update": update,
        "reload": reload,
        "status": status,
        "query": query,
        "config": config,
        "icon": icon,
        "color": color,
        "setups": setups,
        "subscribe": subscribe,
        "preview": Preview.run,
        "theme": theme,
        "dock": DockCLI.run,
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
          swap stack.next|stack.prev   move the window down / up its stack
          warp <dir>          move the window into that tile's place, splitting it
          join <dir> [first]  move the window into the tile that way, splitting it across:
                              | | | with the middle one joined east is | =
          stack <dir>         put the window on the stack that way
          unstack [all]       take the window (or every window) out of its stack
          layout bsp|columns|master|stack|float      toggle float|zoom|split      balance      rotate 90|180|270
          resize <dir> <points>       grid rows:cols:x:y:w:h
          workspace <n>|next|prev|last|new|close      move-to <n>|next|prev [--follow]
          display <dir>|next|prev|<n>                 move-to-display <dir>|<n> [--follow]
          arrange [workspace|all]     put windows where the workspace presets say
          mode <name>|exit    turn a key mode on/off (config `modes`, e.g. resize)
          initiate [setup]    open the preset apps and arrange every workspace (also: reset);
                              with a setup name, use that setup whatever displays are connected
          setups [--json]     the setups in the config, * marks those for the connected displays
          undo | redo         the focused workspace's last layout change
          focus back|forward  windows focused before, across workspaces
          find <text>         go to the window whose app or title matches best
          overview            every workspace and window (again: close)
          retile | recover | reload | exec <shell command>

        paw itself:
          status              version, windows, workspaces per display, binding problems
          query [--json]      workspaces and their windows (for sketchybar)
          subscribe [events…] [--reconnect] [--exec <command>]
                              events as JSON lines, a snapshot first; events: workspaceChanged
                              windowFocused windowsChanged layoutChanged zoomChanged modeChanged displaysChanged
                              setupChanged configReloaded (default: all). --reconnect waits for paw
                              and starts over when it restarts; --exec runs a command per event
                              ($PAW_EVENT, $PAW_SEQ, $PAW_DATA) instead of printing it
          hide | show         hide / show the stack indicators
          reload              reload ~/.config/paw/config.json5 and print problems
          config path | check | show | template | format
          icon <app name>     the sketchybar-app-font glyph for an app
          color <app name>    the app's colour (0xAARRGGBB, from its icon or icons.colors)
          preview <out.png> [--fonts=DIR]   render stack indicators with your config
          theme [list | <name>]   the indicators' theme; a name switches to it (its own colours, fonts
                              and shape; the app icon font stays), list shows them all
          settings [page]     open the settings window, e.g. on its about page (also in the menu bar icon)
          update [--check]    install the newest version now (paw restarts); --check only looks
          dock install|uninstall|status
                              the Dock helper: windows move through the window server, much faster
                              workspace switching (needs SIP's debugging restrictions off; sudo)
          quit                quit (puts hidden windows back on screen)
          version
        """)
        return 0
    }

    /// Installs the newest version (or with --check only looks), waiting up to 2 min for the answer.
    /// Exit 10 when --check finds a new version.
    static func update(_ args: [String]) -> Int32 {
        let check = args.contains("--check")
        var r = request(check ? "update check" : "update", timeout: 10)
        let deadline = Date().addingTimeInterval(120)
        while let reply = r, reply["state"] as? String == "checking", Date() < deadline {
            usleep(300_000)
            r = request("update status", timeout: 10)
        }
        guard let r else {
            // The app quit to install.
            print("paw is restarting into the new version")
            return 0
        }
        if let e = r["error"] as? String, !e.isEmpty { fputs("paw: \(e)\n", stderr); return 1 }
        let message = r["message"] as? String ?? ""
        print(message)
        if message.hasPrefix("update check failed") { return 1 }
        return message.hasSuffix("is available") ? 10 : 0
    }

    static func runWM(_ words: [String]) -> Int32 {
        let text = words.joined(separator: " ")
        do { _ = try Command.parseAll(text) } catch {
            fputs("paw: \(error); see paw help\n", stderr)
            return 64
        }
        return post("run \(text)")
    }

    // MARK: - Talking to the running app

    /// Fire and forget: succeeds once the app has taken the command.
    static func post(_ command: String) -> Int32 {
        guard let r = request(command, timeout: 10) else { return 1 }
        if let e = r["error"] as? String, !e.isEmpty { fputs("paw: \(e)\n", stderr); return 1 }
        return 0
    }

    /// Sends a command over paw's socket and returns its reply.
    static func request(_ command: String, timeout: TimeInterval) -> [String: Any]? {
        switch IPC.send(command, timeout: timeout) {
        case .success(let reply): return reply
        case .failure(.notRunning): fputs("paw is not running (open -a paw)\n", stderr)
        case .failure(.failed(let why)): fputs("paw: \(why)\n", stderr)
        }
        return nil
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
        for k in ["version", "pid", "trusted", "windows", "workspaces", "stacks", "bindings", "iconFont", "windowMoves", "floatsOnTop", "nativeSpaces", "config", "error"] {
            if let v = r[k] as? String, !v.isEmpty { print("\(k): \(v)") }
        }
        return 0
    }

    static func subscribe(_ args: [String]) -> Int32 {
        var args = args
        var exec: String?
        if let i = args.firstIndex(of: "--exec") {
            guard args.indices.contains(i + 1) else { fputs("paw: --exec <command>\n", stderr); return 64 }
            exec = args[i + 1]
            args.removeSubrange(i...(i + 1))
        }
        let reconnect = args.contains("--reconnect")
        let events = args.filter { !$0.hasPrefix("--") }.flatMap { $0.split(separator: ",").map(String.init) }
        if let bad = events.first(where: { !EventBus.names.contains($0) }) {
            fputs("paw: unknown event \(bad); events: \(EventBus.names.dropFirst().joined(separator: " "))\n", stderr)
            return 64
        }
        let request = (["subscribe"] + (events.isEmpty ? [] : [events.joined(separator: ",")])).joined(separator: " ")
        signal(SIGPIPE, SIG_IGN)
        var warned = false
        while true {
            let end = IPC.stream(request) { line in
                if let exec {
                    run(exec, event: line)
                    return
                }
                print(line)
                // The reader went away (`paw subscribe | head`): stop.
                if fflush(stdout) != 0 || ferror(stdout) != 0 { exit(0) }
            }
            guard reconnect else {
                switch end {
                case .notRunning: fputs("paw is not running (open -a paw)\n", stderr)
                case .failed(let why): fputs("paw: \(why)\n", stderr)
                }
                return 1
            }
            if !warned { fputs("paw: waiting for paw…\n", stderr); warned = true }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// `--exec`: the command once per event, one after another, with $PAW_EVENT, $PAW_SEQ and
    /// $PAW_DATA (the event's data as JSON).
    private static func run(_ command: String, event line: String) {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["PAW_EVENT"] = obj["event"] as? String ?? ""
        env["PAW_SEQ"] = "\(obj["seq"] ?? 0)"
        if let data = obj["data"], let json = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) {
            env["PAW_DATA"] = String(decoding: json, as: UTF8.self)
        }
        p.environment = env
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            fputs("paw: \(error.localizedDescription)\n", stderr)
        }
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
        case "format":
            // Rewrites the config in the standard layout with every key and its comment.
            let data = (try? Data(contentsOf: url)) ?? Data()
            do {
                let c = try ConfigLoader.decode(data)
                try ConfigTemplate.render(c).write(to: url, atomically: true, encoding: .utf8)
                print("formatted \(url.path)")
            } catch {
                print("error: \(error)")
                return 1
            }
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
            fputs("paw config path | check | show | template | format\n", stderr)
            return 64
        }
        return 0
    }

    /// `paw theme`: the current theme, `list`, or a theme's name to switch to it.
    static func theme(_ args: [String]) -> Int32 {
        let settings = Settings(url: Settings.defaultURL)
        let a = settings.config.appearance
        switch args.first {
        case nil:
            let changed = a.overrides
            print(a.theme + (changed.isEmpty ? "" : " (changed: \(changed.sorted().joined(separator: ", ")))"))
        case "list", "--json":
            if args.contains("--json") {
                let list = Themes.all.map { ["id": $0.id, "label": $0.label, "summary": $0.summary, "light": $0.light, "current": $0.id == a.theme] as [String: Any] }
                let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                print(String(decoding: data, as: UTF8.self))
            } else {
                for t in Themes.all {
                    print("\(t.id == a.theme ? "*" : " ") \(t.id.padding(toLength: 10, withPad: " ", startingAt: 0)) \(t.summary)")
                }
            }
        case let name?:
            guard let t = Themes.named(name) else {
                fputs("paw: no theme “\(name)”; one of \(Themes.all.map(\.id).joined(separator: ", "))\n", stderr)
                return 64
            }
            if let e = settings.error { fputs("paw: the config can't be read: \(e)\n", stderr); return 1 }
            var c = settings.config
            c.appearance = a.resetToTheme(t.id)
            c.border.color = t.borderColor
            do { try ConfigTemplate.render(c).write(to: settings.url, atomically: true, encoding: .utf8) } catch {
                fputs("paw: \(error.localizedDescription)\n", stderr)
                return 1
            }
            print("theme: \(t.label)")
        }
        return 0
    }

    static func icon(_ args: [String]) -> Int32 {
        let name = args.joined(separator: " ")
        guard !name.isEmpty else { fputs("paw icon <app name>\n", stderr); return 64 }
        print(Settings(url: Settings.defaultURL).icons.glyph(for: name))
        return 0
    }

    /// The config's setups, for launchers (hop's "Set workspace").
    static func setups(_ args: [String]) -> Int32 {
        let config = Settings(url: Settings.defaultURL).config
        let screens = NSScreen.screens.map { s -> (name: String, builtin: Bool) in
            let id = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return (s.localizedName, CGDisplayIsBuiltin(id) != 0)
        }
        let matching = Set(config.matchingSetups(for: screens))
        let list = config.setups.sorted { $0.key < $1.key }.map { name, s -> [String: Any] in
            ["name": name, "displays": s.displays, "matches": matching.contains(name),
             "autoSwitch": config.switchesAutomatically(name),
             "workspaces": s.workspaces.keys.sorted(by: WindowManager.nameOrder)]
        }
        if args.contains("--json") {
            let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            print(String(decoding: data, as: UTF8.self))
        } else {
            for s in list {
                let mark = s["matches"] as? Bool == true ? "*" : " "
                print("\(mark) \(s["name"] ?? "")  [\((s["displays"] as? [String] ?? []).joined(separator: ", "))]")
            }
        }
        return 0
    }

    static func color(_ args: [String]) -> Int32 {
        let name = args.joined(separator: " ")
        guard !name.isEmpty else { fputs("paw color <app name>\n", stderr); return 64 }
        guard let c = AppColors.shared.color(for: name, icons: Settings(url: Settings.defaultURL).config.icons) else { return 1 }
        print(c)
        return 0
    }
}
