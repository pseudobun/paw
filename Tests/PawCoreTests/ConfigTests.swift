import Foundation
import Testing
@testable import PawCore

struct ConfigTests {
    func load(_ s: String) throws -> PawConfig { try ConfigLoader.decode(Data(s.utf8)) }

    @Test func emptyIsDefault() throws {
        #expect(try load("") == PawConfig())
        #expect(try load("// nothing\n{ }") == PawConfig())
    }

    @Test func partialJSON5KeepsDefaults() throws {
        let c = try load("""
        {
          indicator: { side: 'inside-right', width: 32, },
          appearance: { colors: { accent: 0xff8698eb, island: "#1d1d16" } },
        }
        """)
        #expect(c.indicator.side == .insideRight)
        #expect(c.indicator.width == 32)
        #expect(c.indicator.cellHeight == 22)
        #expect(c.appearance.colors.accent == ARGB(0xff86_98eb))
        #expect(c.appearance.colors.island == ARGB(0xff1d_1d16))
        #expect(c.appearance.colors.fg == ARGB(0xfffb_fbf9))
        #expect(c.bindings["ctrl+left"] == "focus west")
    }

    @Test func errorsNameThePath() {
        do {
            _ = try load("{ appearance: { colors: { fg: 'purple' } } }")
            Issue.record("expected an error")
        } catch let p as ConfigProblem {
            #expect(p.message.contains("appearance.colors.fg"))
        } catch { Issue.record("\(error)") }
        #expect(throws: ConfigProblem.self) { try load("{ indicator: { side: 'top' } }") }
        #expect(throws: ConfigProblem.self) { try load("{ yabai: ") }
    }

    @Test func unknownKeysAreReported() {
        let keys = ConfigLoader.unknownKeys(Data("{ yabi: {}, indicator: { sid: 'left' }, appearance: { colors: { gold: 1 } }, icons: { overrides: { Any: ':x:' } }, bindings: { 'ctrl+x': 'balance' } }".utf8))
        #expect(keys == ["appearance.colors.gold", "indicator.sid", "yabi"])
    }

    @Test func templateParsesToDefaults() throws {
        #expect(try load(ConfigTemplate.text) == PawConfig())
        #expect(ConfigLoader.unknownKeys(Data(ConfigTemplate.text.utf8)).isEmpty)
    }

    @Test func warnings() {
        var c = PawConfig()
        #expect(ConfigLoader.warnings(c).isEmpty, "\(ConfigLoader.warnings(c))")
        c.indicator.titles = "always"
        c.bindings = ["ctrl+nope": "balance", "ctrl+x": "fly away", "control+y": "balance", "ctrl+y": "balance"]
        #expect(ConfigLoader.warnings(c).count == 4)
    }
}

struct PresetConfigTests {
    @Test func decodesWorkspacesAndRules() throws {
        let c = try ConfigLoader.decode(Data("""
        {
          workspaces: { "1": { layout: "bsp", tiles: [ { apps: ["Discord", "Spotify"] }, { apps: ["Ghostty"], size: 2 } ] } },
          rules: [ { app: "/^Zoom/", float: true }, { app: "Slack", workspace: "3" } ],
          bindings: { "ralt+1": "workspace 1" },
          animation: { curve: "spring", durationMs: 250 },
        }
        """.utf8))
        let p = try #require(c.workspaces["1"])
        #expect(p.tiles.count == 2 && p.tiles[1].size == 2 && p.axis == .horizontal)
        #expect(p.slot(for: "Spotify") == 0)
        #expect(c.rules.count == 2)
        #expect(c.rules[0].matches(app: "Zoom Workplace", title: ""))
        #expect(c.bindings == ["ralt+1": "workspace 1"])
        #expect(c.animation.curve == .spring)
    }

    @Test func defaultRulesMatchYabairc() {
        let rules = PawConfig().rules
        func floats(_ app: String, _ title: String) -> Bool { rules.contains { $0.matches(app: app, title: title) && $0.float == true } }
        #expect(floats("System Settings", "Wi-Fi"))
        #expect(floats("Brave Browser", "Bitwarden"))
        #expect(!floats("Brave Browser", "GitHub - Brave"))
        #expect(!floats("Discord", "#general"))
    }
}
