import Foundation
import Testing
@testable import PawCore

struct ConfigTests {
    func load(_ s: String) throws -> PawConfig { try ConfigLoader.decode(Data(s.utf8)) }

    @Test func emptyIsDefault() throws {
        #expect(try load("") == PawConfig())
        #expect(try load("{}") == PawConfig())
        #expect(try load("// nothing\n{ }") == PawConfig())
    }

    @Test func partialJSON5KeepsDefaults() throws {
        let c = try load("""
        // comment
        {
          hint: { charset: 'fjdksla', menuBar: false, },
          appearance: { colors: { accent: 0xff8698eb, island: "#1d1d16", bad: "0xffff0000" }, labelAnchor: "center" },
          excludedApps: ["com.apple.Terminal"],
        }
        """)
        #expect(c.hint.charset == "fjdksla")
        #expect(c.hint.menuBar == .off)
        #expect(c.hint.hotkey == "cmd+shift+space")
        #expect(c.appearance.colors.accent == ARGB(0xff86_98eb))
        #expect(c.appearance.colors.island == ARGB(0xff1d_1d16))
        #expect(c.appearance.colors.bad == ARGB(0xffff_0000))
        #expect(c.appearance.colors.fg == ARGB(0xfffb_fbf9))
        #expect(c.appearance.labelAnchor == .center)
        #expect(c.excludedApps == ["com.apple.Terminal"])
    }

    @Test func errorsNameThePath() {
        #expect(throws: ConfigProblem.self) { try load("{ hint: { maxElements: 'lots' } }") }
        do {
            _ = try load("{ appearance: { colors: { fg: 'purple' } } }")
            Issue.record("expected an error")
        } catch let p as ConfigProblem {
            #expect(p.message.contains("appearance.colors.fg"))
        } catch { Issue.record("\(error)") }
        #expect(throws: ConfigProblem.self) { try load("{ hint: ") }
    }

    @Test func unknownKeysAreReported() {
        let keys = ConfigLoader.unknownKeys(Data("{ hnit: {}, hint: { charst: 'a' }, appearance: { colors: { gold: 1 } }, icons: { overrides: { Any: ':x:' } } }".utf8))
        #expect(keys == ["appearance.colors.gold", "hint.charst", "hnit"])
    }

    @Test func warnings() throws {
        var c = PawConfig()
        #expect(ConfigLoader.warnings(c).isEmpty)
        c.hint.hotkey = "cmd+nope"
        c.search.hotkey = ""
        c.hint.charset = "aaa"
        let w = ConfigLoader.warnings(c)
        #expect(w.count == 2)
    }

    @Test func templateParsesToDefaults() throws {
        #expect(try load(ConfigTemplate.text) == PawConfig())
        #expect(ConfigLoader.unknownKeys(Data(ConfigTemplate.text.utf8)).isEmpty)
    }

    @Test func hotkeys() throws {
        let h = try #require(HotkeySpec.parse("cmd+shift+space"))
        #expect(h.hasCommand && h.hasShift && !h.hasOption)
        #expect(HotkeySpec.parse("space") == nil)
        #expect(HotkeySpec.parse("f13") != nil)
        #expect(HotkeySpec.parse("hyper+j") != nil)
    }
}
