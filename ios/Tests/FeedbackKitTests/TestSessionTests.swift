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
}
