/// The commented config paw writes to `~/.config/paw/config.json5` on first launch
/// (`paw config template` prints it). Every value here is the default.
public enum ConfigTemplate {
    public static let text = """
    // paw configuration (JSON5: comments and trailing commas are fine).
    // Saved changes apply immediately. Delete a key to use its default.
    {
      yabai: {
        path: "/opt/homebrew/bin/yabai",
        // paw adds yabai signals (label paw_*) that run `paw refresh` when windows or spaces
        // change, and removes them when it quits.
        signals: true,
        // Also refresh every N seconds, in case a change has no signal; 0 turns it off.
        pollSeconds: 5,
        // Windows whose frames differ by less than this many points are one stack.
        fuzz: 30,
      },

      indicator: {
        // "auto" puts it outside the window on the side nearer the screen edge (like
        // stackline); also "left", "right", "insideLeft", "insideRight".
        side: "auto",
        offsetX: 4,
        offsetY: 2,
        width: 28,
        cellHeight: 22,
        gap: 2,
        padding: 3,
        // An island with the window title next to the icon under the pointer: "hover" or "never"
        titles: "hover",
        clickToFocus: true,
        // Scroll over the indicator to move through the stack
        scrollToCycle: true,
        // Stacks without focus fade to this
        unfocusedOpacity: 0.6,
        fadeMs: 150,
      },

      appearance: {
        font: "GeistMono Nerd Font", // titles; falls back to SF Mono
        fontSize: 12,
        appFont: "sketchybar-app-font",
        appIconSize: 14,
        radius: 9,
        cellRadius: 7,
        borderWidth: 1,
        shadow: true,
        // 0xAARRGGBB like sketchybar's colors.lua, or "#RRGGBB" / "#RRGGBBAA"
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
        // sketchybar's app → glyph map; paw's built-in copy is used when it's missing.
        map: "~/.config/sketchybar/helpers/app_icons.lua",
        overrides: {
          // "My App": ":code:",
        },
      },

      // App names whose windows are left out of indicators.
      excludedApps: [],
      openAtLogin: false,
    }

    """
}
