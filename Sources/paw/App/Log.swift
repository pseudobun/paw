import os

enum Log {
    static let app = Logger(subsystem: AppPaths.bundleID, category: "app")
    static let ax = Logger(subsystem: AppPaths.bundleID, category: "ax")
    static let input = Logger(subsystem: AppPaths.bundleID, category: "input")
}
