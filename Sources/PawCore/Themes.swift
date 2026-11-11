import Foundation

/// A ready-made look for every indicator: colours, fonts and shape. `appearance.theme` names one;
/// the other appearance keys override it.
public struct IndicatorTheme: Sendable, Equatable {
    public let id: String
    public let label: String
    public let summary: String
    public let light: Bool
    public let appearance: PawConfig.Appearance
    /// The focus border's colour in this theme.
    public let borderColor: ARGB
}

public enum Themes {
    public static let weights = ["regular", "medium", "semibold", "bold"]

    public static func named(_ id: String) -> IndicatorTheme? { all.first { $0.id == id.lowercased() } }

    /// The theme's appearance (OG for a name paw doesn't know), with `theme` set to `id`.
    public static func appearance(_ id: String) -> PawConfig.Appearance {
        var a = named(id)?.appearance ?? og.appearance
        a.theme = id
        return a
    }

    public static let all: [IndicatorTheme] = [og, ogLight, modern, minimal, solarpunk, cyberpunk]

    private static func make(_ id: String, _ label: String, _ summary: String, light: Bool, border: ARGB,
                             _ edit: (inout PawConfig.Appearance) -> Void) -> IndicatorTheme {
        var a = PawConfig.Appearance()
        edit(&a)
        a.theme = id
        return IndicatorTheme(id: id, label: label, summary: summary, light: light, appearance: a, borderColor: border)
    }

    private static func palette(_ island: UInt32, _ islandHi: UInt32, _ border: UInt32, _ fg: UInt32, _ muted: UInt32,
                                _ dim: UInt32, _ accent: UInt32, _ wave: UInt32, _ good: UInt32, _ bad: UInt32) -> PawConfig.Colors {
        var c = PawConfig.Colors()
        c.island = ARGB(island); c.islandHi = ARGB(islandHi); c.border = ARGB(border); c.fg = ARGB(fg); c.muted = ARGB(muted)
        c.dim = ARGB(dim); c.accent = ARGB(accent); c.wave = ARGB(wave); c.good = ARGB(good); c.bad = ARGB(bad)
        return c
    }

    /// paw's own look (the defaults): sketchybar islands, olive-black and gold.
    public static let og = make("og", "OG", "Olive-black islands, gold accent, Geist Mono.", light: false,
                                border: ARGB(0xccea_d186)) { _ in }

    public static let ogLight = make("og-light", "OG Light", "The original, in daylight.", light: true,
                                     border: ARGB(0xcc00_8236)) { a in
        a.shadowOpacity = 0.18
        a.colors = palette(0xf2fb_fbf9, 0xffe8_e8e3, 0x1f0c_0c09, 0xff0c_0c09, 0xff73_735e,
                           0xffab_ab9c, 0xff00_8236, 0xff00_7abf, 0xff00_884b, 0xffdd_0000)
    }

    public static let modern = make("modern", "Modern", "Warm charcoal, SF Pro, softer corners, clay accent.", light: false,
                                    border: ARGB(0xccd9_7757)) { a in
        a.font = "system"
        a.fontSize = 12.5
        a.radius = 12
        a.cellRadius = 8
        a.islandHeight = 30
        a.shadowOpacity = 0.3
        a.shadowRadius = 8
        a.colors = palette(0xf026_2624, 0xff3a_3a37, 0x17ff_ffff, 0xfffa_f9f5, 0xffc2_c0b6,
                           0xff76_746c, 0xffd9_7757, 0xff6b_a8ed, 0xff79_ce98, 0xfff0_7a74)
    }

    public static let minimal = make("minimal", "Minimal", "Black glass, no border or shadow, white accent.", light: false,
                                     border: ARGB(0x99ff_ffff)) { a in
        a.font = "system"
        a.fontWeight = "regular"
        a.boldWeight = "medium"
        a.radius = 6
        a.cellRadius = 4
        a.borderWidth = 0
        a.shadow = false
        a.pills = false
        a.hudOpacity = 0.9
        a.edgeOpacity = 0.6
        a.colors = palette(0xd900_0000, 0x2eff_ffff, 0x00ff_ffff, 0xffff_ffff, 0xa6ff_ffff,
                           0x59ff_ffff, 0xffff_ffff, 0xffff_ffff, 0xff8c_e0a8, 0xffff_8a80)
    }

    public static let solarpunk = make("solarpunk", "Solarpunk", "Sunlit paper, moss and brass, DM Mono.", light: true,
                                       border: ARGB(0xcc27_762f)) { a in
        a.font = "DM Mono"
        a.radius = 12
        a.cellRadius = 8
        a.shadowOpacity = 0.15
        a.shadowRadius = 6
        a.colors = palette(0xf5ff_fcf1, 0xfff0_ecd7, 0xffda_d5b8, 0xff12_2d19, 0xff54_674a,
                           0xff9a_a58c, 0xff27_762f, 0xff00_929f, 0xff1c_7634, 0xffc5_2f15)
    }

    public static let cyberpunk = make("cyberpunk", "Cyberpunk", "Neon on night glass, square corners, Share Tech Mono.",
                                       light: false, border: ARGB(0xfff3_25c4)) { a in
        a.font = "Share Tech Mono"
        a.fontSize = 13
        a.fontWeight = "regular"
        a.boldWeight = "regular"
        a.radius = 2
        a.cellRadius = 1
        a.pills = false
        a.shadowOpacity = 0.6
        a.shadowRadius = 8
        a.colors = palette(0xeb0f_0c1d, 0xff1a_172c, 0x5900_d8e1, 0xffd8_f5f6, 0xff85_bbc9,
                           0xff4a_5f78, 0xfff3_25c4, 0xff00_ebec, 0xff56_f487, 0xffff_3b6b)
    }
}
