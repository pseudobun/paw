import Foundation
import Testing
@testable import paw

/// The Dock helper's version: what `paw status` says when the one in Dock or the installed one
/// isn't this paw's, and when `paw dock install` restarts Dock.
struct DockHelperTests {
    @Test func theHelloCarriesTheVersion() {
        #expect(DockBridge.helloVersion("paw-dock 1\n") == "1")
        #expect(DockBridge.helloVersion("paw-dock 3f2a9c01be7d\n\0\0\0") == "3f2a9c01be7d")
        #expect(DockBridge.helloVersion("paw-dock \n") == nil)
        #expect(DockBridge.helloVersion("something else") == nil)
    }

    @Test func statusSaysWhatToDoWhenTheHelperIsNotThisPaws() {
        #expect(DockBridge.advice(bundled: "b", installed: "b", loaded: "b") == nil)
        #expect(DockBridge.advice(bundled: "b", installed: "a", loaded: "a") == "outdated: sudo paw dock install")
        #expect(DockBridge.advice(bundled: "b", installed: nil, loaded: "1") == "outdated: sudo paw dock install",
                "installed before versions")
        #expect(DockBridge.advice(bundled: "b", installed: "b", loaded: "a") == "Dock still runs the old one: killall Dock")
        #expect(DockBridge.advice(bundled: "b", installed: "b", loaded: nil) == nil, "not loaded: said elsewhere")
        #expect(DockBridge.advice(bundled: nil, installed: "a", loaded: "c") == nil, "a build without a version")
    }

    @Test func installRestartsDockOnlyWhenTheHelperChanged() {
        #expect(!DockCLI.needsDockRestart(previous: "a", new: "a"), "reinstalling the same helper")
        #expect(DockCLI.needsDockRestart(previous: "a", new: "b"))
        #expect(DockCLI.needsDockRestart(previous: nil, new: "b"), "first install, or one from before versions")
        #expect(DockCLI.needsDockRestart(previous: "a", new: nil))
    }

    @Test func afterAnUpdateTheChangedHelperIsNotedOncePerVersion() throws {
        let defaults = try #require(UserDefaults(suiteName: "paw.tests.\(UUID())"))
        var noted = 0
        DockCLI.noteUpdateOnce(defaults: defaults, bundled: "a", isOutdated: { false }, show: { noted += 1 })
        #expect(noted == 0, "up to date (or not installed): never")
        DockCLI.noteUpdateOnce(defaults: defaults, bundled: "a", isOutdated: { true }, show: { noted += 1 })
        DockCLI.noteUpdateOnce(defaults: defaults, bundled: "a", isOutdated: { true }, show: { noted += 1 })
        #expect(noted == 1, "once for this helper")
        DockCLI.noteUpdateOnce(defaults: defaults, bundled: "b", isOutdated: { true }, show: { noted += 1 })
        #expect(noted == 2, "the next changed helper is noted")
        DockCLI.noteUpdateOnce(defaults: defaults, bundled: nil, isOutdated: { true }, show: { noted += 1 })
        #expect(noted == 2, "a build without a version")
    }
}
