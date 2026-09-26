import Foundation

public final class BugReportBundler {
    private let deviceInfoSummary: () -> String
    private let now: () -> Int64

    public init(
        deviceInfoSummary: @escaping () -> String,
        now: @escaping () -> Int64 = epochMillisNow
    ) {
        self.deviceInfoSummary = deviceInfoSummary
        self.now = now
    }

    public func build() -> String {
        var result = ""
        result += "=== FeedbackKit bug report ===\n"
        result += "Generated at (epoch millis): \(now())\n"
        result += "\n"

        let deviceInfo = deviceInfoSummary()
        result += deviceInfo
        if !deviceInfo.hasSuffix("\n") {
            result += "\n"
        }

        result += "\n"
        result += "=== Recent logs (\(Logger.size()) lines) ===\n"
        result += Logger.recentLogsText()
        if Logger.size() > 0 {
            result += "\n"
        }

        return result
    }
}

private func epochMillisNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
