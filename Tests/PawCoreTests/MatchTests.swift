import Foundation
import Testing
@testable import PawCore

struct FuzzyTests {
    @Test func substringBeatsScattered() throws {
        let sub = try #require(FuzzyMatcher.score("save", in: "Save Document"))
        let scattered = try #require(FuzzyMatcher.score("save", in: "Show all versions everywhere"))
        #expect(sub > scattered)
    }

    @Test func wordStartBeatsMiddle() throws {
        let start = try #require(FuzzyMatcher.score("port", in: "Port settings"))
        let middle = try #require(FuzzyMatcher.score("port", in: "Import"))
        #expect(start > middle)
    }

    @Test func foldsCaseAndDiacritics() {
        #expect(FuzzyMatcher.score("cafe", in: "Café Menu") != nil)
        #expect(FuzzyMatcher.score("ZAPRI", in: "zapri okno") != nil)
        #expect(FuzzyMatcher.score("cevapcici", in: "Čevapčiči") != nil)
    }

    @Test func everyWordMustMatch() {
        #expect(FuzzyMatcher.score("new tab", in: "New Tab") != nil)
        #expect(FuzzyMatcher.score("new zzz", in: "New Tab") == nil)
        #expect(FuzzyMatcher.score("xyz", in: "abc") == nil)
        #expect(FuzzyMatcher.score("", in: "abc") == nil)
    }

    @Test func acronymsMatch() throws {
        let s = try #require(FuzzyMatcher.score("gh", in: "Go Home"))
        #expect(s > 0)
    }

    @Test func exactBeatsLonger() throws {
        let exact = try #require(FuzzyMatcher.score("Back", in: "Back"))
        let longer = try #require(FuzzyMatcher.score("Back", in: "Background color"))
        #expect(exact > longer)
    }

    @Test func weightedFields() throws {
        let title = try #require(FuzzyMatcher.best("reload", fields: [("Reload", 1.0), (nil, 0.9)]))
        let role = try #require(FuzzyMatcher.best("reload", fields: [(nil, 1.0), ("Reload", 0.3)]))
        #expect(title > role)
    }
}

struct ScrollTests {
    @Test func rampsUpToFullSpeed() {
        let p = ScrollPhysics(speed: 2, fastMultiplier: 3, rampMs: 100, startFraction: 0.5)
        #expect(p.rate(heldMs: 0, fast: false) == 1)
        #expect(p.rate(heldMs: 100, fast: false) == 2)
        #expect(p.rate(heldMs: 1000, fast: true) == 6)
        #expect(p.rate(heldMs: 50, fast: false) > 1)
    }

    @Test func carriesFractions() {
        var p = ScrollPhysics(speed: 0.1, fastMultiplier: 1, rampMs: 0)
        var total = 0
        for _ in 0..<120 { total += p.step(dtMs: 8.333, heldMs: 500, dx: 0, dy: -1, fast: false).y }
        // 0.1 px/ms for ~1 s
        #expect(abs(total + 100) <= 1)
    }

    @Test func directions() {
        var p = ScrollPhysics(speed: 1, fastMultiplier: 1, rampMs: 0)
        let d = p.step(dtMs: 10, heldMs: 0, dx: 1, dy: 1, fast: false)
        #expect(d.x == 10 && d.y == 10)
    }
}

struct RuleTests {
    @Test func clickableRoles() {
        #expect(ElementRules.isClickable(role: "AXButton", subrole: nil, actions: nil, parentRole: nil))
        #expect(ElementRules.isClickable(role: "AXImage", subrole: nil, actions: ["AXPress"], parentRole: nil))
        #expect(!ElementRules.isClickable(role: "AXImage", subrole: nil, actions: [], parentRole: nil))
        #expect(!ElementRules.isClickable(role: "AXWindow", subrole: nil, actions: ["AXPress"], parentRole: nil))
        #expect(!ElementRules.isClickable(role: "AXCell", subrole: nil, actions: nil, parentRole: "AXRow"))
        #expect(ElementRules.isClickable(role: "AXCell", subrole: nil, actions: nil, parentRole: "AXList"))
        #expect(ElementRules.prefersMouse(role: "AXTextField"))
        #expect(!ElementRules.prefersMouse(role: "AXButton"))
    }
}

struct ColorTests {
    @Test func parsesSketchybarAndCSS() {
        #expect(ARGB.parse("0xeb1d1d16") == ARGB(0xeb1d_1d16))
        #expect(ARGB.parse("0x1d1d16") == ARGB(0xff1d_1d16))
        #expect(ARGB.parse("#ead186") == ARGB(0xffea_d186))
        #expect(ARGB.parse("#ead18680") == ARGB(0x80ea_d186))
        #expect(ARGB.parse("nope") == nil)
        let c = ARGB(0xeb1d_1d16)
        #expect(abs(c.alpha - 235.0 / 255) < 0.001)
        #expect(c.withAlpha(1).value == 0xff1d_1d16)
        #expect(c.description == "0xeb1d1d16")
    }
}

struct IconTests {
    @Test func bundledMapMatchesSketchybar() {
        let m = AppIconMap.bundled
        #expect(m.exact.count > 500)
        #expect(m.glyph(for: "Safari") == ":safari:")
        #expect(m.glyph(for: "Adobe Photoshop 2026") == ":photoshop:")
        #expect(m.glyph(for: "Some Unknown App") == ":default:")
    }

    @Test func parsesLuaWithEscapes() {
        let lua = """
        local M = { exact = {
          ["Foo \\"Bar\\""] = ":foo:",
          ["Zed"] = ":zed:",
        }, prefix = {
          { "Adobe X", ":x:" },
        }, default = ":def:" }
        """
        let m = AppIconMap.parse(lua: lua)
        #expect(m.glyph(for: "Foo \"Bar\"") == ":foo:")
        #expect(m.glyph(for: "Adobe X 2") == ":x:")
        #expect(m.glyph(for: "nope") == ":def:")
        #expect(m.merging(["Zed": ":code:"]).glyph(for: "Zed") == ":code:")
    }
}
