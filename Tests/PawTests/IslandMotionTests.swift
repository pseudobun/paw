import Testing
@testable import paw

struct IslandMotionTests {
    @Test func curveRunsFromStartToEndAndOnlyForward() {
        #expect(abs(IslandMotion.easeOutQuint(0)) < 1e-6)
        #expect(abs(IslandMotion.easeOutQuint(1) - 1) < 1e-6)
        var last = 0.0
        for i in 1...20 {
            let y = IslandMotion.easeOutQuint(Double(i) / 20)
            #expect(y >= last)
            last = y
        }
        // Fast out of the gate, like easeOutQuint.
        #expect(IslandMotion.easeOutQuint(0.3) > 0.7)
    }
}
