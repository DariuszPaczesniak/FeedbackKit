import XCTest
@testable import FeedbackKit

final class BugReportBundlerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Logger.clear()
    }

    override func tearDown() {
        super.tearDown()
        Logger.clear()
    }

    func testBuild_includesDeviceInfoAndRecentLogs() {
        Logger.info(tag: "Discovery", message: "advertising + scanning")
        Logger.error(tag: "TrustGroup", message: "delete failed")

        let bundler = BugReportBundler(deviceInfoSummary: { "App version: 0.1\nPlatform: Test OS 1.0\n" })
        let report = bundler.build()

        XCTAssertTrue(report.contains("=== FeedbackKit bug report ==="))
        XCTAssertTrue(report.contains("App version: 0.1"))
        XCTAssertTrue(report.contains("Platform: Test OS 1.0"))
        XCTAssertTrue(report.contains("advertising + scanning"))
        XCTAssertTrue(report.contains("delete failed"))
    }

    func testBuild_reportsHowManyLogLinesAreIncluded() {
        Logger.info(tag: "Tag", message: "one")
        Logger.info(tag: "Tag", message: "two")
        Logger.info(tag: "Tag", message: "three")

        let bundler = BugReportBundler(deviceInfoSummary: { "" })
        let report = bundler.build()

        XCTAssertTrue(report.contains("Recent logs (3 lines)"))
    }

    func testBuild_stillProducesAReport_whenNoLogsHaveBeenRecorded() {
        let bundler = BugReportBundler(deviceInfoSummary: { "App version: 0.1\n" })
        let report = bundler.build()

        XCTAssertTrue(report.contains("Recent logs (0 lines)"))
    }

    func testBuild_withNoTestSession_isUnchanged() {
        let bundler = BugReportBundler(deviceInfoSummary: { "App version: 0.1\n" })
        let report = bundler.build()

        XCTAssertFalse(report.contains("Test session"))
    }

    func testBuild_withTestSession_appendsMergedSection() {
        let session = TestSession(name: "Smoke test", now: { 2000 })
        session.recordResult(scenarioName: "Scenario A", result: .pass)
        session.recordResult(scenarioName: "Scenario B", result: .fail, notes: "crashed")

        let bundler = BugReportBundler(
            deviceInfoSummary: { "App version: 0.1\n" },
            testSession: session
        )
        let report = bundler.build()

        XCTAssertTrue(report.contains("=== Test session: Smoke test ==="))
        XCTAssertFalse(report.contains("=== FeedbackKit test session:"))
        XCTAssertTrue(report.contains("2 scenario(s) recorded"))
        XCTAssertTrue(report.contains("[PASS] Scenario A"))
        XCTAssertTrue(report.contains("[FAIL] Scenario B — crashed"))
    }

    /// Golden test: the exact bytes of a merged report for a plain
    /// (checklist-less) session, pinned so checklist support can't drift it.
    func testBuild_withPlainTestSession_isByteIdenticalToSpec() {
        Logger.clear()
        let session = TestSession(name: "Smoke test", now: { 2000 })
        session.recordResult(scenarioName: "Scenario A", result: .pass)
        session.recordResult(scenarioName: "Scenario B", result: .fail, notes: "crashed")
        session.recordResult(scenarioName: "Scenario C", result: .skip, notes: "")

        let bundler = BugReportBundler(
            deviceInfoSummary: { "App version: 0.1" },
            now: { 1695384924000 },
            testSession: session
        )

        XCTAssertEqual(
            bundler.build(),
            """
            === FeedbackKit bug report ===
            Generated at (epoch millis): 1695384924000

            App version: 0.1

            === Recent logs (0 lines) ===

            === Test session: Smoke test ===
            3 scenario(s) recorded

            [PASS] Scenario A
            [FAIL] Scenario B — crashed
            [SKIP] Scenario C

            """
        )
    }
}
