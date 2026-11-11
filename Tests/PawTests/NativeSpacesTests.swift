import Testing
@testable import paw

struct NativeSpacesTests {
    @Test func countsDesktopsPerDisplayWithoutCountingFullscreenApps() {
        let topology: [[String: Any]] = [
            ["Spaces": [["type": 0], ["type": 0], ["type": 4]]],
            ["Spaces": [["type": 0]]],
        ]
        let counts = SkyLight.nativeDesktopCounts(in: topology)
        #expect(counts == [2, 1])
        #expect(SkyLight.nativeSpacesStatus(counts: counts).hasPrefix("warning:"))
        #expect(SkyLight.nativeSpacesStatus(counts: counts).contains("2, 1"))
        #expect(SkyLight.nativeSpacesStatus(counts: [1, 1]).hasPrefix("ok:"), "two displays are supported")
        #expect(SkyLight.nativeDesktopCounts(in: [["Spaces": [["type": 0], ["type": 4]]]]) == [1])
    }

    @Test func unknownTopologyIsNotReportedAsHealthy() {
        for topology: [[String: Any]] in [[], [["Other": []]], [["Spaces": []]],
                                         [["Spaces": [["MissingType": 0]]]], [["Spaces": [["type": 4]]]]] {
            #expect(SkyLight.nativeDesktopCounts(in: topology) == nil)
        }
        #expect(SkyLight.nativeSpacesStatus(counts: nil).hasPrefix("unavailable:"))
        #expect(SkyLight.nativeSpacesStatus(counts: []).hasPrefix("unavailable:"))
    }
}
