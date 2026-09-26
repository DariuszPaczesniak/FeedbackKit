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
}
