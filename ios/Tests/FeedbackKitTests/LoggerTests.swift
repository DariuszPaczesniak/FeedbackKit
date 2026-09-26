import XCTest
@testable import FeedbackKit

final class LoggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Logger.clear()
    }

    override func tearDown() {
        super.tearDown()
        Logger.clear()
    }

    func testLog_appendsAFormattedLine() {
        Logger.info(tag: "Discovery", message: "started scanning")

        let text = Logger.recentLogsText()
        XCTAssertTrue(text.contains("[INFO]"))
        XCTAssertTrue(text.contains("Discovery:"))
        XCTAssertTrue(text.contains("started scanning"))
    }

    func testLog_preservesOrder() {
        Logger.info(tag: "Tag", message: "first")
        Logger.info(tag: "Tag", message: "second")
        Logger.info(tag: "Tag", message: "third")

        let lines = Logger.recentLogsText().split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].contains("first"))
        XCTAssertTrue(lines[1].contains("second"))
        XCTAssertTrue(lines[2].contains("third"))
    }

    func testLog_eachConvenienceMethod_usesTheRightLevel() {
        Logger.debug(tag: "Tag", message: "d")
        Logger.info(tag: "Tag", message: "i")
        Logger.warn(tag: "Tag", message: "w")
        Logger.error(tag: "Tag", message: "e")

        let lines = Logger.recentLogsText().split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].contains("[DEBUG]"))
        XCTAssertTrue(lines[1].contains("[INFO]"))
        XCTAssertTrue(lines[2].contains("[WARN]"))
        XCTAssertTrue(lines[3].contains("[ERROR]"))
    }

    func testLog_capsAtMaxEntries_evictingOldestFirst() {
        for i in 0..<520 {
            Logger.info(tag: "Tag", message: "message-\(i)")
        }

        XCTAssertEqual(Logger.size(), 500)
        let lines = Logger.recentLogsText().split(separator: "\n").map(String.init)
        XCTAssertFalse(lines.contains { $0.hasSuffix("message-0") }, "oldest entries should have been evicted")
        XCTAssertFalse(lines.contains { $0.hasSuffix("message-19") }, "oldest entries should have been evicted")
        XCTAssertTrue(lines.contains { $0.hasSuffix("message-20") }, "the 500 most recent entries should remain")
        XCTAssertTrue(lines.contains { $0.hasSuffix("message-519") }, "the most recent entry should remain")
    }

    func testClear_emptiesTheBuffer() {
        Logger.info(tag: "Tag", message: "something")
        XCTAssertGreaterThan(Logger.size(), 0)

        Logger.clear()

        XCTAssertEqual(Logger.size(), 0)
        XCTAssertEqual(Logger.recentLogsText(), "")
    }
}
