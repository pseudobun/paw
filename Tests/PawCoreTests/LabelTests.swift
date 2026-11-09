import CoreGraphics
import Testing
@testable import PawCore

struct LabelTests {
    func prefixFree(_ codes: [String]) -> Bool {
        for (i, a) in codes.enumerated() {
            for (j, b) in codes.enumerated() where i != j && b.hasPrefix(a) { return false }
        }
        return true
    }

    @Test func singleKeysWhenTheyFit() {
        #expect(LabelGenerator.labels(count: 3, charset: "asdfghjkl;") == ["a", "s", "d"])
        #expect(LabelGenerator.labels(count: 10, charset: "asdfghjkl;").allSatisfy { $0.count == 1 })
    }

    @Test func mixesLengthsAndStaysPrefixFree() {
        for n in [1, 2, 9, 10, 11, 50, 99, 100, 101, 500, 1000] {
            let codes = LabelGenerator.labels(count: n, charset: "asdfghjkl;")
            #expect(codes.count == n)
            #expect(Set(codes).count == n)
            #expect(prefixFree(codes), "n=\(n)")
        }
        let eleven = LabelGenerator.labels(count: 11, charset: "asdfghjkl;")
        #expect(eleven.filter { $0.count == 1 }.count == 9)
        #expect(LabelGenerator.labels(count: 100, charset: "asdfghjkl;").allSatisfy { $0.count == 2 })
        #expect(LabelGenerator.labels(count: 101, charset: "asdfghjkl;").map(\.count).max() == 3)
    }

    @Test func shortestCodesFirst() {
        let codes = LabelGenerator.labels(count: 40, charset: "asdf")
        #expect(codes.map(\.count) == codes.map(\.count).sorted())
    }

    @Test func charsetIsNormalised() {
        #expect(LabelGenerator.uniqueKeys(Array("AaS s;")) == ["a", "s", ";"])
        #expect(LabelGenerator.labels(count: 5, charset: "a").isEmpty)
        #expect(LabelGenerator.labels(count: 0, charset: "asdf").isEmpty)
    }

    @Test func matcherNarrowsAndPicks() {
        var m = HintMatcher(labels: LabelGenerator.labels(count: 12, charset: "asdfghjkl;"))
        // 12 over 10 keys: 8 singles (d…;), then aa as ad af… and sa ss (prefix "a"/"s" expanded)
        #expect(m.labels.prefix(8).allSatisfy { $0.count == 1 })
        guard case .narrowed(let hits) = m.type("a") else { Issue.record("expected narrowed"); return }
        #expect(hits.count >= 2)
        #expect(m.type("x") == .noMatch)
        #expect(m.typed == "a")
        let target = m.labels[hits[1]]
        #expect(m.type(target.last!) == .matched(hits[1]))
    }

    @Test func matcherBackspace() {
        var m = HintMatcher(labels: ["a", "sd", "sf"])
        _ = m.type("s")
        #expect(m.visible == [1, 2])
        #expect(m.backspace() == [0, 1, 2])
        #expect(m.type("A") == .matched(0))
    }
}

struct GeometryTests {
    let primaryH: CGFloat = 1117

    @Test func axCocoaRoundTrip() {
        let ax = CGRect(x: 100, y: 50, width: 80, height: 20)
        let cocoa = ScreenGeometry.cocoa(fromAX: ax, primaryHeight: primaryH)
        #expect(cocoa == CGRect(x: 100, y: 1117 - 70, width: 80, height: 20))
        #expect(ScreenGeometry.ax(fromCocoa: cocoa, primaryHeight: primaryH) == ax)
    }

    @Test func secondaryScreenAboveAndLeft() {
        // External display above-left of the built-in one: Cocoa y > primary height, negative x.
        let externalCocoa = CGRect(x: -2560, y: 1117, width: 2560, height: 1440)
        let externalAX = ScreenGeometry.axFrame(ofScreen: externalCocoa, primaryHeight: primaryH)
        #expect(externalAX == CGRect(x: -2560, y: -1440, width: 2560, height: 1440))
        let element = CGRect(x: -2500, y: -1400, width: 40, height: 20)
        let local = ScreenGeometry.layerRect(element, inScreen: externalAX)
        #expect(local == CGRect(x: 60, y: 1440 - 60, width: 40, height: 20))
    }

    @Test func screenForRect() {
        let screens = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 1728, y: -300, width: 2560, height: 1440)]
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 10, y: 10, width: 5, height: 5), screens: screens) == 0)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 1700, y: 10, width: 100, height: 5), screens: screens) == 1)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 9000, y: 10, width: 5, height: 5), screens: screens) == 1)
    }

    @Test func dedupeOverlapAndCorners() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 1, y: 1, width: 99, height: 19), // same control twice
            CGRect(x: 2, y: 0, width: 30, height: 30), // same corner
            CGRect(x: 200, y: 0, width: 100, height: 20),
            CGRect(x: 0, y: 100, width: 0, height: 20), // empty
        ]
        #expect(ScreenGeometry.dedupe(frames) == [0, 3])
    }

    @Test func clickPointUsesVisiblePart() {
        let p = ScreenGeometry.clickPoint(CGRect(x: 0, y: -100, width: 100, height: 200), clip: CGRect(x: 0, y: 0, width: 500, height: 500))
        #expect(p == CGPoint(x: 50, y: 50))
    }

    @Test func labelStaysOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let o = ScreenGeometry.labelOrigin(for: CGRect(x: 290, y: -5, width: 20, height: 20), size: CGSize(width: 20, height: 18), anchor: .topLeft, bounds: bounds)
        #expect(o == CGPoint(x: 280, y: 0))
        let c = ScreenGeometry.labelOrigin(for: CGRect(x: 100, y: 100, width: 40, height: 40), size: CGSize(width: 20, height: 18), anchor: .center, bounds: bounds)
        #expect(c == CGPoint(x: 110, y: 111))
    }
}
