import os.log

struct Logger {
    static let shared = Logger()
    private let log = OSLog(subsystem: "com.example.AutoBrowsing", category: "App")

    func debug(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, message)
    }

    func info(_ message: String) {
        os_log("%{public}@", log: log, type: .info, message)
    }

    func error(_ message: String) {
        os_log("%{public}@", log: log, type: .error, message)
    }
}
