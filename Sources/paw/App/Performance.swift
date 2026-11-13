import AppKit
import Darwin
import os
import PawCore

/// Opt-in, bounded in-memory measurements. Normal builds compile the recorder out.
enum Performance {
    struct Interval {
        #if PAW_PROFILE
        let id: UInt64
        let name: StaticString
        let detail: String
        let start: UInt64
        let parent: UInt64?
        let measured: Bool
        let state: OSSignpostIntervalState
        #endif
    }

    #if PAW_PROFILE
    static let enabled = AppPaths.isDev && !(ProcessInfo.processInfo.environment["PAW_PERF_OUTPUT"] ?? "").isEmpty
    private static let signposter = OSSignposter(subsystem: AppPaths.bundleID, category: .pointsOfInterest)
    private static let lock = NSLock()
    private static var recording = false
    private static var serial: UInt64 = 0
    private static var active: [UInt64: Interval] = [:]
    private static var samples: [[String: Any]] = []
    private static var counters: [String: Int] = [:]
    private static var dropped = 0
    private static var started: UInt64 = 0
    private static var initialCPU: Double = 0
    private static var initialThermal = 0
    private static let limit = 100_000

    static func begin(_ name: StaticString, detail: String = "") -> Interval? {
        guard enabled else { return nil }
        return lock.withLock {
            serial += 1
            let parent = String(describing: name) == "command"
                ? active.values.filter { String(describing: $0.name) == "command" }.map(\.id).max() : nil
            let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
            let interval = Interval(id: serial, name: name, detail: detail,
                                    start: DispatchTime.now().uptimeNanoseconds, parent: parent,
                                    measured: recording, state: state)
            active[serial] = interval
            return interval
        }
    }

    static func end(_ interval: Interval?, values: [String: Int] = [:]) {
        guard let interval else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        signposter.endInterval(interval.name, interval.state)
        lock.withLock {
            guard active.removeValue(forKey: interval.id) != nil else { return }
            // Track warm-up work for the idle gate, without mixing it into measured samples.
            guard interval.measured else { return }
            var row: [String: Any] = ["id": interval.id, "name": String(describing: interval.name),
                                      "detail": interval.detail, "start_ns": interval.start,
                                      "duration_ns": now - interval.start, "values": values]
            if let parent = interval.parent { row["parent"] = parent }
            if samples.count < limit { samples.append(row) } else { dropped += 1 }
        }
    }

    static func event(_ name: StaticString) {
        guard enabled else { return }
        lock.withLock { if recording { signposter.emitEvent(name) } }
    }

    static func count(_ name: String, by amount: Int = 1) {
        guard enabled else { return }
        lock.withLock { if recording { counters[name, default: 0] += amount } }
    }

    static func axWrite(_ error: AXError) {
        guard enabled else { return }
        lock.withLock {
            guard recording else { return }
            counters["ax_write_attempts", default: 0] += 1
            if error != .success {
                counters["ax_write_failures", default: 0] += 1
                counters["ax_error_\(error.rawValue)", default: 0] += 1
                signposter.emitEvent("AX write failed")
            }
        }
    }

    private static func usage() -> (cpu: Double, peakRSS: Int, valid: Bool) {
        var usage = rusage()
        let valid = getrusage(RUSAGE_SELF, &usage) == 0
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return (cpu, Int(usage.ru_maxrss), valid)
    }

    static func control(_ action: String) -> [String: Any] {
        guard enabled else { return ["error": "requires a PAW_PROFILE dev build and PAW_PERF_OUTPUT"] }
        switch action {
        case "status":
            return lock.withLock {
                ["recording": recording, "active": active.count,
                 "screenRecording": CGPreflightScreenCaptureAccess(), "schema": 1,
                 "thermalState": ProcessInfo.processInfo.thermalState.rawValue]
            }
        case "begin":
            return lock.withLock {
                guard !recording else { return ["error": "already recording"] }
                guard active.isEmpty else { return ["error": "unfinished intervals from previous measurement"] }
                samples = []; counters = [:]; dropped = 0
                let resources = usage()
                guard resources.valid else { return ["error": "getrusage failed"] }
                initialCPU = resources.cpu
                initialThermal = ProcessInfo.processInfo.thermalState.rawValue
                started = DispatchTime.now().uptimeNanoseconds
                recording = true
                signposter.emitEvent("Measurement begin")
                return ["ok": true]
            }
        case "end":
            let result: [String: Any] = lock.withLock {
                guard recording else { return ["error": "not recording"] }
                let stopped = DispatchTime.now().uptimeNanoseconds
                let resources = usage()
                recording = false
                signposter.emitEvent("Measurement end")
                return ["schema": 1, "pid": getpid(), "version": AppPaths.version,
                        "resources_valid": resources.valid,
                        "thermal_start": initialThermal, "thermal_end": ProcessInfo.processInfo.thermalState.rawValue,
                        "start_ns": started, "end_ns": stopped, "elapsed_ns": stopped - started,
                        "cpu_seconds": resources.cpu - initialCPU,
                        "lifetime_peak_rss_bytes": resources.peakRSS,
                        "intervals": samples, "counters": counters,
                        "incomplete_intervals": active.count, "dropped_records": dropped]
            }
            if result["error"] != nil { return result }
            do {
                guard let path = ProcessInfo.processInfo.environment["PAW_PERF_OUTPUT"] else {
                    return ["error": "PAW_PERF_OUTPUT missing"]
                }
                let url = URL(fileURLWithPath: path)
                guard !FileManager.default.fileExists(atPath: url.path) else {
                    return ["error": "measurement output already exists"]
                }
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                try data.write(to: url, options: .atomic)
                return ["ok": true, "incomplete": result["incomplete_intervals"]!, "dropped": result["dropped_records"]!]
            } catch { return ["error": "cannot save measurement: \(error.localizedDescription)"] }
        default: return ["error": "perf begin|end|status"]
        }
    }
    #else
    static let enabled = false
    @inline(__always) static func begin(_ name: StaticString, detail: String = "") -> Interval? { nil }
    @inline(__always) static func end(_ interval: Interval?, values: [String: Int] = [:]) {}
    @inline(__always) static func event(_ name: StaticString) {}
    @inline(__always) static func count(_ name: String, by amount: Int = 1) {}
    @inline(__always) static func axWrite(_ error: AXError) {}
    static func control(_ action: String) -> [String: Any] { ["error": "not a profiling build"] }
    #endif
}

extension Command {
    // Case names only: associated values can contain shell commands and private search text.
    var performanceName: String {
        switch self {
        case .focus: return "focus"
        case .swap: return "swap"
        case .swapStack: return "swapStack"
        case .warp: return "warp"
        case .join: return "join"
        case .stack: return "stack"
        case .unstack: return "unstack"
        case .layout: return "layout"
        case .toggle: return "toggle"
        case .balance: return "balance"
        case .rotate: return "rotate"
        case .resize: return "resize"
        case .grid: return "grid"
        case .workspace: return "workspace"
        case .workspaceNew: return "workspaceNew"
        case .workspaceClose: return "workspaceClose"
        case .moveTo: return "moveTo"
        case .focusDisplay: return "focusDisplay"
        case .moveToDisplay: return "moveToDisplay"
        case .moveWorkspace: return "moveWorkspace"
        case .moveWorkspaceToDisplay: return "moveWorkspaceToDisplay"
        case .arrange: return "arrange"
        case .initiate: return "initiate"
        case .mode: return "mode"
        case .exec: return "exec"
        case .undo: return "undo"
        case .redo: return "redo"
        case .find: return "find"
        case .overview: return "overview"
        case .zoom: return "zoom"
        case .retile: return "retile"
        case .recover: return "recover"
        case .reload: return "reload"
        }
    }
}
