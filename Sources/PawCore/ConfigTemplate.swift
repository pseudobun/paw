/// The commented config paw writes to `~/.config/paw/config.json5` on first launch
/// (`paw config template` prints it). Every value here is the default.
public enum ConfigTemplate {
    public static var text: String {
        let bindings = Defaults.bindings.sorted { order($0.key) < order($1.key) }
            .map { "    \"\($0.key)\": \"\($0.value)\"," }.joined(separator: "\n")
        return head + bindings + "\n" + tail
    }

    /// Groups bindings by command so the file reads like an skhdrc.
    static func order(_ key: String) -> String {
        let cmd = Defaults.bindings[key] ?? ""
        let verb = cmd.split(separator: " ").first.map(String.init) ?? ""
        let rank = ["focus", "swap", "stack", "warp", "unstack", "layout", "toggle", "grid", "balance", "rotate", "resize",
                    "workspace", "move-to", "recover", "exec"].firstIndex(of: verb) ?? 99
        let num = Int(cmd.split(separator: " ").dropFirst().first ?? "") ?? 0
        return String(format: "%02d %03d %@ %@", rank, num, cmd, key)
    }

    static let head = """
    // paw configuration (JSON5: comments and trailing commas are fine).
    // Saved changes apply immediately. Delete a key to use its default.
    {
      layout: {
        // New workspaces: "bsp", "stack" or "float"
        default: "stack",
        gap: 10,
        padding: { top: 2, bottom: 2, left: 24, right: 24 },
        // Extra room for a status bar such as sketchybar (41 for a 40 pt bar); menu bar and Dock are already left out
        barTop: 0,
        barBottom: 0,
        // Workspaces 1…N exist from the start; "workspace new" adds more
        workspaces: 10,
      },

      focus: {
        mouseFollowsFocus: true,
        focusFollowsMouse: false,
      },

      animation: {
        enabled: true,
        durationMs: 180,
        // linear, easeOutCubic, easeInOutCubic, easeOutQuint, easeOutBack, spring
        curve: "easeOutCubic",
        // "start": final size first, then glide (smooth); "animate": size every frame; "end"
        resize: "start",
        // More windows moving at once than this are placed without animation
        maxWindows: 12,
      },

      // Presets: which apps go in which tile. "arrange" (or opening the app) puts them there.
      workspaces: {
        // "1": {
        //   layout: "bsp",
        //   axis: "horizontal",           // tiles side by side; "vertical" stacks them
        //   tiles: [
        //     { apps: ["Discord", "Spotify"], size: 1 },   // one stack
        //     { apps: ["Ghostty", "/^Alacritty$/"], size: 1 },
        //   ],
        //   display: "main",              // or "secondary", or 1, 2…
        // },
      },

      // app: name or /regex/; title / unlessTitle: substring or /regex/
      // manage: false leaves windows alone, float: true floats them, workspace: where they open
      rules: [
        { app: "/^(System Settings|System Information|Calculator|Archive Utility|Raycast|Alfred|CleanShot X|1Password)$/", float: true },
        { app: "Google Chrome", unlessTitle: "Google Chrome", float: true },
        { app: "Brave Browser", unlessTitle: "Brave", float: true },
        { app: "Zen", unlessTitle: "Zen", float: true },
        { app: "/^Digital Colou?r Meter$/", float: true },
      ],

      // Stack indicators: an island next to each stack with one app icon per window
      indicator: {
        // "auto" (outside, on the side nearer the screen edge), "left", "right", "insideLeft", "insideRight"
        side: "auto",
        offsetX: 4,
        offsetY: 2,
        width: 28,
        cellHeight: 22,
        gap: 2,
        padding: 3,
        titles: "hover", // or "never"
        clickToFocus: true,
        scrollToCycle: true,
        unfocusedOpacity: 0.6,
        fadeMs: 150,
      },

      appearance: {
        font: "GeistMono Nerd Font",
        fontSize: 12,
        appFont: "sketchybar-app-font",
        appIconSize: 14,
        radius: 9,
        cellRadius: 7,
        borderWidth: 1,
        shadow: true,
        colors: {
          island: "0xeb1d1d16",
          islandHi: "0xff2b2b22",
          border: "0x1affffff",
          fg: "0xfffbfbf9",
          muted: "0xffabab9c",
          dim: "0xff5f5f52",
          accent: "0xffead186",
          wave: "0xff8698eb",
          good: "0xff43d58f",
          bad: "0xffff6467",
        },
      },

      icons: {
        map: "~/.config/sketchybar/helpers/app_icons.lua",
        overrides: {},
      },

      // Shell commands with $PAW_WORKSPACE / $PAW_PREV_WORKSPACE, $PAW_APP / $PAW_WINDOW;
      // windowsChanged runs when windows open, close or change workspace (read `paw query --json`)
      hooks: {
        workspaceChanged: "",
        windowFocused: "",
        windowsChanged: "",
      },

      // `paw initiate` ("Initiate workspace"): opens the apps, waits for their windows, then
      // arranges every preset. apps: [] means every plain app name in the presets.
      initiate: {
        apps: [],
        focus: "",
        timeout: 15,
      },

      openAtLogin: false,

      // Keys: cmd ctrl alt shift fn hyper meh, lalt/ralt (and lcmd, rctrl…), a key name or 0x keycode.
      // Commands (also `paw <command>`; chain with ";"):
      //   focus west|east|north|south|stack.next|stack.prev   swap|warp|stack <dir>   unstack [all]
      //   layout bsp|stack|float   toggle float|zoom|split   balance   rotate 90|180|270
      //   resize <dir> <points>   grid rows:cols:x:y:w:h   workspace <n>|next|prev|last|new|close
      //   move-to <n>|next|prev [--follow]   display <dir>|next|n   move-to-display <dir> [--follow]
      //   arrange [workspace]   retile   recover   reload   exec <shell command>
      // Setting bindings replaces this whole list.
      bindings: {

    """

    static let tail = """
      },
    }

    """
}
