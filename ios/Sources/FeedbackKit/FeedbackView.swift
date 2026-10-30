#if os(iOS)
import SwiftUI
import PhotosUI
import UIKit

/// Drop-in feedback screen: previews + shares a bug report (device info +
/// recent Logger lines), and optionally lets a QA tester run a named test
/// session -- recording PASS/FAIL/SKIP/BLOCKED results per scenario --
/// merged into the same shared report. A host app can use this as-is, or
/// call `BugReportBundler`/`TestSession` directly to build its own UI.
///
/// Given a `TestChecklist`, the session runs through that predefined plan
/// instead (per-item status, progress, filter) and is saved to disk via
/// `TestSessionStore` after every change, so a relaunch offers to resume
/// it. Without one, behavior is unchanged: free-form, in-memory only.
public struct FeedbackView: View {
    private static let maxAttachments = 5

    private let checklist: TestChecklist?
    /// Only checklist sessions are persisted; plain ones stay in-memory.
    private let store: TestSessionStore?

    @State private var sessionName = ""
    @State private var session: TestSession?
    @State private var scenarioName = ""
    @State private var notes = ""
    @State private var resultsVersion = 0
    @State private var reportFileURL: URL?
    @State private var reportText = ""
    @State private var shareItems: [URL] = []

    @State private var attachments: [FeedbackAttachment] = []
    @State private var markupAttachmentID: FeedbackAttachment.ID?
    @State private var showingAddAttachmentDialog = false
    @State private var photoPickerItem: PhotosPickerItem?

    @State private var savedSession: TestSession?
    @State private var didCheckForSavedSession = false
    @State private var checklistFilter: ChecklistFilter = .all
    @State private var collapsedSectionIDs: Set<String> = []
    @State private var notesVersion = 0
    @State private var showingClearConfirmation = false

    /// - Parameter checklist: a predefined test plan to run through. `nil`
    ///   (the default) keeps the original free-form, in-memory session UI.
    public init(checklist: TestChecklist? = nil) {
        self.checklist = checklist
        self.store = checklist == nil ? nil : TestSessionStore()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Test session")
                    .font(.headline)

                if let session {
                    Text(session.name)
                        .accessibilityIdentifier("feedbackkit.sessionNameLabel")

                    if let checklist = session.checklist {
                        checklistContent(checklist, session: session)

                        Text("Ad-hoc scenario")
                            .font(.subheadline)
                            .padding(.top, 8)
                    }

                    TextField("Scenario name", text: $scenarioName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("feedbackkit.scenarioNameField")
                    TextField("Notes (optional)", text: $notes)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("feedbackkit.notesField")

                    HStack {
                        Button("Pass") { record(.pass, in: session) }
                            .accessibilityIdentifier("feedbackkit.passButton")
                        Button("Fail") { record(.fail, in: session) }
                            .accessibilityIdentifier("feedbackkit.failButton")
                        Button("Skip") { record(.skip, in: session) }
                            .accessibilityIdentifier("feedbackkit.skipButton")
                        Button("Blocked") { record(.blocked, in: session) }
                            .accessibilityIdentifier("feedbackkit.blockedButton")
                    }
                    .buttonStyle(.bordered)

                    Text(session.checklist == nil ? "Recorded results" : "Ad-hoc results")
                        .font(.subheadline)
                    // Reads resultsVersion so this redraws after each recordResult call --
                    // TestSession itself isn't an ObservableObject, it's a plain accumulator.
                    let _ = resultsVersion
                    // With a checklist, item results are shown on their rows above;
                    // this list is only the free-form (ad-hoc) entries.
                    let listedResults = session.checklist == nil
                        ? session.results()
                        : session.results().filter { $0.itemID == nil }
                    ForEach(Array(listedResults.enumerated()), id: \.offset) { index, entry in
                        let notesSuffix = (entry.notes?.isEmpty == false) ? " — \(entry.notes!)" : ""
                        Text("[\(entry.result.rawValue)] \(entry.scenarioName)\(notesSuffix)")
                            .accessibilityIdentifier("feedbackkit.resultRow.\(index)")
                    }

                    Button("Clear session", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .padding(.top, 4)
                    .accessibilityIdentifier("feedbackkit.clearSessionButton")
                    .confirmationDialog(
                        "Clear this test session?",
                        isPresented: $showingClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear session", role: .destructive) { clearSession(session) }
                            .accessibilityIdentifier("feedbackkit.confirmClearSessionButton")
                    } message: {
                        Text("All recorded results and notes in \"\(session.name)\" will be deleted.")
                    }
                } else if let savedSession {
                    savedSessionCard(savedSession)
                } else {
                    TextField("Session name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("feedbackkit.sessionNameField")
                    Button("Start session") {
                        if !sessionName.trimmingCharacters(in: .whitespaces).isEmpty {
                            session = TestSession(name: sessionName, checklist: checklist)
                            sessionDidChange()
                        }
                    }
                    .accessibilityIdentifier("feedbackkit.startSessionButton")
                }

                Divider()

                Text("Feedback")
                    .font(.headline)

                attachmentStrip

                if !shareItems.isEmpty {
                    ShareLink(items: shareItems) {
                        Text("Send bug report")
                    }
                    .accessibilityIdentifier("feedbackkit.sendButton")
                }

                Divider()
                Text("Report preview")
                Text(reportText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("feedbackkit.reportPreviewText")
            }
            .padding()
        }
        .onAppear {
            checkForSavedSession()
            buildReport()
        }
        .onChange(of: resultsVersion) { _ in buildReport() }
        // Notes edits update the session (and its saved file) per keystroke,
        // but the share payload is rebuilt only once typing pauses.
        .task(id: notesVersion) {
            guard notesVersion > 0 else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            buildReport()
        }
        .confirmationDialog(
            "Add Screenshot",
            isPresented: $showingAddAttachmentDialog,
            titleVisibility: .visible
        ) {
            Button("Capture Current Screen") { captureCurrentScreen() }
                .accessibilityIdentifier("feedbackkit.captureScreenButton")
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Text("Choose from Photos")
            }
            .accessibilityIdentifier("feedbackkit.choosePhotoButton")
        }
        .onChange(of: photoPickerItem) { newItem in
            guard let newItem else { return }
            Task {
                await addAttachmentFromPhotoPicker(newItem)
                photoPickerItem = nil
            }
        }
        .sheet(item: markupBinding) { attachment in
            AttachmentMarkupView(attachment: binding(for: attachment.id))
                .onDisappear { buildReport() }
        }
    }

    // MARK: - Checklist

    @ViewBuilder
    private func checklistContent(_ checklist: TestChecklist, session: TestSession) -> some View {
        // Same redraw trigger as the results list: TestSession isn't observable.
        let _ = resultsVersion
        let _ = notesVersion
        let progress = session.checklistProgress() ?? TestChecklistProgress(total: 0, run: 0, counts: [:])
        let visibleSections = checklist.sections.compactMap { section -> (TestChecklistSection, [TestChecklistItem])? in
            let items = section.items.filter { checklistFilter.includes(session.result(forItemID: $0.id)) }
            return items.isEmpty ? nil : (section, items)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(checklist.title)
                .font(.subheadline.weight(.semibold))
            Text("\(progress.run) of \(progress.total) run")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("feedbackkit.checklist.progress")
            ProgressView(value: Double(progress.run), total: Double(max(progress.total, 1)))
                .accessibilityHidden(true)
        }

        Picker("Show", selection: $checklistFilter) {
            ForEach(ChecklistFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("feedbackkit.checklist.filter")

        if visibleSections.isEmpty {
            Text("No items match this filter.")
                .foregroundColor(.secondary)
                .accessibilityIdentifier("feedbackkit.checklist.emptyFilterLabel")
        }

        ForEach(visibleSections, id: \.0.id) { section, items in
            DisclosureGroup(isExpanded: expansionBinding(for: section.id)) {
                ForEach(items) { item in
                    ChecklistItemRow(
                        item: item,
                        entry: session.result(forItemID: item.id),
                        onSelect: { result in
                            session.recordResult(for: item, result: result, notes: session.result(forItemID: item.id)?.notes)
                            sessionDidChange()
                        },
                        onReset: {
                            session.resetResult(forItemID: item.id)
                            sessionDidChange()
                        },
                        notes: notesBinding(for: item, in: session)
                    )
                    Divider()
                }
            } label: {
                let sectionRun = section.items.filter { session.result(forItemID: $0.id) != nil }.count
                HStack {
                    Text(section.title)
                        .font(.headline)
                    Spacer()
                    Text("\(sectionRun)/\(section.items.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("\(sectionRun) of \(section.items.count) run")
                }
                .accessibilityElement(children: .combine)
                // On the label, not the DisclosureGroup: an identifier on the
                // group would override every item row's own identifier.
                .accessibilityIdentifier("feedbackkit.checklist.section.\(section.id)")
            }
        }
    }

    private func savedSessionCard(_ saved: TestSession) -> some View {
        let progress = saved.checklistProgress()
        return VStack(alignment: .leading, spacing: 8) {
            Text("Saved session in progress")
                .font(.subheadline.weight(.semibold))
            Text(saved.name)
                .accessibilityIdentifier("feedbackkit.savedSessionNameLabel")
            if let progress {
                Text("\(progress.run) of \(progress.total) run")
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("feedbackkit.savedSessionProgressLabel")
            }
            HStack {
                Button("Resume") {
                    session = saved
                    savedSession = nil
                    resultsVersion += 1
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("feedbackkit.resumeSessionButton")
                Button("Start new", role: .destructive) {
                    store?.delete(id: saved.id)
                    savedSession = nil
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Deletes the saved session")
                .accessibilityIdentifier("feedbackkit.startNewSessionButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(12)
    }

    private func expansionBinding(for sectionID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSectionIDs.contains(sectionID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedSectionIDs.remove(sectionID)
                } else {
                    collapsedSectionIDs.insert(sectionID)
                }
            }
        )
    }

    private func notesBinding(for item: TestChecklistItem, in session: TestSession) -> Binding<String> {
        Binding(
            get: { session.result(forItemID: item.id)?.notes ?? "" },
            set: { newValue in
                session.updateNotes(forItemID: item.id, notes: newValue)
                store?.save(session)
                notesVersion += 1
            }
        )
    }

    /// Looks once (on first appearance) for a saved in-progress session for
    /// this checklist, to offer resuming it, and pre-fills the session name.
    private func checkForSavedSession() {
        guard !didCheckForSavedSession, let checklist, let store else { return }
        didCheckForSavedSession = true
        if sessionName.isEmpty {
            sessionName = checklist.title
        }
        if session == nil {
            savedSession = store.latestSession(for: checklist)
        }
    }

    /// Call after every mutation of `session`: redraws, rebuilds the report,
    /// and (checklist mode) saves the session so a relaunch can restore it.
    private func sessionDidChange() {
        resultsVersion += 1
        if let store, let session {
            store.save(session)
        }
    }

    private func clearSession(_ cleared: TestSession) {
        store?.delete(id: cleared.id)
        session = nil
        scenarioName = ""
        notes = ""
        if let checklist {
            sessionName = checklist.title
        }
        resultsVersion += 1
    }

    // MARK: - Attachment strip

    @ViewBuilder
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    attachmentThumbnail(for: attachment)
                }

                if attachments.count < Self.maxAttachments {
                    Button {
                        showingAddAttachmentDialog = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 60, height: 60)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .accessibilityIdentifier("feedbackkit.addAttachmentButton")
                }
            }
        }
    }

    private func attachmentThumbnail(for attachment: FeedbackAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                markupAttachmentID = attachment.id
            } label: {
                Image(uiImage: attachment.displayImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityIdentifier("feedbackkit.attachmentThumbnail.\(attachment.id)")

            Button {
                removeAttachment(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .accessibilityIdentifier("feedbackkit.removeAttachmentButton.\(attachment.id)")
            .offset(x: 6, y: -6)
        }
    }

    /// Bridges `markupAttachmentID` (an ID, so it survives array mutation) to a
    /// `Binding<FeedbackAttachment>` for the markup sheet's `item:` presentation,
    /// which needs a concrete `Identifiable` value rather than just an ID.
    private var markupBinding: Binding<FeedbackAttachment?> {
        Binding<FeedbackAttachment?>(
            get: {
                guard let id = markupAttachmentID else { return nil }
                return attachments.first(where: { $0.id == id })
            },
            set: { newValue in
                guard let newValue, let index = attachments.firstIndex(where: { $0.id == newValue.id }) else {
                    markupAttachmentID = nil
                    return
                }
                attachments[index] = newValue
            }
        )
    }

    /// A stable `Binding<FeedbackAttachment>` for a given id, used to hand the
    /// markup sheet a two-way binding into `attachments` (so its "Done" button
    /// can write the flattened image straight back into the array). Falls back
    /// to a throwaway binding if the id is somehow no longer present (e.g. the
    /// row was removed just as the sheet was dismissing).
    private func binding(for id: FeedbackAttachment.ID) -> Binding<FeedbackAttachment> {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else {
            return Binding(
                get: { FeedbackAttachment(original: UIImage()) },
                set: { _ in }
            )
        }
        return $attachments[index]
    }

    private func removeAttachment(_ attachment: FeedbackAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        buildReport()
    }

    private func captureCurrentScreen() {
        guard attachments.count < Self.maxAttachments else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })
        else { return }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.layer.render(in: UIGraphicsGetCurrentContext()!)
        }

        attachments.append(FeedbackAttachment(original: image))
        buildReport()
    }

    @MainActor
    private func addAttachmentFromPhotoPicker(_ item: PhotosPickerItem) async {
        guard attachments.count < Self.maxAttachments else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }

        attachments.append(FeedbackAttachment(original: image))
        buildReport()
    }

    // MARK: - Report + share payload

    private func record(_ result: TestResult, in session: TestSession) {
        guard !scenarioName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        session.recordResult(scenarioName: scenarioName, result: result, notes: notes.isEmpty ? nil : notes)
        scenarioName = ""
        notes = ""
        sessionDidChange()
    }

    /// Rebuilds the report text plus the full share payload (report file +
    /// one PNG per attachment) fresh. Called whenever anything that feeds
    /// the share sheet changes (logs/results via `resultsVersion`, or the
    /// attachment list/markup) so the share sheet always reflects current
    /// state rather than a stale snapshot.
    private func buildReport() {
        let bundler = BugReportBundler(
            deviceInfoSummary: { DeviceInfoProvider().summary() },
            testSession: session
        )
        let text = bundler.build()
        reportText = text

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedbackkit-bug-report-\(timestamp).txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        reportFileURL = fileURL

        var items = [fileURL]
        for (index, attachment) in attachments.enumerated() {
            guard let pngData = attachment.displayImage.pngData() else { continue }
            let attachmentURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("feedbackkit-attachment-\(timestamp)-\(index).png")
            do {
                try pngData.write(to: attachmentURL, options: .atomic)
                items.append(attachmentURL)
            } catch {
                // Skip this attachment's file rather than failing the whole share payload.
            }
        }
        shareItems = items
    }
}
#endif
