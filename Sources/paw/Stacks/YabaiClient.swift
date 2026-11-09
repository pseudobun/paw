import Foundation
import PawCore

/// Talks to yabai through its CLI.
struct YabaiClient {
    let path: String

    static let signalEvents = [
        "window_focused", "window_moved", "window_resized", "window_created", "window_destroyed",
        "window_minimized", "window_deminimized", "window_title_changed", "application_front_switched",
        "application_hidden", "application_visible", "application_terminated", "space_changed",
        "display_changed", "display_added", "display_removed", "display_moved", "display_resized",
        "mission_control_exit", "system_woke",
    ]
    static let signalPrefix = "paw_"

    @discardableResult
    func run(_ args: [String]) -> (status: Int32, out: Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    /// Windows and spaces, queried in parallel. nil when yabai isn't running or answers garbage.
    func query() -> (windows: [YabaiWindow], spaces: [YabaiSpace])? {
        var w: (Int32, Data) = (-1, Data()), s: (Int32, Data) = (-1, Data())
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) { w = run(["-m", "query", "--windows"]) }
        DispatchQueue.global(qos: .userInitiated).async(group: group) { s = run(["-m", "query", "--spaces"]) }
        group.wait()
        guard w.0 == 0, s.0 == 0,
              let windows = try? JSONDecoder().decode([YabaiWindow].self, from: w.1),
              let spaces = try? JSONDecoder().decode([YabaiSpace].self, from: s.1) else { return nil }
        return (windows, spaces)
    }

    func focus(window id: Int) {
        run(["-m", "window", "--focus", String(id)])
    }

    /// Signals that run `action` (paw refresh) on every change paw draws.
    func addSignals(action: String) -> Int {
        var ok = 0
        for e in Self.signalEvents {
            if run(["-m", "signal", "--add", "label=\(Self.signalPrefix)\(e)", "event=\(e)", "action=\(action)"]).status == 0 { ok += 1 }
        }
        return ok
    }

    func removeSignals() {
        for e in Self.signalEvents { run(["-m", "signal", "--remove", "\(Self.signalPrefix)\(e)"]) }
    }

    /// paw's signals currently in yabai.
    func listSignals() -> [String] {
        guard let arr = try? JSONSerialization.jsonObject(with: run(["-m", "signal", "--list"]).out) as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["label"] as? String }.filter { $0.hasPrefix(Self.signalPrefix) }
    }
}
