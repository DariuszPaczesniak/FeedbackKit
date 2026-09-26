import XCTest

final class ExampleUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Use case 2: preview a bug report before sending -- the report
    /// preview text should be populated as soon as the screen appears.
    func testReportPreviewIsVisible() throws {
        let preview = app.staticTexts["feedbackkit.reportPreviewText"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.contains("FeedbackKit bug report"))
        XCTAssertTrue(preview.label.contains("Recent logs"))
    }

    /// Use case 3: share a bug report as a file attachment -- tapping the
    /// send button should present the system share sheet. Full completion
    /// of a real share (e.g. to Messages) isn't exercised here -- that's an
    /// OS-owned flow outside this app's control -- only that the button
    /// works and the system sheet appears.
    func testSendButtonPresentsShareSheet() throws {
        let sendButton = app.buttons["feedbackkit.sendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        // The share sheet is a system UI, not part of this app's accessibility
        // tree by identifier -- assert on its well-known activity view label,
        // which is stable across iOS versions for UIActivityViewController.
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5), "expected the system share sheet to appear")
    }

    /// Use case 5: start a test session and record a scenario result --
    /// the full tap-through flow, not just the underlying TestSession data.
    func testStartSessionAndRecordResult() throws {
        let sessionNameField = app.textFields["feedbackkit.sessionNameField"]
        XCTAssertTrue(sessionNameField.waitForExistence(timeout: 5))
        sessionNameField.tap()
        sessionNameField.typeText("Smoke test")

        app.buttons["feedbackkit.startSessionButton"].tap()

        let sessionLabel = app.staticTexts["feedbackkit.sessionNameLabel"]
        XCTAssertTrue(sessionLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(sessionLabel.label, "Smoke test")

        let scenarioField = app.textFields["feedbackkit.scenarioNameField"]
        XCTAssertTrue(scenarioField.waitForExistence(timeout: 5))
        scenarioField.tap()
        scenarioField.typeText("Sign in with valid credentials")

        app.buttons["feedbackkit.passButton"].tap()

        let resultRow = app.staticTexts["feedbackkit.resultRow.0"]
        XCTAssertTrue(resultRow.waitForExistence(timeout: 5))
        XCTAssertEqual(resultRow.label, "[PASS] Sign in with valid credentials")
    }

    /// Use case 5 (notes variant): a result recorded with notes shows the
    /// " — notes" suffix, per spec/TEST_SESSION_FORMAT.md.
    func testRecordResultWithNotesShowsSuffix() throws {
        let sessionNameField = app.textFields["feedbackkit.sessionNameField"]
        XCTAssertTrue(sessionNameField.waitForExistence(timeout: 5))
        sessionNameField.tap()
        sessionNameField.typeText("Smoke test")
        app.buttons["feedbackkit.startSessionButton"].tap()

        let scenarioField = app.textFields["feedbackkit.scenarioNameField"]
        XCTAssertTrue(scenarioField.waitForExistence(timeout: 5))
        scenarioField.tap()
        scenarioField.typeText("Sign in with expired token")

        let notesField = app.textFields["feedbackkit.notesField"]
        notesField.tap()
        notesField.typeText("did not redirect to login")

        app.buttons["feedbackkit.failButton"].tap()

        let resultRow = app.staticTexts["feedbackkit.resultRow.0"]
        XCTAssertTrue(resultRow.waitForExistence(timeout: 5))
        XCTAssertEqual(resultRow.label, "[FAIL] Sign in with expired token — did not redirect to login")
    }

    /// Use case 7: a recorded test-session result shows up in the same
    /// report preview used for the bug-report share, merged with the logs.
    func testRecordedResultAppearsInSharedReportPreview() throws {
        let sessionNameField = app.textFields["feedbackkit.sessionNameField"]
        XCTAssertTrue(sessionNameField.waitForExistence(timeout: 5))
        sessionNameField.tap()
        sessionNameField.typeText("Smoke test")
        app.buttons["feedbackkit.startSessionButton"].tap()

        let scenarioField = app.textFields["feedbackkit.scenarioNameField"]
        XCTAssertTrue(scenarioField.waitForExistence(timeout: 5))
        scenarioField.tap()
        scenarioField.typeText("Sign in with valid credentials")
        app.buttons["feedbackkit.passButton"].tap()

        let preview = app.staticTexts["feedbackkit.reportPreviewText"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.contains("=== Test session: Smoke test ==="))
        XCTAssertTrue(preview.label.contains("[PASS] Sign in with valid credentials"))
    }
}
