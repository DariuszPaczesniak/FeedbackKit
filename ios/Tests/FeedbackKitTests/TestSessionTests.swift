import XCTest
@testable import FeedbackKit

final class TestSessionTests: XCTestCase {

    func testRecordResult_appendsInOrder() {
        let session = TestSession(name: "My session", now: { 1000 })
        session.recordResult(scenarioName: "Scenario A", result: .pass)
        session.recordResult(scenarioName: "Scenario B", result: .fail, notes: "did not respond")

        let results = session.results()
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].scenarioName, "Scenario A")
        XCTAssertEqual(results[0].result, .pass)
        XCTAssertEqual(results[1].scenarioName, "Scenario B")
        XCTAssertEqual(results[1].result, .fail)
        XCTAssertEqual(results[1].notes, "did not respond")
    }

    func testRecordResult_sameScenarioTwice_producesTwoEntries() {
        let session = TestSession(name: "Session", now: { 1000 })
        session.recordResult(scenarioName: "Scenario A", result: .fail)
        session.recordResult(scenarioName: "Scenario A", result: .pass)

        XCTAssertEqual(session.results().count, 2)
    }

    func testExportReport_includesHeaderCountAndResults() {
        let session = TestSession(name: "Release candidate 1.4 smoke test", now: { 1000 })
        session.recordResult(scenarioName: "Sign in with valid credentials", result: .pass)
        session.recordResult(
            scenarioName: "Sign in with expired token",
            result: .fail,
            notes: "did not redirect to login, showed blank screen"
        )
        session.recordResult(
            scenarioName: "Password reset flow",
            result: .blocked,
            notes: "email delivery not configured in this environment"
        )

        let report = session.exportReport()

        XCTAssertTrue(report.contains("=== FeedbackKit test session: Release candidate 1.4 smoke test ==="))
        XCTAssertTrue(report.contains("3 scenario(s) recorded"))
        XCTAssertTrue(report.contains("[PASS] Sign in with valid credentials"))
        XCTAssertTrue(
            report.contains(
                "[FAIL] Sign in with expired token — did not redirect to login, showed blank screen"
            )
        )
        XCTAssertTrue(
            report.contains(
                "[BLOCKED] Password reset flow — email delivery not configured in this environment"
            )
        )
    }

    func testExportReport_withNoNotes_hasNoTrailingSeparator() {
        let session = TestSession(name: "Session", now: { 1000 })
        session.recordResult(scenarioName: "Scenario A", result: .skip)

        let report = session.exportReport()

        XCTAssertTrue(report.contains("[SKIP] Scenario A"))
        XCTAssertFalse(report.contains("Scenario A —"))
    }

    func testExportReport_withNoResults_reportsZero() {
        let session = TestSession(name: "Empty session", now: { 1000 })

        let report = session.exportReport()

        XCTAssertTrue(report.contains("0 scenario(s) recorded"))
    }

    func testClear_emptiesResults_butKeepsName() {
        let session = TestSession(name: "Session", now: { 1000 })
        session.recordResult(scenarioName: "Scenario A", result: .pass)

        session.clear()

        XCTAssertEqual(session.results().count, 0)
        XCTAssertEqual(session.name, "Session")
    }

    /// Golden test: exact bytes of a plain session's standalone export,
    /// per spec/TEST_SESSION_FORMAT.md -- must not change with checklist support.
    func testExportReport_plainSession_isByteIdenticalToSpec() {
        let session = TestSession(name: "Release candidate 1.4 smoke test", now: { 1000 })
        session.recordResult(scenarioName: "Sign in with valid credentials", result: .pass)
        session.recordResult(scenarioName: "Password reset flow", result: .blocked, notes: "no email")

        XCTAssertEqual(
            session.exportReport(),
            """
            === FeedbackKit test session: Release candidate 1.4 smoke test ===
            2 scenario(s) recorded

            [PASS] Sign in with valid credentials
            [BLOCKED] Password reset flow — no email

            """
        )
        XCTAssertEqual(TestSession(name: "Empty", now: { 1000 }).exportReport(), "=== FeedbackKit test session: Empty ===\n0 scenario(s) recorded\n\n")
    }

    // MARK: - Checklist-backed sessions

    private let checklist = try! TestChecklist(
        id: "smoke",
        title: "Smoke",
        sections: [
            TestChecklistSection(id: "launch", title: "Launch", items: [
                TestChecklistItem(id: "cold", title: "Cold launch"),
                TestChecklistItem(id: "warm", title: "Warm launch"),
                TestChecklistItem(id: "offline", title: "Offline launch"),
            ])
        ]
    )

    func testRecordResultForItem_replacesEarlierResultForSameItem() {
        var clock: Int64 = 0
        let session = TestSession(name: "S", checklist: checklist, now: { clock += 1; return clock })
        session.recordResult(for: checklist.allItems[0], result: .fail, notes: "crash")
        session.recordResult(for: checklist.allItems[1], result: .pass)
        session.recordResult(for: checklist.allItems[0], result: .pass)

        let results = session.results()
        XCTAssertEqual(results.map(\.itemID), ["warm", "cold"], "one entry per item, re-recorded item moves to the end")
        XCTAssertEqual(results[1].result, .pass)
        XCTAssertNil(results[1].notes)
        XCTAssertEqual(results[1].scenarioName, "Cold launch")
        XCTAssertEqual(results[1].recordedAtMillis, 3)
    }

    func testResetResult_returnsItemToNotRun() {
        let session = TestSession(name: "S", checklist: checklist)
        session.recordResult(for: checklist.allItems[0], result: .blocked)

        session.resetResult(forItemID: "cold")

        XCTAssertNil(session.result(forItemID: "cold"))
        XCTAssertEqual(session.checklistProgress()?.run, 0)
    }

    func testUpdateNotes_keepsResultAndTimestamp_andIsNoOpForNotRunItems() {
        var clock: Int64 = 100
        let session = TestSession(name: "S", checklist: checklist, now: { clock += 1; return clock })
        session.recordResult(for: checklist.allItems[0], result: .fail)

        session.updateNotes(forItemID: "cold", notes: "spinner never stops")
        session.updateNotes(forItemID: "warm", notes: "ignored")

        let entry = session.result(forItemID: "cold")
        XCTAssertEqual(entry?.result, .fail)
        XCTAssertEqual(entry?.notes, "spinner never stops")
        XCTAssertEqual(entry?.recordedAtMillis, 101)
        XCTAssertNil(session.result(forItemID: "warm"))

        session.updateNotes(forItemID: "cold", notes: "")
        XCTAssertNil(session.result(forItemID: "cold")?.notes, "empty notes are stored as nil")
    }

    func testChecklistProgress_countsRunItemsAndResults_ignoringAdHoc() throws {
        let session = TestSession(name: "S", checklist: checklist)
        session.recordResult(for: checklist.allItems[0], result: .pass)
        session.recordResult(for: checklist.allItems[1], result: .skip)
        session.recordResult(scenarioName: "Ad-hoc", result: .fail)

        let progress = try XCTUnwrap(session.checklistProgress())
        XCTAssertEqual(progress.total, 3)
        XCTAssertEqual(progress.run, 2)
        XCTAssertEqual(progress.notRun, 1)
        XCTAssertEqual(progress.count(of: .pass), 1)
        XCTAssertEqual(progress.count(of: .skip), 1)
        XCTAssertEqual(progress.count(of: .fail), 0)
    }

    func testChecklistProgress_withoutChecklist_isNil() {
        XCTAssertNil(TestSession(name: "Plain").checklistProgress())
    }

    func testFreeFormRecordResult_inChecklistSession_stillAppends() {
        let session = TestSession(name: "S", checklist: checklist)
        session.recordResult(scenarioName: "Rotate", result: .pass)
        session.recordResult(scenarioName: "Rotate", result: .fail)

        XCTAssertEqual(session.results().count, 2)
        XCTAssertEqual(session.results().map(\.itemID), [nil, nil])
    }
}
