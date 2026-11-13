import Foundation
import Testing
@testable import PawCore

/// What a config reload changes for windows and workspaces paw already has.
struct RuleEffectsTests {
    private func config(_ rules: [PawConfig.Rule]) -> PawConfig {
        var c = PawConfig()
        c.rules = rules
        return c
    }

    @Test func floatsFollowsRulesAndTheWindowsKind() {
        let none = config([])
        #expect(!none.floats(app: "Zed", title: "", native: .none))
        #expect(none.floats(app: "Zed", title: "", native: .kind))
        #expect(none.floats(app: "Zed", title: "", native: .fixedSize))
        let tile = config([.init(app: "Zed", float: false)])
        #expect(!tile.floats(app: "Zed", title: "", native: .fixedSize), "float: false tiles a fixed-size window")
        #expect(tile.floats(app: "Zed", title: "", native: .kind), "but never a dialog")
        #expect(config([.init(app: "Zed", float: true)]).floats(app: "Zed", title: "", native: .none))
    }

    @Test func addingAFloatRuleFloatsTheWindow() {
        let old = config([]), new = config([.init(app: "Finder", float: true)])
        #expect(RuleChange.between(old, new, app: "Finder", title: "", native: .none, floating: false, on: "1") == .init(float: true))
        #expect(RuleChange.between(new, old, app: "Finder", title: "", native: .none, floating: true, on: "1") == .init(float: false))
        #expect(RuleChange.between(old, new, app: "Zed", title: "", native: .none, floating: false, on: "1") == .init(),
                "another app's rule changes nothing")
    }

    @Test func aWindowFloatedByHandStaysWhenItsRulesDidntChange() {
        let old = config([]), new = config([.init(app: "Finder", float: true)])
        #expect(RuleChange.between(old, new, app: "Zed", title: "", native: .none, floating: true, on: "1") == .init())
        #expect(RuleChange.between(new, old, app: "Finder", title: "", native: .kind, floating: true, on: "1") == .init(),
                "a dialog keeps floating without the rule")
    }

    @Test func aNewWorkspaceRuleMovesTheWindow() {
        let old = config([]), new = config([.init(app: "Slack", workspace: "4")])
        #expect(RuleChange.between(old, new, app: "Slack", title: "", native: .none, floating: false, on: "1") == .init(workspace: "4"))
        #expect(RuleChange.between(old, new, app: "Slack", title: "", native: .none, floating: false, on: "4") == .init())
        #expect(RuleChange.between(new, new, app: "Slack", title: "", native: .none, floating: false, on: "2") == .init(),
                "an unchanged rule doesn't pull back a window moved by hand")
        #expect(RuleChange.between(new, old, app: "Slack", title: "", native: .none, floating: false, on: "4") == .init(),
                "a removed rule leaves it where it is")
    }

    @Test func ignoresAndRuleWorkspace() {
        let c = config([.init(app: "Raycast", manage: false), .init(app: "/Mail/", title: "Inbox", workspace: "3")])
        #expect(c.ignores(app: "Raycast", title: ""))
        #expect(!c.ignores(app: "Zed", title: ""))
        #expect(c.ruleWorkspace(app: "Mail", title: "Inbox – 3 messages") == "3")
        #expect(c.ruleWorkspace(app: "Mail", title: "Draft") == nil)
    }

    @Test func manageTrueClaimsSelfLayeredPanels() {
        let c = config([.init(app: "Ghostty", manage: true), .init(app: "Raycast", manage: false)])
        #expect(c.forcesManage(app: "Ghostty", title: ""))
        #expect(!c.forcesManage(app: "Raycast", title: ""))
        #expect(!c.forcesManage(app: "Zed", title: ""))
    }

    @Test func presetsComeFromTheActiveSetup() {
        var c = PawConfig()
        c.workspaces = ["code": .init(tiles: [.init(apps: ["Zed"])])]
        c.setups = ["home": .init(displays: ["DELL"], workspaces: ["web": .init(tiles: [.init(apps: ["Brave"])])])]
        #expect(Array(c.presets(setup: nil).keys) == ["code"])
        #expect(Array(c.presets(setup: "home").keys) == ["web"])
        #expect(Array(c.presets(setup: "gone").keys) == ["code"])
    }

    @Test func surplusWorkspacesAreEmptyNumberedOnesAboveTheCount() {
        var l = PawConfig.Layout()
        l.workspaces = 3
        let names = ["1", "2", "3", "4", "5", "6", "7", "code", "x1"]
        let busy: Set = ["5"], kept: Set = ["6"]
        let gone = l.surplusWorkspaces(among: names, isEmpty: { !busy.contains($0) }, keep: { kept.contains($0) })
        #expect(gone == ["4", "7"])
        l.workspaces = 0
        #expect(l.surplusWorkspaces(among: ["1"], isEmpty: { _ in true }, keep: { _ in false }).isEmpty, "1 always stays")
    }
}
