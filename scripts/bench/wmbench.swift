// paw's window-management benchmark, run against the dev build (`just dev`, then `just bench`).
// It needs a desktop to work on: workspaces 1 and 2 with a few tiled windows each (TextEdit
// documents are fine), and for `hung` an app with windows on them that may be stopped.
//
//   wmbench switch [n]       workspace 1 ↔ 2: the command's round trip, and the time until every
//                            window of the new workspace is really on screen (window server)
//   wmbench ops [n]          focus, swap, resize, layout changes, query: round trips
//   wmbench hung <app>       the same commands while <app> is stopped (SIGSTOP), as a hung app
//                            would be: how long paw's main thread is held up by it
//   wmbench all [n]          switch, ops
//
// Every number is milliseconds. Round trips are main-thread time: paw answers a command after
// running it.
import CoreGraphics
import Foundation

let sock = NSHomeDirectory() + "/Library/Application Support/com.pseudobun.paw.dev/paw.sock"

func send(_ cmd: String) -> Data {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return Data() }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { p in
        sock.utf8CString.withUnsafeBytes { p.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(p.count - 1))) }
    }
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard ok == 0 else { fputs("wmbench: paw Dev is not running\n", stderr); exit(1) }
    _ = cmd.withCString { write(fd, $0, strlen($0)) }
    shutdown(fd, SHUT_WR)
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        out.append(buf, count: n)
    }
    return out
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func query() -> [[String: Any]] {
    let outer = (try? JSONSerialization.jsonObject(with: send("query"))) as? [String: Any]
    guard let text = outer?["json"] as? String else { return [] }
    return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]] ?? []
}

func windows(_ ws: String) -> [[String: Any]] {
    (query().first { ($0["id"] as? String) == ws }?["windows"] as? [[String: Any]]) ?? []
}

func ids(_ ws: String) -> [CGWindowID] { windows(ws).compactMap { ($0["id"] as? Int).map(CGWindowID.init) } }

let screen = CGDisplayBounds(CGMainDisplayID())

/// Every window on screen (its middle inside the main display), polling the window server each ms.
func onScreen(_ wids: [CGWindowID], timeout: Double = 3000) -> Bool {
    let t0 = now()
    var ptrs = wids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    let arr = CFArrayCreate(nil, &ptrs, ptrs.count, nil)!
    while now() - t0 < timeout {
        let desc = (CGWindowListCreateDescriptionFromArray(arr) as? [[String: Any]]) ?? []
        let ok = desc.count == wids.count && desc.allSatisfy { d in
            guard let b = d[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return screen.intersects(r.insetBy(dx: r.width * 0.45, dy: r.height * 0.45))
        }
        if ok { return true }
        usleep(1000)
    }
    return false
}

func report(_ name: String, _ xs: [Double]) {
    guard !xs.isEmpty else { print("\(name): no samples"); return }
    let s = xs.sorted()
    func p(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count) * q))] }
    let label = name.padding(toLength: 24, withPad: " ", startingAt: 0)
    print(label + String(format: " n=%-4d p50=%8.2f  p90=%8.2f  p99=%8.2f  max=%8.2f", s.count, p(0.5), p(0.9), p(0.99), s.last!))
}

func rtt(_ cmd: String, _ n: Int) -> [Double] {
    (0..<n).map { _ in
        let t = now()
        _ = send("run " + cmd)
        return now() - t
    }
}

/// The windows paw shows on a workspace (not those parked behind a placeholder, too big for
/// their tile): switched to once to find out.
func shown(_ ws: String) -> [CGWindowID] {
    _ = send("run workspace \(ws)")
    usleep(500_000)
    return windows(ws).filter { $0["onScreen"] as? Bool ?? true }.compactMap { ($0["id"] as? Int).map(CGWindowID.init) }
}

func switches(_ n: Int) {
    let a = shown("1"), b = shown("2")
    guard !a.isEmpty, !b.isEmpty else { fputs("wmbench: put windows on workspaces 1 and 2 first\n", stderr); exit(1) }
    print("workspace 1: \(a.count) windows shown, workspace 2: \(b.count) windows shown")
    var r: [Double] = [], s: [Double] = [], miss = 0
    for i in 0..<n {
        let (to, wins) = i % 2 == 0 ? ("2", b) : ("1", a)
        let t = now()
        _ = send("run workspace \(to)")
        r.append(now() - t)
        if onScreen(wins) { s.append(now() - t) } else { miss += 1 }
        usleep(30_000)
    }
    report("switch round trip", r)
    report("switch all on screen", s)
    print("switch timeouts: \(miss)")
}

func ops(_ n: Int) {
    _ = send("run workspace 1")
    usleep(300_000)
    report("focus east/west", rtt("focus east", n / 2) + rtt("focus west", n / 2))
    report("swap east/west", rtt("swap east", n / 2) + rtt("swap west", n / 2))
    report("resize east ±20", rtt("resize east 20", n / 2) + rtt("resize east -20", n / 2))
    var l: [Double] = []
    for i in 0..<max(4, n / 4) { l += rtt(["layout columns", "layout stack", "layout master", "layout bsp"][i % 4], 1) }
    report("layout change", l)
    _ = send("run layout bsp")
    report("query", (0..<n).map { _ in let t = now(); _ = query(); return now() - t })
}

func hung(_ app: String) {
    let pids = pgrep(app)
    guard !pids.isEmpty else { fputs("wmbench: \(app) is not running\n", stderr); exit(1) }
    _ = send("run workspace 1; layout bsp")
    usleep(500_000)
    for p in pids { kill(p, SIGSTOP) }
    defer { for p in pids { kill(p, SIGCONT) } }
    print("\(app) stopped (pid \(pids.map(String.init).joined(separator: ",")))")
    for cmd in ["workspace 2", "workspace 1", "layout columns", "layout bsp", "focus east", "swap west", "swap east",
                "resize east 40", "resize east -40"] {
        let t = now()
        _ = send("run " + cmd)
        print("  " + cmd.padding(toLength: 22, withPad: " ", startingAt: 0) + String(format: "%9.1f ms", now() - t))
    }
    let t = now()
    _ = send("status")
    print("  " + "status (after)".padding(toLength: 22, withPad: " ", startingAt: 0) + String(format: "%9.1f ms", now() - t))
}

func pgrep(_ name: String) -> [pid_t] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-x", name]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    p.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return out.split(separator: "\n").compactMap { pid_t($0) }
}

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "all"
let n = args.dropFirst().first.flatMap { Int($0) } ?? 100
switch mode {
case "switch": switches(n)
case "ops": ops(n)
case "hung": hung(args.dropFirst().first ?? "TextEdit")
case "all": switches(n); ops(n)
default: fputs("usage: wmbench switch|ops|all [n] | hung <app>\n", stderr); exit(64)
}
