import Foundation
import Testing
@testable import PawCore

struct ConfigTests {
    func load(_ s: String) throws -> PawConfig { try ConfigLoader.decode(Data(s.utf8)) }

    @Test func emptyIsDefault() throws {
        #expect(try load("") == PawConfig())
        #expect(try load("// nothing\n{ }") == PawConfig())
    }

    @Test func glassStyleAndTintAreSetAndKeptAcrossThemes() throws {
        #expect(try load("").appearance.glassStyle == "regular")
        #expect(try load("").appearance.glassTint == 0.2)
        let c = try load("{ appearance: { theme: 'modern', glassStyle: 'clear', glassTint: 1.5 } }")
        #expect(c.appearance.glassStyle == "clear")
        #expect(c.appearance.glassTint == 1, "clamped to 0…1")
        let reset = c.appearance.resetToTheme("solarpunk")
        #expect(reset.glassStyle == "clear" && reset.glassTint == 1)
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

    @Test func updatesDefaultToCheckAndAsk() throws {
        #expect(PawConfig().updates == .init())
        #expect(PawConfig().updates.check && !PawConfig().updates.automatic)
        let c = try load("{ updates: { automatic: true } }")
        #expect(c.updates.check && c.updates.automatic)
        #expect(ConfigLoader.unknownKeys(Data("{ updates: { auto: true } }".utf8)) == ["updates.auto"])
    }

    @Test func updateChannelFollowsTheRunningVersionUnlessSet() throws {
        let auto = PawConfig.Updates()
        #expect(auto.wantsBeta(running: "0.2.0-beta.3"))
        #expect(!auto.wantsBeta(running: "0.2.0"))
        #expect(!auto.wantsBeta(running: "0.2.0+abc1234.dirty"))
        #expect(try load("{ updates: { channel: \"beta\" } }").updates.wantsBeta(running: "0.2.0"))
        #expect(try !load("{ updates: { channel: \"stable\" } }").updates.wantsBeta(running: "0.2.0-beta.3"))
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

    @Test func nestedUnknownKeysAreReported() {
        let text = """
        {
          layout: { padding: { top: 1, lef: 2 } },
          rules: [{ app: "Finder", flaot: true }, { app: "Zed", workspace: "2" }],
          workspaces: { code: { layuot: "bsp", tiles: [{ apps: ["Zed"], szie: 2 }] } },
          setups: { home: { displys: ["DELL"], workspaces: { web: { tiles: [{ app: ["Brave"] }] } } } },
          mouse: { gestures: [{ button: "middle", direction: "left", comand: "focus west" }] },
        }
        """
        #expect(ConfigLoader.unknownKeys(Data(text.utf8)) == [
            "layout.padding.lef", "mouse.gestures[0].comand", "rules[0].flaot",
            "workspaces.code.layuot", "workspaces.code.tiles[0].szie",
            "setups.home.displys", "setups.home.workspaces.web.tiles[0].app",
        ])
    }

    /// Rules and gestures decode with synthesized keys; the lists unknownKeys checks must match them.
    @Test func ruleAndGestureKeyListsMatchTheirFields() throws {
        let rule = PawConfig.Rule(app: "A", title: "t", unlessTitle: "u", manage: true, float: true, workspace: "1")
        let ruleKeys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any]
        #expect(Set(ruleKeys?.keys.map { $0 } ?? []) == ConfigLoader.ruleKeys)
        let gesture = PawConfig.Gesture(button: "middle", direction: "left", command: "balance")
        let gestureKeys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(gesture)) as? [String: Any]
        #expect(Set(gestureKeys?.keys.map { $0 } ?? []) == ConfigLoader.gestureKeys)
    }

    @Test func modeBindingsAreChecked() {
        var c = PawConfig()
        c.modes = ["resize": ["escap": "mode exit", "h": "fly away", "escape": "mode exit"]]
        #expect(ConfigLoader.warnings(c).count == 2, "\(ConfigLoader.warnings(c))")
    }

    @Test func templateParsesToDefaults() throws {
        #expect(try load(ConfigTemplate.text) == PawConfig())
        #expect(ConfigLoader.unknownKeys(Data(ConfigTemplate.text.utf8)).isEmpty)
    }

    @Test func automaticBorderRadiusKeepsManualFallbackAndRoundTrips() throws {
        let legacy = try load("{ border: { enabled: true, radius: 20 } }")
        #expect(legacy.border.autoRadius)
        #expect(legacy.border.radius == 20)
        let manual = try load("{ border: { autoRadius: false, radius: 0 } }")
        #expect(!manual.border.autoRadius && manual.border.radius == 0)
        let text = ConfigTemplate.render(manual)
        #expect(try load(text) == manual)
        #expect(ConfigLoader.unknownKeys(Data(text.utf8)).isEmpty)
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

    @Test func defaultRulesFloatUtilitiesAndPopups() {
        let rules = PawConfig().rules
        func floats(_ app: String, _ title: String) -> Bool { rules.contains { $0.matches(app: app, title: title) && $0.float == true } }
        #expect(floats("System Settings", "Wi-Fi"))
        #expect(floats("Brave Browser", "Bitwarden"))
        #expect(!floats("Brave Browser", "GitHub - Brave"))
        #expect(!floats("Discord", "#general"))
    }

    @Test func initiateOpensPresetApps() throws {
        let c = try ConfigLoader.decode(Data("""
        { workspaces: { "2": { tiles: [ { apps: ["Mail", "/^T3/"] } ] }, "10": { tiles: [ { apps: ["Finder"] } ] },
                        "1": { tiles: [ { apps: ["Safari", "Mail"] } ] } } }
        """.utf8))
        #expect(c.initiate.appsToOpen(c.workspaces) == ["Safari", "Mail", "Finder"])
        var i = c.initiate
        i.apps = ["Slack"]
        #expect(i.appsToOpen(c.workspaces) == ["Slack"])
    }

    @Test func renderRoundTrips() throws {
        let c = try ConfigLoader.decode(Data("""
        { layout: { unassignedWorkspace: "4", barTop: 41 },
          workspaces: { "1": { layout: "stack", tiles: [ { apps: ["Brave Browser"] } ] } },
          autoSwitchSetups: false,
          setups: { home: { displays: ["builtin", "DELL"], focus: "9", autoSwitch: true,
            workspaces: { "1": { display: "builtin" },
                          "8": { display: "DELL", layout: "stack", tiles: [ { apps: ["Discord", "Spotify"] } ] },
                          "9": { layout: "bsp", axis: "vertical", tiles: [ { apps: ["Brave Browser"], size: 2 }, { apps: ["/^T3/"] } ] } } } },
          rules: [ { app: "Slack", workspace: "9", title: "say \\"hi\\"" } ],
          icons: { colors: { "Brave Browser": "#fb542b" } },
          bindings: { "hyper+i": "initiate" } }
        """.utf8))
        let text = ConfigTemplate.render(c)
        #expect(try ConfigLoader.decode(Data(text.utf8)) == c)
        #expect(ConfigLoader.unknownKeys(Data(text.utf8)).isEmpty)
    }

    @Test func themeIsTheBaseOfAppearance() throws {
        let c = try ConfigLoader.decode(Data("{ appearance: { theme: 'cyberpunk', radius: 5, colors: { accent: '#ff0000' } } }".utf8))
        let t = try #require(Themes.named("cyberpunk"))
        #expect(c.appearance.font == t.appearance.font)
        #expect(c.appearance.colors.island == t.appearance.colors.island)
        #expect(c.appearance.radius == 5)
        #expect(c.appearance.colors.accent == ARGB(0xffff_0000))
        #expect(c.appearance.overrides == ["radius", "colors.accent"])
        #expect(c.appearance.resetToTheme().overrides.isEmpty)
        #expect(Themes.og.appearance == PawConfig.Appearance())
    }

    @Test func glassIsOnByDefaultAndSurvivesThemes() throws {
        #expect(PawConfig().appearance.glass)
        #expect(Themes.all.allSatisfy { $0.appearance.glass })
        func load(_ s: String) throws -> PawConfig { try ConfigLoader.decode(Data(s.utf8)) }
        let c = try load("{ appearance: { theme: 'minimal', glass: false } }")
        #expect(!c.appearance.glass)
        #expect(c.appearance.radius == Themes.minimal.appearance.radius)
        #expect(!c.appearance.resetToTheme("og").glass, "switching themes keeps glass off")
        #expect(ConfigLoader.unknownKeys(Data("{ appearance: { glass: false } }".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try load("{ appearance: { glass: 'yes' } }") }
        #expect(ConfigTemplate.appearance(c.appearance).contains("\n    glass: false,"))
        #expect(ConfigTemplate.appearance(PawConfig().appearance).contains("// glass: true,"))
    }

    @Test func themesRoundTrip() throws {
        for t in Themes.all {
            var c = PawConfig()
            c.appearance = t.appearance
            c.appearance.fontSize += 1
            let text = ConfigTemplate.render(c)
            #expect(try ConfigLoader.decode(Data(text.utf8)) == c)
            #expect(ConfigLoader.unknownKeys(Data(text.utf8)).isEmpty)
            #expect(ConfigLoader.warnings(c).isEmpty)
        }
        let bad = try ConfigLoader.decode(Data("{ appearance: { theme: 'nope', fontWeight: 'heavy' } }".utf8))
        #expect(ConfigLoader.warnings(bad).contains { $0.hasPrefix("appearance.theme") })
        #expect(ConfigLoader.warnings(bad).contains { $0.hasPrefix("appearance.fontWeight") })
    }

    @Test func setupMatchesDisplays() throws {
        let s = PawConfig.Setup(displays: ["builtin", "DELL", "external"])
        #expect(s.matches([("Built-in Retina Display", true), ("Gigabyte M32U", false), ("DELL U2717D", false)]))
        #expect(!s.matches([("Built-in Retina Display", true), ("DELL U2717D", false)]))
        #expect(!s.matches([("Built-in Retina Display", true), ("LG", false), ("Gigabyte", false)]))
    }

    @Test func autoSwitchPicksASetup() throws {
        let home: [(name: String, builtin: Bool)] = [("Built-in Retina Display", true), ("DELL U2717D", false)]
        let laptop: [(name: String, builtin: Bool)] = [("Built-in Retina Display", true)]
        let other: [(name: String, builtin: Bool)] = [("Built-in Retina Display", true), ("LG", false)]
        var c = PawConfig()
        c.setups = ["home": .init(displays: ["builtin", "DELL"]), "focus": .init(displays: ["builtin", "DELL"]),
                    "laptop": .init(displays: ["builtin"])]
        // Several setups for the same displays: the one picked last, else the first by name.
        #expect(c.matchingSetups(for: home) == ["focus", "home"])
        #expect(c.autoSetup(for: home) == "focus")
        #expect(c.autoSetup(for: home, preferred: "home") == "home")
        #expect(c.autoSetup(for: home, preferred: "laptop") == "focus")
        #expect(c.setupAfterDisplayChange(laptop, preferred: nil, current: "home") == "laptop")
        // No setup for these displays: the default workspaces.
        #expect(c.setupAfterDisplayChange(other, preferred: nil, current: "home") == nil)
        // A setup that doesn't switch by itself is left out; with none left the setup stays.
        c.setups["focus"]?.autoSwitch = false
        #expect(c.autoSetup(for: home) == "home")
        c.setups["home"]?.autoSwitch = false
        #expect(c.setupAfterDisplayChange(home, preferred: nil, current: "laptop") == "laptop")
        #expect(c.setupAfterDisplayChange(home, preferred: nil, current: "gone") == nil)
        // Off for every setup: nothing changes, unless a setup opts in.
        c = PawConfig()
        c.autoSwitchSetups = false
        c.setups = ["home": .init(displays: ["builtin", "DELL"]), "laptop": .init(displays: ["builtin"], autoSwitch: true)]
        #expect(c.setupAfterDisplayChange(home, preferred: nil, current: "laptop") == "laptop")
        #expect(c.setupAfterDisplayChange(other, preferred: nil, current: "home") == "home")
        #expect(c.setupAfterDisplayChange(laptop, preferred: nil, current: "home") == "laptop")
        #expect(PawConfig.arrangementKey(home) == PawConfig.arrangementKey(home.reversed()))
    }
}
