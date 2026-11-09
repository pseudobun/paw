/// Bunny's yabai + skhd setup, as paw defaults (dotfiles yabai/.skhdrc and .yabairc).
public enum Defaults {
    public static let bindings: [String: String] = {
        var b: [String: String] = [
            "hyper+0x18": "exec open -a Alacritty",
            "hyper+w": "layout bsp",
            "hyper+s": "layout stack",
            "hyper+f": "layout float",
            "hyper+right": "focus stack.next",
            "hyper+left": "focus stack.prev",
            "alt+r": "rotate 270",
            "hyper+n": "workspace new",
            "hyper+d": "workspace close",
            "ralt+d": "workspace next",
            "ralt+a": "workspace prev",
            "cmd+alt+r": "recover",
            "ctrl+alt+return": "toggle zoom",
            "ctrl+alt+s": "toggle split",
            "ctrl+shift+return": "grid 1:1:0:0:1:1",
            "ctrl+alt+space": "toggle float",
            "ctrl+alt+c": "toggle float; grid 4:4:1:1:2:2",
            "ctrl+alt+u": "unstack",
            "hyper+e": "balance",
            "shift+alt+a": "resize west 40",
            "shift+alt+s": "resize south 40",
            "shift+alt+w": "resize north 40",
            "shift+alt+d": "resize east 40",
            "shift+ctrl+a": "resize west -40",
            "shift+ctrl+s": "resize south -40",
            "shift+ctrl+w": "resize north -40",
            "shift+ctrl+d": "resize east -40",
        ]
        for (key, dir) in [("left", "west"), ("right", "east"), ("up", "north"), ("down", "south")] {
            b["ctrl+\(key)"] = "focus \(dir)"
            b["ctrl+alt+\(key)"] = "swap \(dir)"
            b["ctrl+shift+\(key)"] = "stack \(dir)"
            b["cmd+shift+ctrl+\(key)"] = "warp \(dir)"
        }
        for n in 1...10 {
            let key = n == 10 ? "0" : "\(n)"
            b["ctrl+\(key)"] = "workspace \(n)"
            b["ralt+\(key)"] = "workspace \(n)"
            b["ralt+shift+\(key)"] = "move-to \(n)"
            b["cmd+ctrl+\(key)"] = "move-to \(n) --follow"
            b["cmd+ralt+\(key)"] = "move-to \(n) --follow"
        }
        return b
    }()

    public static let rules: [PawConfig.Rule] = [
        .init(app: "/^(iTerm2|He3|System Settings|Parallels Desktop|CleanShot X|Raycast|Perplexity)$/", float: true),
        .init(app: "Raycast Beta", title: "/^AI Chat$/", float: true),
        // Browser popups float; their main windows (title ends in the browser name) tile.
        .init(app: "Google Chrome", unlessTitle: "Google Chrome", float: true),
        .init(app: "Brave Browser", unlessTitle: "Brave", float: true),
        .init(app: "Zen", unlessTitle: "Zen", float: true),
        .init(app: "/^Digital Colou?r Meter$/", float: true),
    ]
}
