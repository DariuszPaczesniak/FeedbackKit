import Foundation

/// Saves test sessions to disk -- one JSON file per session id -- so a
/// force-quit or relaunch can restore an in-progress session. Opt-in:
/// a plain `TestSession` stays in-memory only unless something saves it
/// here (`FeedbackView` does so automatically when given a checklist).
///
/// Never throws and never crashes on I/O: read/write failures (and corrupt
/// files) are logged via `Logger` under the `TestSessionStore` tag and
/// surface as `false`/`nil`. Like `TestSession`, not thread-safe -- drive
/// it from one thread.
public struct TestSessionStore {
    private static let logTag = "TestSessionStore"

    /// The folder holding the session files.
    public let directory: URL
    private let now: () -> Int64

    /// - Parameter directory: where to keep session files. Defaults to
    ///   `Application Support/FeedbackKit/TestSessions/`, created on first save.
    public init(directory: URL? = nil, now: @escaping () -> Int64 = epochMillisNow) {
        self.directory = directory ?? TestSessionStore.defaultDirectory()
        self.now = now
    }

    /// Writes (or overwrites) the session's file. Returns false, after
    /// logging why, if it couldn't be written.
    @discardableResult
    public func save(_ session: TestSession) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(session.snapshot(savedAtMillis: now()))
            try data.write(to: fileURL(forSessionID: session.id), options: .atomic)
            return true
        } catch {
            Logger.error(tag: Self.logTag, message: "couldn't save session \(session.id): \(error.localizedDescription)")
            return false
        }
    }

    /// Restores a saved session. Pass the session's checklist to get a
    /// checklist-backed session back; it's ignored (with a warning) if its
    /// id doesn't match the one the session was saved with.
    public func load(id: String, checklist: TestChecklist? = nil) -> TestSession? {
        guard let snapshot = readSnapshot(at: fileURL(forSessionID: id)) else { return nil }
        return restore(snapshot, checklist: checklist)
    }

    /// The most recently saved session that was run against `checklist`
    /// (matched by checklist id), restored with that checklist attached.
    public func latestSession(for checklist: TestChecklist) -> TestSession? {
        let latest = allSnapshots()
            .filter { $0.checklistID == checklist.id }
            .max { $0.savedAtMillis < $1.savedAtMillis }
        return latest.map { restore($0, checklist: checklist) }
    }

    /// Deletes a session's file. A missing file isn't an error.
    public func delete(id: String) {
        let url = fileURL(forSessionID: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.error(tag: Self.logTag, message: "couldn't delete session \(id): \(error.localizedDescription)")
        }
    }

    /// Deletes every saved session in `directory`.
    public func deleteAll() {
        for url in sessionFileURLs() {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Logger.error(tag: Self.logTag, message: "couldn't delete \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Files

    /// Percent-encodes the id so any string (including "/" or "..") maps to a
    /// single, safe file name inside `directory`.
    func fileURL(forSessionID id: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        let safeName = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? UUID().uuidString
        return directory.appendingPathComponent(safeName).appendingPathExtension("json")
    }

    private func sessionFileURLs() -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        do {
            return try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
        } catch {
            Logger.error(tag: Self.logTag, message: "couldn't list \(directory.path): \(error.localizedDescription)")
            return []
        }
    }

    private func allSnapshots() -> [TestSessionSnapshot] {
        sessionFileURLs().compactMap(readSnapshot(at:))
    }

    private func readSnapshot(at url: URL) -> TestSessionSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(TestSessionSnapshot.self, from: Data(contentsOf: url))
            guard snapshot.formatVersion <= TestSessionSnapshot.currentFormatVersion else {
                Logger.warn(tag: Self.logTag, message: "skipping \(url.lastPathComponent): saved by a newer FeedbackKit (format \(snapshot.formatVersion))")
                return nil
            }
            return snapshot
        } catch {
            Logger.warn(tag: Self.logTag, message: "skipping unreadable session file \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func restore(_ snapshot: TestSessionSnapshot, checklist: TestChecklist?) -> TestSession {
        var attached = checklist
        if let checklist, checklist.id != snapshot.checklistID {
            Logger.warn(tag: Self.logTag, message: "session \(snapshot.id) was saved for checklist \(snapshot.checklistID ?? "none"), not \(checklist.id); restoring without a checklist")
            attached = nil
        }
        return TestSession(restoring: snapshot, checklist: attached, now: now)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("FeedbackKit", isDirectory: true)
            .appendingPathComponent("TestSessions", isDirectory: true)
    }
}
