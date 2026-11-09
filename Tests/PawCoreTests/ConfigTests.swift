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
          excludedApps: ["Finder"],
        }
        """)
        #expect(c.indicator.side == .insideRight)
        #expect(c.indicator.width == 32)
        #expect(c.indicator.cellHeight == 22)
        #expect(c.appearance.colors.accent == ARGB(0xff86_98eb))
        #expect(c.appearance.colors.island == ARGB(0xff1d_1d16))
        #expect(c.appearance.colors.fg == ARGB(0xfffb_fbf9))
        #expect(c.yabai.path == "/opt/homebrew/bin/yabai")
        #expect(c.excludedApps == ["Finder"])
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
        let keys = ConfigLoader.unknownKeys(Data("{ yabi: {}, indicator: { sid: 'left' }, appearance: { colors: { gold: 1 } }, icons: { overrides: { Any: ':x:' } } }".utf8))
        #expect(keys == ["appearance.colors.gold", "indicator.sid", "yabi"])
    }

    @Test func templateParsesToDefaults() throws {
        #expect(try load(ConfigTemplate.text) == PawConfig())
        #expect(ConfigLoader.unknownKeys(Data(ConfigTemplate.text.utf8)).isEmpty)
    }

    @Test func warnings() {
        var c = PawConfig()
        c.indicator.titles = "always"
        c.yabai.path = "/nonexistent/yabai"
        #expect(ConfigLoader.warnings(c).count == 2)
    }
}
