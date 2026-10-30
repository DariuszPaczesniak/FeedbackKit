import Foundation

/// A predefined test plan a host app hands to FeedbackKit, so a QA tester
/// ticks through known items instead of retyping scenario names. File
/// format, validation rules and the stable-id rule are specified in
/// `spec/TEST_CHECKLIST_FORMAT.md`.
///
/// Every `TestChecklist` value is valid: both the throwing memberwise
/// initializer and decoding run the same validation, so UI and report
/// code can rely on non-empty sections and unique ids.
public struct TestChecklist: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let version: String?
    public let sections: [TestChecklistSection]

    public init(id: String, title: String, version: String? = nil, sections: [TestChecklistSection]) throws {
        self.id = id
        self.title = title
        self.version = version
        self.sections = sections
        try validate()
    }

    /// Decodes and validates a checklist from UTF-8 JSON. Malformed JSON is
    /// reported as `TestChecklistError.invalidJSON` rather than a raw
    /// `DecodingError`, so callers have one error type to handle.
    public init(jsonData: Data) throws {
        do {
            self = try JSONDecoder().decode(TestChecklist.self, from: jsonData)
        } catch let error as TestChecklistError {
            throw error
        } catch {
            throw TestChecklistError.invalidJSON(reason: describe(error))
        }
    }

    /// Reads and decodes a checklist file (e.g. one bundled in the host app).
    public static func load(from url: URL) throws -> TestChecklist {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TestChecklistError.unreadableFile(path: url.path, reason: error.localizedDescription)
        }
        return try TestChecklist(jsonData: data)
    }

    /// Every item across all sections, in checklist order.
    public var allItems: [TestChecklistItem] {
        sections.flatMap(\.items)
    }

    public func item(withID itemID: String) -> TestChecklistItem? {
        for section in sections {
            if let item = section.items.first(where: { $0.id == itemID }) {
                return item
            }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, version, sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        // `version` is a string per the spec, but a bare JSON number ("version": 3)
        // is the natural thing to write by hand -- accept it and keep its text form.
        if let text = try? container.decodeIfPresent(String.self, forKey: .version) {
            version = text
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .version) {
            version = String(number)
        } else if let number = try? container.decodeIfPresent(Double.self, forKey: .version) {
            version = String(number)
        } else if container.contains(.version), try !container.decodeNil(forKey: .version) {
            throw TestChecklistError.invalidJSON(reason: "\"version\" must be a string or a number")
        } else {
            version = nil
        }
        sections = try container.decode([TestChecklistSection].self, forKey: .sections)
        try validate()
    }

    /// Enforces the rules in `spec/TEST_CHECKLIST_FORMAT.md` ("Validation").
    private func validate() throws {
        try requireNonBlank(id, field: "checklist id")
        try requireNonBlank(title, field: "checklist title")
        guard !sections.isEmpty else { throw TestChecklistError.noSections }

        var sectionIDs = Set<String>()
        var itemIDs = Set<String>()
        for section in sections {
            try requireNonBlank(section.id, field: "section id")
            try requireNonBlank(section.title, field: "title of section \"\(section.id)\"")
            guard sectionIDs.insert(section.id).inserted else {
                throw TestChecklistError.duplicateSectionID(section.id)
            }
            guard !section.items.isEmpty else {
                throw TestChecklistError.emptySection(sectionID: section.id)
            }
            for item in section.items {
                try requireNonBlank(item.id, field: "item id in section \"\(section.id)\"")
                try requireNonBlank(item.title, field: "title of item \"\(item.id)\"")
                guard itemIDs.insert(item.id).inserted else {
                    throw TestChecklistError.duplicateItemID(item.id)
                }
            }
        }
    }
}

public struct TestChecklistSection: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let items: [TestChecklistItem]

    public init(id: String, title: String, items: [TestChecklistItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// One test in a checklist. `id` is the stable key results are stored
/// under -- it must never be reused for a different test, so editing
/// `title`/`detail` never orphans recorded progress.
public struct TestChecklistItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String?

    public init(id: String, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public enum TestChecklistError: Error, Equatable, LocalizedError {
    case unreadableFile(path: String, reason: String)
    case invalidJSON(reason: String)
    case blankField(String)
    case noSections
    case emptySection(sectionID: String)
    case duplicateSectionID(String)
    case duplicateItemID(String)

    public var errorDescription: String? {
        switch self {
        case let .unreadableFile(path, reason):
            return "Couldn't read test checklist at \(path): \(reason)"
        case let .invalidJSON(reason):
            return "Test checklist is not valid: \(reason)"
        case let .blankField(field):
            return "Test checklist has an empty \(field)."
        case .noSections:
            return "Test checklist has no sections."
        case let .emptySection(sectionID):
            return "Test checklist section \"\(sectionID)\" has no items."
        case let .duplicateSectionID(sectionID):
            return "Test checklist has more than one section with id \"\(sectionID)\"."
        case let .duplicateItemID(itemID):
            return "Test checklist has more than one item with id \"\(itemID)\" (item ids must be unique across the whole checklist)."
        }
    }
}

private func requireNonBlank(_ value: String, field: String) throws {
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw TestChecklistError.blankField(field)
    }
}

/// Turns a `DecodingError` into a one-line, human-readable reason that
/// names the offending key path, instead of Foundation's verbose dump.
private func describe(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
        return error.localizedDescription
    }
    func path(_ codingPath: [CodingKey]) -> String {
        let joined = codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return joined.isEmpty ? "the top level" : String(joined.drop(while: { $0 == "." }))
    }
    switch decodingError {
    case let .keyNotFound(key, context):
        let parent = context.codingPath.isEmpty ? "" : " in \(path(context.codingPath))"
        return "missing required field \"\(key.stringValue)\"\(parent)"
    case let .typeMismatch(_, context):
        return "wrong type at \(path(context.codingPath))"
    case let .valueNotFound(_, context):
        return "missing value at \(path(context.codingPath))"
    case let .dataCorrupted(context):
        return context.codingPath.isEmpty ? "malformed JSON" : "malformed value at \(path(context.codingPath))"
    @unknown default:
        return error.localizedDescription
    }
}
