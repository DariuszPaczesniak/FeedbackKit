import XCTest

/// Predefined test checklist flow (spec/TEST_CHECKLIST_FORMAT.md), driven
/// against the Example app's bundled `SampleChecklist.json`.
final class ChecklistUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Start every test from an empty session store, so a previous test's
        // saved session never shows up as "resume".
        app.launchArguments = ["-sampleChecklist", "-resetSavedSessions"]
        app.launch()
    }

    // MARK: - Helpers

    private func startSession() {
        let startButton = app.buttons["feedbackkit.startSessionButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        // The session name is pre-filled with the checklist's title.
        XCTAssertEqual(app.textFields["feedbackkit.sessionNameField"].value as? String, "Example smoke test")
        startButton.tap()
        XCTAssertTrue(app.staticTexts["feedbackkit.sessionNameLabel"].waitForExistence(timeout: 5))
    }

    private func button(_ itemID: String, _ result: String) -> XCUIElement {
        app.buttons["feedbackkit.checklist.item.\(itemID).\(result)"].firstMatch
    }

    private func status(_ itemID: String) -> XCUIElement {
        app.staticTexts["feedbackkit.checklist.item.\(itemID).status"]
    }

    private var progress: XCUIElement {
        app.staticTexts["feedbackkit.checklist.progress"]
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Tests

    /// Loading a checklist shows every item as "not run" and a 0-of-N
    /// progress header; marking items updates their status and the progress.
    func testLoadChecklistAndMarkItems() throws {
        startSession()

        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "0 of 5 run")
        XCTAssertEqual(status("launch-cold").label, "Status: Not run")

        button("launch-cold", "pass").tap()
        button("launch-offline", "fail").tap()

        XCTAssertEqual(progress.label, "2 of 5 run")
        XCTAssertEqual(status("launch-cold").label, "Status: Passed")
        XCTAssertEqual(status("launch-offline").label, "Status: Failed")
        XCTAssertTrue(button("launch-cold", "pass").isSelected)
        attachScreenshot("checklist-marked")

        // Tapping the selected status again resets the item to "not run".
        button("launch-cold", "pass").tap()
        XCTAssertEqual(status("launch-cold").label, "Status: Not run")
        XCTAssertEqual(progress.label, "1 of 5 run")

        // The marked result reaches the shared report preview, in checklist form.
        let preview = app.staticTexts["feedbackkit.reportPreviewText"]
        XCTAssertTrue(preview.label.contains("Progress: 1 of 5 run"), preview.label)
        XCTAssertTrue(preview.label.contains("[FAIL] Launch in airplane mode"), preview.label)
        XCTAssertTrue(preview.label.contains("--- Not run (4) ---"), preview.label)
    }

    /// Notes field appears once an item has a result, and its text sticks.
    func testNotesFieldAppearsAfterMarkingAnItem() throws {
        startSession()

        let notes = app.textFields["feedbackkit.checklist.item.launch-offline.notes"]
        XCTAssertFalse(notes.exists, "no notes field before a result is recorded")

        button("launch-offline", "fail").tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("crashed on launch")

        XCTAssertEqual(notes.value as? String, "crashed on launch")
    }

    /// The All / Not run / Failed filter narrows which items are listed.
    func testFilterShowsOnlyMatchingItems() throws {
        startSession()
        button("launch-cold", "pass").tap()
        button("launch-offline", "fail").tap()

        app.buttons["Failed"].tap()
        XCTAssertTrue(status("launch-offline").waitForExistence(timeout: 5))
        XCTAssertFalse(status("launch-cold").exists)
        XCTAssertFalse(status("report-share").exists)

        app.buttons["Not run"].tap()
        XCTAssertTrue(status("report-share").waitForExistence(timeout: 5))
        XCTAssertFalse(status("launch-cold").exists)
        XCTAssertFalse(status("launch-offline").exists)

        app.buttons["All"].tap()
        XCTAssertTrue(status("launch-cold").waitForExistence(timeout: 5))
    }

    /// Progress survives a relaunch: the saved session is offered for
    /// resuming, and resuming restores every recorded result and note.
    func testRelaunchRestoresProgress() throws {
        startSession()
        button("launch-cold", "pass").tap()
        button("launch-offline", "blocked").tap()
        let notes = app.textFields["feedbackkit.checklist.item.launch-offline.notes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("no airplane mode in simulator")
        XCTAssertEqual(progress.label, "2 of 5 run")

        // Relaunch WITHOUT resetting the store -- like a force-quit.
        app.terminate()
        app.launchArguments = ["-sampleChecklist"]
        app.launch()

        let savedProgress = app.staticTexts["feedbackkit.savedSessionProgressLabel"]
        XCTAssertTrue(savedProgress.waitForExistence(timeout: 5), "expected the resume prompt after relaunch")
        XCTAssertEqual(savedProgress.label, "2 of 5 run")
        XCTAssertEqual(app.staticTexts["feedbackkit.savedSessionNameLabel"].label, "Example smoke test")
        attachScreenshot("resume-prompt")

        app.buttons["feedbackkit.resumeSessionButton"].tap()

        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "2 of 5 run")
        XCTAssertEqual(status("launch-cold").label, "Status: Passed")
        XCTAssertEqual(status("launch-offline").label, "Status: Blocked")
        XCTAssertEqual(status("report-share").label, "Status: Not run")
        XCTAssertEqual(
            app.textFields["feedbackkit.checklist.item.launch-offline.notes"].value as? String,
            "no airplane mode in simulator"
        )
    }

    /// "Start new" on the resume prompt discards the saved session.
    func testStartNewDiscardsSavedSession() throws {
        startSession()
        button("launch-cold", "pass").tap()

        app.terminate()
        app.launchArguments = ["-sampleChecklist"]
        app.launch()

        let startNew = app.buttons["feedbackkit.startNewSessionButton"]
        XCTAssertTrue(startNew.waitForExistence(timeout: 5))
        startNew.tap()
        startSession()
        XCTAssertEqual(progress.label, "0 of 5 run")

        // ...and it stays discarded across another relaunch (the new, empty
        // session is what's offered now).
        app.terminate()
        app.launch()
        let savedProgress = app.staticTexts["feedbackkit.savedSessionProgressLabel"]
        XCTAssertTrue(savedProgress.waitForExistence(timeout: 5))
        XCTAssertEqual(savedProgress.label, "0 of 5 run")
    }

    /// "Clear session" (after confirming) deletes the session and its saved
    /// file: the start form returns, and a relaunch offers nothing to resume.
    func testClearSessionDeletesSavedProgress() throws {
        startSession()
        button("launch-cold", "pass").tap()

        let clear = app.buttons["feedbackkit.clearSessionButton"]
        scrollTo(clear)
        clear.tap()
        let confirm = app.buttons["feedbackkit.confirmClearSessionButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.buttons["feedbackkit.startSessionButton"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-sampleChecklist"]
        app.launch()
        XCTAssertTrue(app.buttons["feedbackkit.startSessionButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedbackkit.resumeSessionButton"].exists)
    }

    /// Free-form scenario entry still works alongside the checklist, and is
    /// listed as an ad-hoc result.
    func testAdHocScenarioStillAvailable() throws {
        startSession()

        let scenarioField = app.textFields["feedbackkit.scenarioNameField"]
        scrollTo(scenarioField)
        scenarioField.tap()
        scenarioField.typeText("Rotate to landscape")
        app.buttons["feedbackkit.passButton"].tap()

        let row = app.staticTexts["feedbackkit.resultRow.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "[PASS] Rotate to landscape")
        XCTAssertEqual(progress.label, "0 of 5 run", "ad-hoc results don't count toward checklist progress")
    }

    /// With a checklist session in progress, the send button still presents
    /// the system share sheet.
    func testShareSheetAppearsWithChecklistSession() throws {
        startSession()
        button("launch-cold", "pass").tap()
        button("launch-offline", "fail").tap()

        let sendButton = app.buttons["feedbackkit.sendButton"]
        scrollTo(sendButton)
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5), "expected the system share sheet to appear")
        attachScreenshot("share-sheet")
    }
}
