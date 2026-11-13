import Foundation
import PawCore
import Testing
@testable import paw

/// Reloading the config file: only real changes are announced, a broken file keeps the last good
/// config without re-applying it, and the watcher keeps working across replaced files and folders.
@MainActor
@Suite(.serialized)
struct ConfigReloadTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "paw-reload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }

    @Test func onlyChangesAreAnnounced() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "config.json5")
        try write("{ layout: { gap: 4 } }", to: url)
        let s = Settings(url: url)
        var calls: [Bool] = []
        s.onChange = { calls.append($0) }

        s.load() // the same file again (an editor touching it, a save's echo)
        #expect(calls.isEmpty)

        try write("{ layout: { gap: 6 } }", to: url)
        s.load()
        #expect(calls == [true])
        #expect(s.config.layout.gap == 6)

        try write("{ layout: { gap: 6 }, typo: 1 }", to: url)
        s.load()
        #expect(calls == [true, false], "a new warning, same config")
        #expect(s.warnings == ["unknown key typo"])

        try write("{ layout: { gap: ", to: url)
        s.load()
        #expect(calls == [true, false, false], "broken: the error is news, the config isn't")
        #expect(s.error != nil && s.warnings.isEmpty)
        #expect(s.config.layout.gap == 6)
        s.load()
        #expect(calls.count == 3, "still the same error")

        s.load(force: true)
        #expect(calls.count == 4 && calls.last == false, "a forced reload of a broken file reports it, applies nothing")

        try write("{ layout: { gap: 6 } }", to: url)
        s.load()
        #expect(calls.last == false && s.error == nil, "fixed, but the config in effect didn't change")
        s.load(force: true)
        #expect(calls.last == true)
    }

    @Test func saveAppliesOnce() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "config.json5")
        try write("{}", to: url)
        let s = Settings(url: url)
        var calls = 0
        s.onChange = { _ in calls += 1 }
        s.save { $0.layout.gap = 3 }
        #expect(calls == 1)
        s.load() // the watcher's echo of the same save
        #expect(calls == 1)
    }

    @Test func iconMapEditsReload() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "config.json5")
        let map = dir.appending(path: "icon_map.lua")
        try write("local icons = {\n  [\"Zed\"] = \":zed:\",\n}\n", to: map)
        try write("{ icons: { map: \"\(map.path)\" } }", to: url)
        let s = Settings(url: url)
        var calls: [Bool] = []
        s.onChange = { calls.append($0) }
        #expect(s.icons.glyph(for: "Zed") == ":zed:")
        try write("local icons = {\n  [\"Zed\"] = \":code:\",\n}\n", to: map)
        s.load()
        #expect(calls == [true], "only the icon map file changed")
        #expect(s.icons.glyph(for: "Zed") == ":code:")
    }

    @Test func watcherFollowsAReplacedFolder() async throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appending(path: "dotfiles")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try write("{}", to: real.appending(path: "config.json5"))
        let link = root.appending(path: "paw")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        var fired = 0
        let watcher = FileWatcher(url: link.appending(path: "config.json5")) { fired += 1 }
        defer { watcher.stop() }

        try write("{ layout: { gap: 1 } }", to: link.appending(path: "config.json5"))
        try await waitFor { fired >= 1 }

        // The checkout is recreated: the old folder goes, a new one takes its place.
        try FileManager.default.removeItem(at: real)
        try await waitFor { fired >= 2 }
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try write("{ layout: { gap: 2 } }", to: real.appending(path: "config.json5"))
        try await waitFor(seconds: 5) { fired >= 3 }
        let before = fired
        try write("{ layout: { gap: 3 } }", to: real.appending(path: "config.json5"))
        try await waitFor { fired > before }
    }

    private func waitFor(seconds: Double = 2, _ done: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() {
            guard Date() < deadline else { Issue.record("timed out"); return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
