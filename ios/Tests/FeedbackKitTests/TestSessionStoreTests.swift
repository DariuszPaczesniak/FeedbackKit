import XCTest
@testable import FeedbackKit

final class TestSessionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: TestSessionStore!

    private let checklist = try! TestChecklist(
        id: "smoke",
        title: "Smoke",
        version: "1",
        sections: [
            TestChecklistSection(id: "launch", title: "Launch", items: [
                TestChecklistItem(id: "cold", title: "Cold launch"),
                TestChecklistItem(id: "warm", title: "Warm launch"),
            ])
        ]
    )

    override func setUp() {
        super.setUp()
        Logger.clear()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackKitTests-\(UUID().uuidString)", isDirectory: true)
        var clock: Int64 = 1000
        store = TestSessionStore(directory: directory, now: { clock += 1; return clock })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        Logger.clear()
        super.tearDown()
    }

    func testSaveThenLoad_roundTripsNameResultsAndNotes() throws {
        let session = TestSession(name: "RC smoke", id: "session-1", checklist: checklist, now: { 42 })
        session.recordResult(for: checklist.allItems[0], result: .fail, notes: "black screen")
        session.recordResult(scenarioName: "Ad-hoc rotate", result: .pass)

        XCTAssertTrue(store.save(session))
        let restored = try XCTUnwrap(store.load(id: "session-1", checklist: checklist))

        XCTAssertEqual(restored.id, "session-1")
        XCTAssertEqual(restored.name, "RC smoke")
        XCTAssertEqual(restored.checklist, checklist)
        XCTAssertEqual(restored.results(), session.results())
        XCTAssertEqual(restored.result(forItemID: "cold")?.notes, "black screen")
        XCTAssertNil(restored.result(forItemID: "warm"))
        XCTAssertEqual(restored.exportReport(), session.exportReport())
    }

    func testSave_writesOneFilePerSessionIDUnderDirectory() throws {
        store.save(TestSession(name: "A", id: "a"))
        store.save(TestSession(name: "B", id: "b"))
        store.save(TestSession(name: "A again", id: "a"))

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["a.json", "b.json"])
        XCTAssertEqual(store.load(id: "a")?.name, "A again")
    }

    func testFileName_isSafeForHostileIDs() {
        let url = store.fileURL(forSessionID: "../../etc/passwd")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertFalse(url.lastPathComponent.contains("/"))
    }

    func testLatestSession_picksMostRecentlySavedForThatChecklist() {
        let older = TestSession(name: "Older", id: "older", checklist: checklist)
        let newer = TestSession(name: "Newer", id: "newer", checklist: checklist)
        let unrelated = TestSession(name: "Free-form", id: "free")
        store.save(older)
        store.save(newer)
        store.save(unrelated)

        let latest = store.latestSession(for: checklist)
        XCTAssertEqual(latest?.id, "newer")
        XCTAssertEqual(latest?.checklist, checklist)
    }

    func testLatestSession_whenNothingSaved_isNil() {
        XCTAssertNil(store.latestSession(for: checklist))
    }

    func testDelete_removesOnlyThatSession_andMissingFileIsNotAnError() {
        store.save(TestSession(name: "A", id: "a", checklist: checklist))
        store.save(TestSession(name: "B", id: "b", checklist: checklist))

        store.delete(id: "a")
        store.delete(id: "never-existed")

        XCTAssertNil(store.load(id: "a"))
        XCTAssertNotNil(store.load(id: "b"))
        XCTAssertEqual(Logger.size(), 0, "deleting a missing file shouldn't log an error")
    }

    func testDeleteAll_removesEverySession() {
        store.save(TestSession(name: "A", id: "a"))
        store.save(TestSession(name: "B", id: "b"))

        store.deleteAll()

        XCTAssertNil(store.load(id: "a"))
        XCTAssertNil(store.load(id: "b"))
    }

    func testLoad_corruptFile_returnsNilAndLogsInsteadOfCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ definitely not a session".utf8).write(to: directory.appendingPathComponent("bad.json"))
        store.save(TestSession(name: "Good", id: "good", checklist: checklist))

        XCTAssertNil(store.load(id: "bad"))
        XCTAssertEqual(store.latestSession(for: checklist)?.id, "good", "a corrupt file shouldn't hide valid ones")
        XCTAssertTrue(Logger.recentLogsText().contains("[WARN] TestSessionStore: skipping unreadable session file bad.json"))
    }

    func testSave_unwritableDirectory_returnsFalseAndLogs() throws {
        // A regular file where the directory should be makes createDirectory fail.
        try Data().write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(store.save(TestSession(name: "A", id: "a")))
        XCTAssertTrue(Logger.recentLogsText().contains("[ERROR] TestSessionStore: couldn't save session a"))
    }

    func testLoad_withDifferentChecklist_restoresWithoutChecklist() {
        store.save(TestSession(name: "A", id: "a", checklist: checklist))
        let other = try! TestChecklist(id: "other", title: "Other", sections: checklist.sections)

        let restored = store.load(id: "a", checklist: other)

        XCTAssertNotNil(restored)
        XCTAssertNil(restored?.checklist)
    }

    func testPlainSession_isNotPersistedUnlessSaved() {
        let session = TestSession(name: "In memory")
        session.recordResult(scenarioName: "A", result: .pass)

        XCTAssertNil(store.load(id: session.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}
