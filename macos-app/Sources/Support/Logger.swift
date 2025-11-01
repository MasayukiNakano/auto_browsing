import Foundation
import os.log

extension Notification.Name {
    static let loggerMessage = Notification.Name("LoggerMessageNotification")
}

struct Logger {
    static let shared = Logger()
    private let log = OSLog(subsystem: "com.example.AutoBrowsing", category: "App")

    func debug(_ message: String) {
        log(message, type: .debug)
    }

    func info(_ message: String) {
        log(message, type: .info)
    }

    func error(_ message: String) {
        log(message, type: .error)
    }

    private func log(_ message: String, type: OSLogType) {
        os_log("%{public}@", log: log, type: type, message)
        NotificationCenter.default.post(name: .loggerMessage, object: nil, userInfo: ["message": message])
    }
}
