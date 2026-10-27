#if os(iOS)
import SwiftUI
import PhotosUI
import UIKit

/// Drop-in feedback screen: previews + shares a bug report (device info +
/// recent Logger lines), and optionally lets a QA tester run a named test
/// session -- recording PASS/FAIL/SKIP/BLOCKED results per scenario --
/// merged into the same shared report. A host app can use this as-is, or
/// call `BugReportBundler`/`TestSession` directly to build its own UI.
public struct FeedbackView: View {
    private static let maxAttachments = 5

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

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Test session")
                    .font(.headline)

                if let session {
                    Text(session.name)
                        .accessibilityIdentifier("feedbackkit.sessionNameLabel")

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

                    Text("Recorded results")
                        .font(.subheadline)
                    // Reads resultsVersion so this redraws after each recordResult call --
                    // TestSession itself isn't an ObservableObject, it's a plain accumulator.
                    let _ = resultsVersion
                    ForEach(Array(session.results().enumerated()), id: \.offset) { index, entry in
                        let notesSuffix = (entry.notes?.isEmpty == false) ? " — \(entry.notes!)" : ""
                        Text("[\(entry.result.rawValue)] \(entry.scenarioName)\(notesSuffix)")
                            .accessibilityIdentifier("feedbackkit.resultRow.\(index)")
                    }
                } else {
                    TextField("Session name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("feedbackkit.sessionNameField")
                    Button("Start session") {
                        if !sessionName.trimmingCharacters(in: .whitespaces).isEmpty {
                            session = TestSession(name: sessionName)
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
        .onAppear { buildReport() }
        .onChange(of: resultsVersion) { _ in buildReport() }
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
        resultsVersion += 1
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
