// Workload driver for just bench. The Python controller owns builds, fixtures and captures.
import AppKit
import Darwin
import Foundation

private let socketPath = NSHomeDirectory() + "/Library/Application Support/com.pseudobun.paw.dev/paw.sock"
private func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

private func send(_ text: String) throws -> [String: Any] {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    try require(fd >= 0, "cannot open socket")
    defer { close(fd) }
    var timeout = timeval(tv_sec: 10, tv_usec: 0), noPipe: Int32 = 1
    try require(setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
        && setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
        && setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe))) == 0, "socket options failed")
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    try require(socketPath.utf8CString.count <= MemoryLayout.size(ofValue: address.sun_path), "socket path too long")
    withUnsafeMutableBytes(of: &address.sun_path) { dest in
        socketPath.utf8CString.withUnsafeBytes { dest.copyBytes(from: $0) }
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    try require(connected == 0, "paw Dev is not running")
    let deadline = now() + 10_000
    try Data(text.utf8).withUnsafeBytes { bytes in
        var sent = 0
        while sent < bytes.count {
            let n = write(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
            if n < 0 && errno == EINTR && now() < deadline { continue }
            try require(n > 0 && now() < deadline, "IPC write failed/timed out")
            sent += n
        }
    }
    shutdown(fd, SHUT_WR)
    var data = Data(), buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        try require(now() < deadline, "IPC reply timed out")
        let n = read(fd, &buffer, buffer.count)
        if n < 0 && errno == EINTR { continue }
        try require(n >= 0 && now() < deadline, "IPC read failed/timed out")
        if n == 0 { break }
        data.append(buffer, count: n)
        try require(data.count <= 16 * 1024 * 1024, "oversized IPC reply")
    }
    return try reply(data)
}

private func query() throws -> [[String: Any]] {
    guard let json = try send("query")["json"] as? String,
          let rows = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]], !rows.isEmpty else {
        throw BenchError("missing/invalid workspace query")
    }
    return rows
}

private func windows(_ rows: [[String: Any]]) -> [[String: Any]] { rows.flatMap { $0["windows"] as? [[String: Any]] ?? [] } }
private func focused(_ rows: [[String: Any]]) -> Int? {
    windows(rows.filter { $0["focused"] as? Bool == true }).first { $0["focused"] as? Bool == true }?["id"] as? Int
}
private func intended(_ rows: [[String: Any]]) throws -> [Int: CGRect] {
    var result: [Int: CGRect] = [:]
    for window in windows(rows) {
        guard let id = window["id"] as? Int, let value = window["frame"] as? [String: Any] else { throw BenchError("invalid window query") }
        try require(result[id] == nil, "duplicate window ID")
        result[id] = try frame(value)
    }
    try require(!result.isEmpty, "scene has no windows")
    return result
}

private func actualFrames(_ ids: Set<Int>) -> [Int: CGRect] {
    var pointers = ids.sorted().map { UnsafeRawPointer(bitPattern: $0) }
    guard let array = CFArrayCreate(nil, &pointers, pointers.count, nil),
          let descriptions = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [:] }
    var frames: [Int: CGRect] = [:]
    for description in descriptions {
        guard let id = description[kCGWindowNumber as String] as? Int,
              let bounds = description[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
              let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double else { continue }
        frames[id] = CGRect(x: x, y: y, width: w, height: h)
    }
    return frames
}

private func waitGeometry(_ target: [Int: CGRect]) throws {
    let deadline = now() + 3000
    repeat {
        if framesMatch(actualFrames(Set(target.keys)), target) { return }
        usleep(1000)
    } while now() < deadline
    throw BenchError("actual window geometry did not reach the target; batch invalid")
}

private struct Driver {
    let mode: String, count: Int, pace: Double, settle: Double, duration: Double, recording: Bool
    var measured = false
    var samples: [[String: Any]] = []
    var commands: [String] = []
    var targets: [String: [Int: CGRect]] = [:]
    var membership: Set<Int> = []

    mutating func run(_ command: String, metric: String? = nil, detail: String? = nil) throws {
        let start = now()
        _ = try send("run " + command)
        if measured {
            commands.append(detail ?? String(command.split(separator: " ")[0]))
            if let metric { samples.append(["metric": metric, "elapsed_ms": now() - start]) }
        }
    }

    func checkedQuery() throws -> [[String: Any]] {
        let rows = try query()
        try require(Set(windows(rows).compactMap { $0["id"] as? Int }) == membership, "window membership changed")
        return rows
    }

    func drain() throws {
        let deadline = now() + 10_000
        repeat {
            let status = try send("perf status")
            if status["axIdle"] as? Bool == true && status["active"] as? Int == 0 { return }
            usleep(10_000)
        } while now() < deadline
        throw BenchError("asynchronous work did not drain")
    }

    mutating func warm() throws {
        let status = try send("status")
        try require(status["trusted"] as? String == "yes", "PAW needs Accessibility access")
        try require(NSScreen.screens.count == 1, "bench requires one display")
        membership = Set(try windows(query()).compactMap { $0["id"] as? Int })
        try require(!membership.isEmpty, "prepare windows on workspaces 1 and 2")
        if mode == "hung" { return }
        for workspace in ["2", "1"] {
            try run("workspace " + workspace)
            Thread.sleep(forTimeInterval: 0.5)
            let rows = try checkedQuery()
            let shown = rows.first { $0["id"] as? String == workspace }
            try require(shown?["visible"] as? Bool == true && !(shown?["windows"] as? [[String: Any]] ?? []).isEmpty,
                        "need windows on both workspaces 1 and 2")
            let target = try intended(rows)
            try waitGeometry(target)
            targets[workspace] = target
        }
        if mode == "ops" {
            try run("layout columns")
            for _ in 0..<membership.count { try run("focus west") }
            try waitGeometry(intended(checkedQuery()))
        }
        if mode.hasPrefix("overview") {
            try run("overview"); Thread.sleep(forTimeInterval: pace)
            try run("overview"); Thread.sleep(forTimeInterval: pace)
        }
        Thread.sleep(forTimeInterval: settle)
        if recording { try drain() }
    }

    mutating func switches() throws {
        for index in 0..<count {
            let workspace = index.isMultiple(of: 2) ? "2" : "1"
            let start = now()
            try run("workspace " + workspace, metric: "switch.round_trip")
            let rows = try checkedQuery()
            try require(rows.first { $0["id"] as? String == workspace }?["visible"] as? Bool == true, "wrong visible workspace")
            let target = try intended(rows)
            try require(framesMatch(target, targets[workspace]!), "workspace target geometry changed")
            try waitGeometry(target)
            samples.append(["metric": "switch.geometry", "elapsed_ms": now() - start])
            Thread.sleep(forTimeInterval: pace)
        }
    }

    mutating func operations() throws {
        for (name, pair) in [("focus", ["focus east", "focus west"]), ("swap", ["swap east", "swap west"]),
                             ("resize", ["resize east 20", "resize east -20"])] {
            for index in 0..<count {
                let before = try checkedQuery()
                try run(pair[index % 2], metric: name + ".round_trip")
                let after = try checkedQuery()
                let changed = name == "focus" ? focused(before) != focused(after)
                    : try intended(before) != intended(after)
                try require(changed, "\(pair[index % 2]) did no work; use columns with two or more visible tiles")
                try waitGeometry(intended(after))
                Thread.sleep(forTimeInterval: pace)
            }
        }
        for _ in 0..<max(1, count / 8) {
            for kind in ["stack", "master", "bsp", "columns"] {
                try run("layout " + kind, metric: "layout.round_trip")
                try waitGeometry(intended(checkedQuery()))
                Thread.sleep(forTimeInterval: pace)
            }
        }
        for _ in 0..<count {
            let start = now(); _ = try checkedQuery()
            samples.append(["metric": "query.round_trip", "elapsed_ms": now() - start])
        }
    }

    mutating func execute() throws -> [String: Any] {
        try warm()
        if recording { _ = try send("perf begin") }
        measured = true
        switch mode {
        case "switch": try switches()
        case "ops": try operations()
        case "all":
            try switches()
            try run("layout columns")
            for _ in 0..<membership.count { try run("focus west") }
            try waitGeometry(intended(checkedQuery()))
            try operations()
        case "idle": Thread.sleep(forTimeInterval: duration)
        case "overview-off", "overview-on":
            for _ in 0..<(count / 2) {
                for state in ["open", "close"] {
                    try run("overview", metric: "overview." + state + ".round_trip", detail: "overview." + state)
                    Thread.sleep(forTimeInterval: pace)
                }
                try waitGeometry(intended(checkedQuery()))
            }
        case "hung":
            for cmd in ["workspace 2", "workspace 1", "layout columns", "layout bsp", "focus east", "swap west", "swap east", "resize east 20", "resize east -20"] {
                try run(cmd, metric: cmd + ".round_trip")
            }
        default: throw BenchError("unknown mode")
        }
        Thread.sleep(forTimeInterval: settle)
        if recording { try drain(); _ = try send("perf end") }
        let groups = Dictionary(grouping: samples, by: { $0["metric"] as! String })
        let metrics = try groups.mapValues { try summary($0.map { $0["elapsed_ms"] as! Double }) }
        return ["schema": 2, "valid": true, "mode": mode, "count": count, "pace": pace, "settle": settle,
                "duration": duration, "recording": recording, "window_ids": membership.sorted(),
                "expected_commands": commands, "samples": samples, "metrics": metrics, "status": try send("status")]
    }
}

@main private enum WMBench {
    static func main() {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            let mode = args.isEmpty ? "all" : args.removeFirst()
            let count = args.first.flatMap(Int.init) ?? 100
            if args.first.flatMap(Int.init) != nil { args.removeFirst() }
            func option(_ key: String, fallback: Double) throws -> Double {
                guard let i = args.firstIndex(of: key) else { return fallback }
                try require(i + 1 < args.count, "missing \(key)")
                let value = Double(args[i + 1]); args.removeSubrange(i...i + 1)
                guard let value, value.isFinite && value >= 0 && value <= 600 else { throw BenchError("invalid \(key)") }
                return value
            }
            let pace = try option("--pace", fallback: 0.03), settle = try option("--settle", fallback: 0.5)
            let duration = try option("--duration", fallback: 120)
            let recording = args.contains("--record"); args.removeAll { $0 == "--record" }
            let paused = args.contains("--paused"); args.removeAll { $0 == "--paused" }
            var output: URL?
            if let i = args.firstIndex(of: "--output") {
                try require(i + 1 < args.count, "missing --output")
                output = URL(fileURLWithPath: args[i + 1]); args.removeSubrange(i...i + 1)
                try require(!FileManager.default.fileExists(atPath: output!.path), "output already exists")
            }
            try require(args.isEmpty && ["switch", "ops", "all", "idle", "overview-off", "overview-on", "hung"].contains(mode),
                        "usage: just bench switch|ops|all [even-count] | prepare|register|run|compare|hung|check")
            try require((2...10000).contains(count) && count.isMultiple(of: 2), "count must be even, 2–10000")
            try require(mode != "hung" || paused, "hung must be started through just bench's cleanup controller")
            var driver = Driver(mode: mode, count: count, pace: pace, settle: settle, duration: duration, recording: recording)
            let result = try driver.execute()
            if let output { try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic) }
            for (name, value) in (result["metrics"] as! [String: [String: Double]]).sorted(by: { $0.key < $1.key }) {
                print(name + String(format: " n=%.0f median=%.3f p90=%.3f p99=%.3f max=%.3f ms", value["count"]!, value["median_ms"]!, value["p90_ms"]!, value["p99_ms"]!, value["max_ms"]!))
            }
        } catch {
            fputs("wmbench: \(error)\n", stderr)
            exit(1)
        }
    }
}
