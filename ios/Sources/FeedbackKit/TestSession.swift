import Foundation

public enum TestResult: String {
    case pass = "PASS"
    case fail = "FAIL"
    case skip = "SKIP"
    case blocked = "BLOCKED"
}

// Encoded as its raw value ("PASS", ...), for TestSessionStore's files.
extension TestResult: Codable, Sendable {}

public struct TestScenarioResult: Codable, Equatable {
    public let scenarioName: String
    public let result: TestResult
    public let notes: String?
    public let recordedAtMillis: Int64
    /// The checklist item this result belongs to, or nil for a free-form
    /// scenario recorded via `recordResult(scenarioName:result:notes:)`.
    public let itemID: String?

    init(scenarioName: String, result: TestResult, notes: String?, recordedAtMillis: Int64, itemID: String? = nil) {
        self.scenarioName = scenarioName
        self.result = result
        self.notes = notes
        self.recordedAtMillis = recordedAtMillis
        self.itemID = itemID
    }
}

public final class TestSession {
    /// Stable identity, used as the persisted file name by `TestSessionStore`.
    public let id: String
    public let name: String
    /// The predefined test plan this session runs through, if any. With a
    /// checklist, results are keyed by item id and the exported report adds
    /// progress and a "Not run" list (`spec/TEST_CHECKLIST_FORMAT.md`);
    /// without one, behavior and output are exactly as before.
    public let checklist: TestChecklist?
    private let now: () -> Int64
    private var entries: [TestScenarioResult] = []

    public init(
        name: String,
        id: String = UUID().uuidString,
        checklist: TestChecklist? = nil,
        now: @escaping () -> Int64 = epochMillisNow
    ) {
        self.id = id
        self.name = name
        self.checklist = checklist
        self.now = now
    }

    /// Restores a session saved by `TestSessionStore`.
    init(restoring snapshot: TestSessionSnapshot, checklist: TestChecklist?, now: @escaping () -> Int64) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.checklist = checklist
        self.now = now
        self.entries = snapshot.results
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

    /// Records (or changes) the result for a checklist item. Unlike the
    /// free-form overload this replaces any earlier result for the same
    /// item id -- one result per item -- moving it to the end of `results()`.
    public func recordResult(for item: TestChecklistItem, result: TestResult, notes: String? = nil) {
        entries.removeAll { $0.itemID == item.id }
        entries.append(
            TestScenarioResult(
                scenarioName: item.title,
                result: result,
                notes: (notes?.isEmpty ?? true) ? nil : notes,
                recordedAtMillis: now(),
                itemID: item.id
            )
        )
    }

    /// Replaces just the notes of an item's existing result (keeping its
    /// result, position, and timestamp). No-op if the item has no result.
    public func updateNotes(forItemID itemID: String, notes: String?) {
        guard let index = entries.firstIndex(where: { $0.itemID == itemID }) else { return }
        let entry = entries[index]
        entries[index] = TestScenarioResult(
            scenarioName: entry.scenarioName,
            result: entry.result,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            recordedAtMillis: entry.recordedAtMillis,
            itemID: itemID
        )
    }

    /// Returns a checklist item to "not run" -- which is the absence of a
    /// result, not a `TestResult` case.
    public func resetResult(forItemID itemID: String) {
        entries.removeAll { $0.itemID == itemID }
    }

    public func result(forItemID itemID: String) -> TestScenarioResult? {
        entries.first { $0.itemID == itemID }
    }

    /// Run/not-run counts over the checklist's items; nil without a checklist.
    public func checklistProgress() -> TestChecklistProgress? {
        guard let checklist else { return nil }
        var counts: [TestResult: Int] = [:]
        var run = 0
        for item in checklist.allItems {
            if let entry = result(forItemID: item.id) {
                run += 1
                counts[entry.result, default: 0] += 1
            }
        }
        return TestChecklistProgress(total: checklist.allItems.count, run: run, counts: counts)
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

    func snapshot(savedAtMillis: Int64) -> TestSessionSnapshot {
        TestSessionSnapshot(
            formatVersion: TestSessionSnapshot.currentFormatVersion,
            id: id,
            name: name,
            checklistID: checklist?.id,
            savedAtMillis: savedAtMillis,
            results: entries
        )
    }
}

/// How far a checklist-backed session has got. "Run" means the item has
/// any recorded result (a deliberate SKIP counts as run).
public struct TestChecklistProgress: Equatable, Sendable {
    public let total: Int
    public let run: Int
    public let counts: [TestResult: Int]

    public var notRun: Int { total - run }

    public func count(of result: TestResult) -> Int {
        counts[result, default: 0]
    }
}

/// The on-disk shape of a saved session (one JSON file per session id).
/// Stores the checklist's id only, not the checklist -- it's re-supplied on
/// restore so edited titles apply. Platform-local cache, not an
/// interchange format.
struct TestSessionSnapshot: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let id: String
    let name: String
    let checklistID: String?
    let savedAtMillis: Int64
    let results: [TestScenarioResult]
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
