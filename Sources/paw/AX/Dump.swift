import AppKit

/// What a collection found, as JSON (`paw dump`).
enum Dump {
    static func json(_ r: Collector.Result, app: NSRunningApplication, purpose: Collector.Purpose) -> Data {
        let list = (purpose == .scroll ? r.scrollAreas : r.elements).map { e -> [String: Any] in
            var d: [String: Any] = ["role": e.role, "source": e.source.rawValue,
                                    "frame": [e.frame.minX, e.frame.minY, e.frame.width, e.frame.height].map { Int($0) }]
            for (k, v) in [("subrole", e.subrole), ("title", e.title), ("description", e.desc), ("value", e.value),
                           ("roleDescription", e.roleDescription), ("placeholder", e.placeholder)] {
                if let v { d[k] = v }
            }
            return d
        }
        let out: [String: Any] = ["app": app.localizedName ?? "", "bundleID": app.bundleIdentifier ?? "",
                                  "trusted": AX.isTrusted, "purpose": "\(purpose)", "ms": NSDecimalNumber(string: String(format: "%.1f", r.ms)),
                                  "nodes": r.nodes, "menuOpen": r.menuOpen, "count": list.count, "elements": list]
        return (try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
