import Foundation
import Testing
@testable import PawCore

/// Regressions from the 2026-11-10 security audit.
struct SecurityTests {
    @Test func catastrophicPatternStopsAtDeadline() {
        let title = String(repeating: "a", count: 40) + "X"
        let start = Date()
        #expect(!PawConfig.Rule.text("/^(a+)+$/", title))
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(PawConfig.Rule.text("/^(a+)+$/", "aaaa"))
    }

    @Test func patternsStillMatch() {
        #expect(PawConfig.Rule.text("/^Digital Colou?r Meter$/", "digital color meter"))
        #expect(!PawConfig.Rule.text("/^Digital Colou?r Meter$/", "Digital Colour Meters"))
        #expect(PawConfig.Rule.text("paw", "~/repos/PAW"))
        #expect(AppMatcher.matches("/^(He3|Ghostty)$/", "ghostty"))
        #expect(!AppMatcher.matches("/[/", "anything")) // does not compile: no match, no crash
        #expect(AppMatcher.matches("Safari", "safari"))
    }

    @Test func longTitlesAreCapped() {
        let title = String(repeating: "x", count: 100_000) + "needle"
        #expect(!PawConfig.Rule.text("/needle/", title))
        #expect(PawConfig.Rule.text("/needle/", String(repeating: "x", count: 100) + "needle"))
    }

    @Test func saturatingInt() {
        #expect(Int(saturating: .nan) == 0)
        #expect(Int(saturating: .infinity) == .max)
        #expect(Int(saturating: -.infinity) == .min)
        #expect(Int(saturating: 1e300) == .max)
        #expect(Int(saturating: 12.9) == 12)
    }

    @Test func outOfRangeNumbersWarnAndClamp() throws {
        let c = try ConfigLoader.decode(Data("""
        {
          layout: { gap: Infinity, workspaces: 0 },
          appearance: { appIconSize: 1e300, fontSize: NaN },
          workspaces: { "1": { tiles: [ { apps: ["Safari"], size: 1e20 } ] } },
        }
        """.utf8))
        let w = ConfigLoader.warnings(c)
        #expect(w.contains { $0.hasPrefix("layout.gap:") })
        #expect(w.contains { $0.hasPrefix("layout.workspaces:") })
        #expect(w.contains { $0.hasPrefix("appearance.appIconSize:") })
        #expect(w.contains { $0.hasPrefix("appearance.fontSize:") })
        #expect(w.contains { $0.hasPrefix("workspaces.1.tiles[0].size:") })
        let k = c.clamped()
        #expect(k.layout.gap == 500)
        #expect(k.layout.workspaces == 1)
        #expect(k.appearance.appIconSize == 200)
        #expect(k.appearance.fontSize == PawConfig().appearance.fontSize)
        #expect(k.workspaces["1"]?.tiles[0].size == 100)
        #expect(k.rangeWarnings.isEmpty)
        _ = k.workspaces["1"]!.tilesText // used to trap on Int(1e20)
    }

    @Test func defaultsAreInRange() {
        #expect(PawConfig().rangeWarnings.isEmpty)
        #expect(PawConfig().clamped() == PawConfig())
    }
}
