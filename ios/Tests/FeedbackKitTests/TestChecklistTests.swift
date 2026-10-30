import XCTest
@testable import FeedbackKit

final class TestChecklistTests: XCTestCase {

    private func fixtureURL(_ name: String) throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
    }

    private func checklist(_ json: String) throws -> TestChecklist {
        try TestChecklist(jsonData: Data(json.utf8))
    }

    private func assertThrows(_ expected: TestChecklistError, _ json: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try checklist(json), file: file, line: line) { error in
            XCTAssertEqual(error as? TestChecklistError, expected, file: file, line: line)
        }
    }

    func testLoad_validFixture_decodesSectionsAndItemsInOrder() throws {
        let checklist = try TestChecklist.load(from: fixtureURL("valid_checklist"))

        XCTAssertEqual(checklist.id, "example-smoke-test")
        XCTAssertEqual(checklist.title, "Example smoke test")
        XCTAssertEqual(checklist.version, "1")
        XCTAssertEqual(checklist.sections.map(\.id), ["launch", "share"])
        XCTAssertEqual(checklist.allItems.map(\.id), ["launch-cold", "launch-offline", "share-report"])
        XCTAssertNil(checklist.allItems[0].detail)
        XCTAssertEqual(checklist.allItems[1].detail, "Expect an offline banner, no crash.")
        XCTAssertEqual(checklist.item(withID: "share-report")?.title, "Send a bug report via the share sheet")
        XCTAssertNil(checklist.item(withID: "nope"))
    }

    func testLoad_duplicateItemIDsAcrossSections_throws() throws {
        XCTAssertThrowsError(try TestChecklist.load(from: fixtureURL("duplicate_item_ids"))) { error in
            XCTAssertEqual(error as? TestChecklistError, .duplicateItemID("same"))
        }
    }

    func testLoad_missingRequiredField_throwsInvalidJSONNamingTheField() throws {
        XCTAssertThrowsError(try TestChecklist.load(from: fixtureURL("missing_item_title"))) { error in
            guard case let .invalidJSON(reason) = error as? TestChecklistError else {
                return XCTFail("expected invalidJSON, got \(error)")
            }
            XCTAssertTrue(reason.contains("\"title\""), reason)
            XCTAssertTrue(reason.contains("sections[0].items[0]"), reason)
        }
    }

    func testLoad_noSections_throws() throws {
        XCTAssertThrowsError(try TestChecklist.load(from: fixtureURL("no_sections"))) { error in
            XCTAssertEqual(error as? TestChecklistError, .noSections)
        }
    }

    func testLoad_missingFile_throwsUnreadableFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feedbackkit-no-such-checklist.json")
        XCTAssertThrowsError(try TestChecklist.load(from: url)) { error in
            guard case .unreadableFile = error as? TestChecklistError else {
                return XCTFail("expected unreadableFile, got \(error)")
            }
        }
    }

    func testInit_malformedJSON_throwsInvalidJSON() {
        XCTAssertThrowsError(try checklist("{ not json")) { error in
            guard case .invalidJSON = error as? TestChecklistError else {
                return XCTFail("expected invalidJSON, got \(error)")
            }
        }
    }

    func testInit_emptySection_throws() {
        assertThrows(.emptySection(sectionID: "a"), #"{"id":"c","title":"C","sections":[{"id":"a","title":"A","items":[]}]}"#)
    }

    func testInit_duplicateSectionIDs_throws() {
        assertThrows(
            .duplicateSectionID("a"),
            #"{"id":"c","title":"C","sections":[{"id":"a","title":"A","items":[{"id":"1","title":"One"}]},{"id":"a","title":"A2","items":[{"id":"2","title":"Two"}]}]}"#
        )
    }

    func testInit_blankIDsOrTitles_throw() {
        assertThrows(.blankField("checklist id"), #"{"id":" ","title":"C","sections":[{"id":"a","title":"A","items":[{"id":"1","title":"One"}]}]}"#)
        assertThrows(.blankField("title of item \"1\""), #"{"id":"c","title":"C","sections":[{"id":"a","title":"A","items":[{"id":"1","title":""}]}]}"#)
    }

    func testInit_numericVersion_isKeptAsText() throws {
        let checklist = try checklist(#"{"id":"c","title":"C","version":3,"sections":[{"id":"a","title":"A","items":[{"id":"1","title":"One"}]}]}"#)
        XCTAssertEqual(checklist.version, "3")
    }

    func testInit_missingOrNullVersion_isNil() throws {
        XCTAssertNil(try checklist(#"{"id":"c","title":"C","sections":[{"id":"a","title":"A","items":[{"id":"1","title":"One"}]}]}"#).version)
        XCTAssertNil(try checklist(#"{"id":"c","title":"C","version":null,"sections":[{"id":"a","title":"A","items":[{"id":"1","title":"One"}]}]}"#).version)
    }

    func testMemberwiseInit_validatesToo() {
        XCTAssertThrowsError(
            try TestChecklist(
                id: "c",
                title: "C",
                sections: [
                    TestChecklistSection(id: "a", title: "A", items: [
                        TestChecklistItem(id: "1", title: "One"),
                        TestChecklistItem(id: "1", title: "Also one"),
                    ])
                ]
            )
        ) { error in
            XCTAssertEqual(error as? TestChecklistError, .duplicateItemID("1"))
        }
    }

    func testEncodeThenDecode_roundTrips() throws {
        let original = try TestChecklist.load(from: fixtureURL("valid_checklist"))
        let decoded = try TestChecklist(jsonData: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testErrors_haveHumanReadableDescriptions() {
        XCTAssertEqual(
            TestChecklistError.duplicateItemID("x").localizedDescription,
            "Test checklist has more than one item with id \"x\" (item ids must be unique across the whole checklist)."
        )
    }
}
