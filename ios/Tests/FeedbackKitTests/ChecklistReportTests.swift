import XCTest
@testable import FeedbackKit

/// Report export for checklist-backed sessions, per
/// spec/TEST_CHECKLIST_FORMAT.md ("Exported report additions").
final class ChecklistReportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Logger.clear()
    }

    override func tearDown() {
        Logger.clear()
        super.tearDown()
    }

    private func makeChecklist(coldTitle: String = "Cold launch shows the home screen") throws -> TestChecklist {
        try TestChecklist(
            id: "example-smoke-test",
            title: "Example smoke test",
            version: "1",
            sections: [
                TestChecklistSection(id: "launch", title: "Launch", items: [
                    TestChecklistItem(id: "launch-cold", title: coldTitle),
                    TestChecklistItem(id: "launch-offline", title: "Launch in airplane mode", detail: "Not in the report"),
                ]),
                TestChecklistSection(id: "share", title: "Sharing", items: [
                    TestChecklistItem(id: "share-report", title: "Send a bug report via the share sheet"),
                ]),
            ]
        )
    }

    /// The example in the spec, byte for byte, merged into a bug report.
    func testBundlerMergedSection_matchesSpecExample() throws {
        let checklist = try makeChecklist()
        let session = TestSession(name: "RC 1.1 smoke test", checklist: checklist, now: { 1000 })
        session.recordResult(for: checklist.allItems[0], result: .pass)
        session.recordResult(for: checklist.allItems[1], result: .fail, notes: "no offline banner")
        session.recordResult(scenarioName: "Rotate to landscape on the home screen", result: .pass)

        let report = BugReportBundler(
            deviceInfoSummary: { "App version: 0.1" },
            now: { 1695384924000 },
            testSession: session
        ).build()

        XCTAssertEqual(
            report,
            """
            === FeedbackKit bug report ===
            Generated at (epoch millis): 1695384924000

            App version: 0.1

            === Recent logs (0 lines) ===

            === Test session: RC 1.1 smoke test ===
            3 scenario(s) recorded
            Checklist: Example smoke test (example-smoke-test, version 1)
            Progress: 2 of 3 run
            Results: 1 PASS, 1 FAIL, 0 SKIP, 0 BLOCKED, 1 NOT RUN

            --- Launch ---
            [PASS] Cold launch shows the home screen
            [FAIL] Launch in airplane mode — no offline banner

            --- Sharing ---
            [NOT RUN] Send a bug report via the share sheet

            --- Ad-hoc scenarios ---
            [PASS] Rotate to landscape on the home screen

            --- Not run (1) ---
            - Sharing: Send a bug report via the share sheet

            """
        )
    }

    func testStandaloneExport_usesFeedbackKitHeaderAndSameBody() throws {
        let checklist = try makeChecklist()
        let session = TestSession(name: "S", checklist: checklist, now: { 1000 })
        session.recordResult(for: checklist.allItems[2], result: .skip)

        let report = session.exportReport()

        XCTAssertTrue(report.hasPrefix("=== FeedbackKit test session: S ===\n1 scenario(s) recorded\nChecklist:"))
        XCTAssertTrue(report.contains("[SKIP] Send a bug report via the share sheet\n"))
        XCTAssertTrue(report.hasSuffix("--- Not run (2) ---\n- Launch: Cold launch shows the home screen\n- Launch: Launch in airplane mode\n"))
    }

    func testAllItemsRun_omitsNotRunAndAdHocBlocks_andVersionIsOptional() throws {
        let checklist = try TestChecklist(id: "c", title: "C", sections: [
            TestChecklistSection(id: "a", title: "A", items: [TestChecklistItem(id: "1", title: "One")]),
        ])
        let session = TestSession(name: "S", checklist: checklist, now: { 1000 })
        session.recordResult(for: checklist.allItems[0], result: .blocked, notes: "env down")

        XCTAssertEqual(
            session.exportReport(),
            """
            === FeedbackKit test session: S ===
            1 scenario(s) recorded
            Checklist: C (c)
            Progress: 1 of 1 run
            Results: 0 PASS, 0 FAIL, 0 SKIP, 1 BLOCKED, 0 NOT RUN

            --- A ---
            [BLOCKED] One — env down

            """
        )
    }

    /// Stable-id rule: a result recorded under an old title is reported
    /// under the item's new title once the checklist is edited.
    func testEditedItemTitle_keepsResult_andReportsNewTitle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FeedbackKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TestSessionStore(directory: directory)

        let original = try makeChecklist(coldTitle: "Cold launch")
        let session = TestSession(name: "S", id: "s", checklist: original)
        session.recordResult(for: original.allItems[0], result: .fail, notes: "slow")
        XCTAssertTrue(store.save(session))

        let edited = try makeChecklist(coldTitle: "Cold launch reaches home in under 2s")
        let restored = try XCTUnwrap(store.load(id: "s", checklist: edited))

        XCTAssertEqual(restored.result(forItemID: "launch-cold")?.result, .fail)
        XCTAssertEqual(restored.checklistProgress()?.run, 1)
        let report = restored.exportReport()
        XCTAssertTrue(report.contains("[FAIL] Cold launch reaches home in under 2s — slow\n"), report)
        XCTAssertFalse(report.contains("[FAIL] Cold launch — slow"), report)
    }

    /// A result whose item id the checklist no longer has isn't lost: it's
    /// reported as ad-hoc under the name it was recorded with.
    func testOrphanedItemResult_isReportedAsAdHoc() throws {
        let checklist = try makeChecklist()
        let session = TestSession(name: "S", checklist: checklist, now: { 1000 })
        session.recordResult(for: TestChecklistItem(id: "retired-item", title: "Old test"), result: .pass)

        let report = session.exportReport()

        XCTAssertTrue(report.contains("--- Ad-hoc scenarios ---\n[PASS] Old test\n"), report)
        XCTAssertTrue(report.contains("Progress: 0 of 3 run"), report)
    }

    func testDetailText_isNotInReport() throws {
        let checklist = try makeChecklist()
        let session = TestSession(name: "S", checklist: checklist)
        XCTAssertFalse(session.exportReport().contains("Not in the report"))
    }
}
