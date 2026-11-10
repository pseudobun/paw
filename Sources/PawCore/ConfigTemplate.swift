import Foundation

/// The commented JSON5 config: `render` writes any config (the settings window saves through
/// it), `text` is the defaults paw writes to `~/.config/paw/config.json5` on first launch
/// (`paw config template`). Comments explain every key, so people and agents can edit the file.
public enum ConfigTemplate {
    public static var text: String { render(PawConfig()) }

    public static func render(_ c: PawConfig) -> String {
        let l = c.layout, f = c.focus, a = c.animation, i = c.indicator, ap = c.appearance, k = ap.colors
        var o = """
        // paw configuration (JSON5: comments and trailing commas are fine).
        // Saved changes apply immediately. Delete a key to use its default.
        // The settings window (paw settings, or the menu bar icon) writes this file too.
        {
          layout: {
            // New workspaces: "bsp", "columns", "master", "stack" or "float"
            default: \(str(l.default.rawValue)),
            gap: \(num(l.gap)),
            padding: { top: \(num(l.padding.top)), bottom: \(num(l.padding.bottom)), left: \(num(l.padding.left)), right: \(num(l.padding.right)) },
            // Extra room for a status bar such as sketchybar (41 for a 40 pt bar); menu bar and Dock are already left out
            barTop: \(num(l.barTop)),
            barBottom: \(num(l.barBottom)),
            // Workspaces 1…N exist from the start; "workspace new" adds more
            workspaces: \(l.workspaces),
            // Where initiate and setup switches put windows of apps no preset or rule places:
        // a workspace ("4"), or "" to leave them on the workspace they're on
            unassignedWorkspace: \(str(l.unassignedWorkspace)),
            // bsp: tiles never get smaller than this; when more windows don't fit, the tree grows past
            // the screen and the screen follows focus (like TrellisWM's canvas). 0: off, tiles shrink
            // freely and only windows whose app refuses the size get a placeholder
            minTileWidth: \(num(l.minTileWidth)),
            minTileHeight: \(num(l.minTileHeight)),
            // A window whose app won't shrink to its tile waits out of sight and a placeholder with its
            // icon takes the tile; false: the window keeps its size and sticks out over its neighbours
            placeholders: \(l.placeholders),
            // resizing stops before a tile, and so a placeholder, gets smaller than this
            placeholderMinWidth: \(num(l.placeholderMinWidth)),
            placeholderMinHeight: \(num(l.placeholderMinHeight)),
          },

          focus: {
            mouseFollowsFocus: \(f.mouseFollowsFocus),
            focusFollowsMouse: \(f.focusFollowsMouse),
            // stack.next on the last window goes back to the first (false: it stays)
            wrapStacks: \(f.wrapStacks),
            // workspace next on the last workspace goes back to the first (false: it stays)
            wrapWorkspaces: \(f.wrapWorkspaces),
          },

          animation: {
            enabled: \(a.enabled),
            durationMs: \(num(a.durationMs)),
            // linear, easeOutCubic, easeInOutCubic, easeOutQuint, easeOutBack, spring
            curve: \(str(a.curve.rawValue)),
            // "start": final size first, then glide (smooth); "animate": size every frame; "end"
            resize: \(str(a.resize)),
            // More windows moving at once than this are placed without animation
            maxWindows: \(a.maxWindows),
          },

          // Presets: which apps go in which tile. initiate, arrange (or opening the app) puts them there.
          // Used when no setup below matches the connected displays.
          workspaces: {

        """
        o += c.workspaces.isEmpty ? """
            // "1": {
            //   layout: "bsp",
            //   axis: "horizontal",           // tiles side by side; "vertical" stacks them
            //   tiles: [
            //     { apps: ["Discord", "Spotify"], size: 1 },   // one stack, first app on top
            //     { apps: ["Ghostty", "/^Alacritty$/"], size: 1 },
            //     { apps: ["Ghostty"], title: "paw", launch: "open -na Ghostty --args --working-directory=~/repos/paw" },
            //   ],
            //   display: "builtin",           // pin: "builtin", "external", "main", "secondary", 1, 2… or a name ("DELL")
            // },

        """ : presets(c.workspaces, indent: "    ")
        o += """
          },

          // Presets per display arrangement. When the connected displays match a setup's `displays`
          // (one entry each: "builtin", "external" or part of a name), its workspaces replace the ones
          // above, every display shows its pinned workspace and windows move where the presets say.
          setups: {

        """
        if c.setups.isEmpty {
            o += """
                // home: {
                //   displays: ["builtin", "DELL", "Gigabyte"],
                //   focus: "9",
                //   workspaces: {
                //     "1": { display: "builtin" },
                //     "8": { display: "DELL", layout: "stack", tiles: [ { apps: ["Discord", "Spotify"] } ] },
                //     "9": { display: "Gigabyte", layout: "bsp", tiles: [ { apps: ["Safari"], size: 2 }, { apps: ["Zed"] } ] },
                //   },
                // },

            """
        } else {
            for (name, s) in c.setups.sorted(by: { $0.key < $1.key }) {
                o += "    \(key(name)): {\n"
                o += "      displays: [\(s.displays.map(str).joined(separator: ", "))],\n"
                if !s.focus.isEmpty { o += "      focus: \(str(s.focus)),\n" }
                o += "      workspaces: {\n" + presets(s.workspaces, indent: "        ") + "      },\n"
                o += "    },\n"
            }
        }
        o += """
          },

          // app: name or /regex/; title / unlessTitle: substring or /regex/
          // manage: false leaves windows alone, float: true floats them, workspace: where they open
          rules: [

        """
        for r in c.rules { o += "    \(rule(r)),\n" }
        o += """
          ],

          // Stack indicators: an island next to each stack with one app icon per window
          indicator: {
            // the islands beside stacks, one icon per window
            enabled: \(i.enabled),
            // "auto" (outside, on the side nearer the screen edge), "left", "right", "insideLeft", "insideRight"
            side: \(str(i.side.rawValue)),
            offsetX: \(num(i.offsetX)),
            offsetY: \(num(i.offsetY)),
            width: \(num(i.width)),
            cellHeight: \(num(i.cellHeight)),
            gap: \(num(i.gap)),
            padding: \(num(i.padding)),
            titles: \(str(i.titles)), // or "never"
            clickToFocus: \(i.clickToFocus),
            scrollToCycle: \(i.scrollToCycle),
            unfocusedOpacity: \(num(i.unfocusedOpacity)),
            fadeMs: \(num(i.fadeMs)),
          },

          appearance: {
            font: \(str(ap.font)),
            fontSize: \(num(ap.fontSize)),
            appFont: \(str(ap.appFont)),
            appIconSize: \(num(ap.appIconSize)),
            radius: \(num(ap.radius)),
            cellRadius: \(num(ap.cellRadius)),
            borderWidth: \(num(ap.borderWidth)),
            shadow: \(ap.shadow),
            // 0xAARRGGBB or "#RRGGBB"
            colors: {
              island: \(str(k.island.description)),
              islandHi: \(str(k.islandHi.description)),
              border: \(str(k.border.description)),
              fg: \(str(k.fg.description)),
              muted: \(str(k.muted.description)),
              dim: \(str(k.dim.description)),
              accent: \(str(k.accent.description)),
              wave: \(str(k.wave.description)),
              good: \(str(k.good.description)),
              bad: \(str(k.bad.description)),
            },
          },

          icons: {
            // sketchybar's app → glyph map; paw's built-in copy is used when it's missing
            map: \(str(c.icons.map)),
            overrides: \(map(c.icons.overrides)),
            // Each icon in the app's own colour (picked from its app icon); colors fixes single apps
            brandColors: \(c.icons.brandColors),
            colors: \(map(c.icons.colors.mapValues(\.description))),
          },

          // Shell commands with $PAW_WORKSPACE / $PAW_PREV_WORKSPACE, $PAW_APP / $PAW_WINDOW;
          // windowsChanged runs when windows open, close or change workspace (read `paw query --json`);
          // modeChanged when a mode turns on or off ($PAW_MODE, "" for off);
          // displaysChanged after displays come, go or move and paw has retiled ($PAW_DISPLAYS)
          hooks: {
            workspaceChanged: \(str(c.hooks.workspaceChanged)),
            windowFocused: \(str(c.hooks.windowFocused)),
            windowsChanged: \(str(c.hooks.windowsChanged)),
            modeChanged: \(str(c.hooks.modeChanged)),
            displaysChanged: \(str(c.hooks.displaysChanged)),
          },

          mouse: {
            // Drop a dragged tile on a tile's edge to split it there, on the gap between tiles to make
            // room there, at the screen's edge to dock beside everything, in a tile's middle to swap
            // (holding stackModifier: to stack). A preview shows where it lands.
            dropZones: \(c.mouse.dropZones),
            stackModifier: \(str(c.mouse.stackModifier)), // alt, cmd, ctrl or shift
            // Drag the gap between two tiles to resize both; double-click it to even them out
            seamHandles: \(c.mouse.seamHandles),
            // Hold a mouse button (middle, back, forward), drag left/right/up/down (or "click"), release
            gestures: [
        \(c.mouse.gestures.map { "      { button: \(str($0.button)), direction: \(str($0.direction)), command: \(str($0.command)) },\n" }.joined())    ],
            // No gestures while one of these is in front (they pan or orbit with the middle button)
            gestureIgnoreApps: [\(c.mouse.gestureIgnoreApps.map(str).joined(separator: ", "))],
            // Hold it and scroll or pinch over a window to zoom through the tree towards it ("off": never)
            zoomModifier: \(str(c.mouse.zoomModifier)),
          },

          // overview (hyper+tab): every workspace and its windows. Arrows move, Return goes there,
          // typing filters, drag a window onto a workspace or next to another window, Esc closes.
          overview: {
            // Window pictures: "auto" (if Screen Recording is already allowed), "on" (asks), "off" (icons)
            thumbnails: \(str(c.overview.thumbnails)),
          },

          // The island that flashes the workspace's number and apps when you switch
          hud: {
            workspace: \(c.hud.workspace),
            durationMs: \(num(c.hud.durationMs)),
          },

          // A line around the focused window (or a placeholder that has focus)
          border: {
            enabled: \(c.border.enabled),
            color: \(str(c.border.color.description)), // 0xAARRGGBB or "#RRGGBB"
            width: \(num(c.border.width)),
            radius: \(num(c.border.radius)),
            offset: \(num(c.border.offset)),
          },

          // `paw initiate` (also `paw reset`): opens the apps, waits for their windows, then arranges
          // every preset. apps: [] means every plain app name in the presets.
          initiate: {
            apps: [\(c.initiate.apps.map(str).joined(separator: ", "))],
            focus: \(str(c.initiate.focus)),
            timeout: \(num(c.initiate.timeout)),
          },

          openAtLogin: \(c.openAtLogin),

          // New versions from GitHub releases. Homebrew installs can also `brew upgrade --cask pseudobun/tap/paw`.
          updates: {
            check: \(c.updates.check), // look once a day, download in the background, install when paw quits
            automatic: \(c.updates.automatic), // install as soon as it is downloaded; paw restarts
          },

          // Keys: cmd ctrl alt shift fn hyper meh, lalt/ralt (and lcmd, rctrl…), a key name or 0x keycode.
          // Commands (also `paw <command>`; chain with ";"):
          //   focus west|east|north|south|stack.next|stack.prev   swap|warp|stack <dir>   swap stack.next|stack.prev   unstack [all]
          //   layout bsp|columns|master|stack|float   toggle float|zoom|split   balance   rotate 90|180|270
          //   undo   redo   focus back|forward   find <app or title>   overview   zoom in|out
          //   resize <dir> <points>   grid rows:cols:x:y:w:h   workspace <n>|next|prev|last|new|close
          //   move-to <n>|next|prev [--follow]   display <dir>|next|n   move-to-display <dir> [--follow]
          //   arrange [workspace|all]   initiate   mode <name>|exit   retile   recover   reload   exec <shell command>
          // Setting bindings replaces this whole list.
          bindings: {

        """
        for (key, cmd) in c.bindings.sorted(by: { order($0.key, c.bindings) < order($1.key, c.bindings) }) {
            o += "    \(str(key)): \(str(cmd)),\n"
        }
        o += """
          },

          // While a mode is on (`mode resize`, hyper+r), its keys come before the bindings above and an
          // island at the top of the screen says so. resize <dir> <points> moves that edge.
          modes: {

        """
        for (name, keys) in c.modes.sorted(by: { $0.key < $1.key }) {
            o += "    \(key(name)): {\n"
            for (key, cmd) in keys.sorted(by: { order($0.key, keys) < order($1.key, keys) }) {
                o += "      \(str(key)): \(str(cmd)),\n"
            }
            o += "    },\n"
        }
        o += """
          },
        }

        """
        return o
    }

    // MARK: - Pieces

    static func presets(_ p: [String: WorkspacePreset], indent: String) -> String {
        p.sorted { ($0.key.count, $0.key) < ($1.key.count, $1.key) }.map { name, w in
            var parts: [String] = []
            if let d = w.display { parts.append("display: \(str(d))") }
            if let l = w.layout { parts.append("layout: \(str(l.rawValue))") }
            if w.axis != .horizontal { parts.append("axis: \(str(w.axis.rawValue))") }
            if !w.tiles.isEmpty {
                let tiles = w.tiles.map { t in
                    "{ apps: [\(t.apps.map(str).joined(separator: ", "))]" + (t.size.map { ", size: \(num($0))" } ?? "")
                        + (t.title.map { ", title: \(str($0))" } ?? "") + (t.launch.map { ", launch: \(str($0))" } ?? "") + " }"
                }
                parts.append("tiles: [ \(tiles.joined(separator: ", ")) ]")
            }
            return "\(indent)\(str(name)): { \(parts.joined(separator: ", ")) },\n"
        }.joined()
    }

    static func rule(_ r: PawConfig.Rule) -> String {
        var parts = ["app: \(str(r.app))"]
        if let t = r.title { parts.append("title: \(str(t))") }
        if let t = r.unlessTitle { parts.append("unlessTitle: \(str(t))") }
        if let m = r.manage { parts.append("manage: \(m)") }
        if let f = r.float { parts.append("float: \(f)") }
        if let w = r.workspace { parts.append("workspace: \(str(w))") }
        return "{ \(parts.joined(separator: ", ")) }"
    }

    static func map(_ m: [String: String]) -> String {
        m.isEmpty ? "{}" : "{ " + m.sorted { $0.key < $1.key }.map { "\(str($0.key)): \(str($0.value))" }.joined(separator: ", ") + " }"
    }

    /// A JSON string literal.
    static func str(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// An object key: bare when it's an identifier, quoted otherwise.
    static func key(_ s: String) -> String {
        let ok = s.first.map { $0.isLetter || $0 == "_" } == true && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        return ok ? s : str(s)
    }

    static func num(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
    }

    /// Groups bindings by command so the file reads like an skhdrc.
    static func order(_ key: String, _ bindings: [String: String]) -> String {
        let cmd = bindings[key] ?? ""
        let verb = cmd.split(separator: " ").first.map(String.init) ?? ""
        let rank = ["focus", "swap", "stack", "warp", "unstack", "layout", "toggle", "grid", "balance", "rotate", "resize",
                    "workspace", "move-to", "mode", "undo", "redo", "overview", "find", "recover", "exec"].firstIndex(of: verb) ?? 99
        let num = Int(cmd.split(separator: " ").dropFirst().first ?? "") ?? 0
        return String(format: "%02d %03d %@ %@", rank, num, cmd, key)
    }
}
