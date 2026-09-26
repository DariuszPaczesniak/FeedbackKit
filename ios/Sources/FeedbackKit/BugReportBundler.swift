import Foundation

public final class BugReportBundler {
    private let deviceInfoSummary: () -> String
    private let now: () -> Int64
    private let testSession: TestSession?

    public init(
        deviceInfoSummary: @escaping () -> String,
        now: @escaping () -> Int64 = epochMillisNow,
        testSession: TestSession? = nil
    ) {
        self.deviceInfoSummary = deviceInfoSummary
        self.now = now
        self.testSession = testSession
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

        if let session = testSession {
            let results = session.results()
            result += "\n"
            result += "=== Test session: \(session.name) ===\n"
            result += "\(results.count) scenario(s) recorded\n"
            result += "\n"
            for entry in results {
                result += formatResultLine(entry) + "\n"
            }
        }

        return result
    }
}

public func epochMillisNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
