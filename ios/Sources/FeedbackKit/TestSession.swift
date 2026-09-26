import Foundation

public enum TestResult: String {
    case pass = "PASS"
    case fail = "FAIL"
    case skip = "SKIP"
    case blocked = "BLOCKED"
}

public struct TestScenarioResult {
    public let scenarioName: String
    public let result: TestResult
    public let notes: String?
    public let recordedAtMillis: Int64
}

public final class TestSession {
    public let name: String
    private let now: () -> Int64
    private var entries: [TestScenarioResult] = []

    public init(name: String, now: @escaping () -> Int64 = epochMillisNow) {
        self.name = name
        self.now = now
    }

    public func recordResult(scenarioName: String, result: TestResult, notes: String? = nil) {
        entries.append(
            TestScenarioResult(
                scenarioName: scenarioName,
                result: result,
                notes: notes,
                recordedAtMillis: now()
            )
        )
    }

    public func results() -> [TestScenarioResult] {
        entries
    }

    public func exportReport() -> String {
        var result = ""
        result += "=== FeedbackKit test session: \(name) ===\n"
        result += "\(entries.count) scenario(s) recorded\n"
        result += "\n"
        for entry in entries {
            result += formatResultLine(entry) + "\n"
        }
        return result
    }

    public func clear() {
        entries.removeAll()
    }
}

func formatResultLine(_ entry: TestScenarioResult) -> String {
    let notesSuffix: String
    if let notes = entry.notes, !notes.isEmpty {
        notesSuffix = " — \(notes)"
    } else {
        notesSuffix = ""
    }
    return "[\(entry.result.rawValue)] \(entry.scenarioName)\(notesSuffix)"
}
