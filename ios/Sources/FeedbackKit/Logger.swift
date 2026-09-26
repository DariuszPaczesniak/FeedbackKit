import Foundation
import os.log

public enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
}

public final class Logger {
    private static let maxEntries = 500
    private static var entries = Deque<String>()

    public static func log(_ level: LogLevel, tag: String, message: String) {
        let line = "\(epochMillisNow()) [\(level.rawValue)] \(tag): \(message)"
        entries.append(line)
        while entries.count > maxEntries {
            entries.removeFirst()
        }
        platformLog(level, tag, message)
    }

    public static func debug(tag: String, message: String) {
        log(.debug, tag: tag, message: message)
    }

    public static func info(tag: String, message: String) {
        log(.info, tag: tag, message: message)
    }

    public static func warn(tag: String, message: String) {
        log(.warn, tag: tag, message: message)
    }

    public static func error(tag: String, message: String) {
        log(.error, tag: tag, message: message)
    }

    public static func recentLogsText() -> String {
        entries.joined(separator: "\n")
    }

    public static func size() -> Int {
        entries.count
    }

    public static func clear() {
        entries.removeAll()
    }
}

private func platformLog(_ level: LogLevel, tag: String, message: String) {
    let log = OSLog(subsystem: "com.feedbackkit", category: tag)
    let osLevel: OSLogType
    switch level {
    case .debug:
        osLevel = .debug
    case .info:
        osLevel = .info
    case .warn:
        osLevel = .error
    case .error:
        osLevel = .error
    }
    os_log("%{public}@: %{public}@", log: log, type: osLevel, tag, message)
}

private func epochMillisNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

// Simple deque implementation using a deque-like structure
private struct Deque<Element> {
    private var elements: [Element] = []

    mutating func append(_ element: Element) {
        elements.append(element)
    }

    mutating func removeFirst() {
        if !elements.isEmpty {
            elements.removeFirst()
        }
    }

    mutating func removeAll() {
        elements.removeAll()
    }

    var count: Int {
        elements.count
    }

    func joined(separator: String) -> String {
        elements.map { "\($0)" }.joined(separator: separator)
    }
}
