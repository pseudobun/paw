import os

enum Log {
    static let app = Logger(subsystem: AppPaths.bundleID, category: "app")
}
