#if os(iOS)
import SwiftUI

/// Drop-in feedback screen: previews + shares a bug report (device info +
/// recent Logger lines), and optionally lets a QA tester run a named test
/// session -- recording PASS/FAIL/SKIP/BLOCKED results per scenario --
/// merged into the same shared report. A host app can use this as-is, or
/// call `BugReportBundler`/`TestSession` directly to build its own UI.
public struct FeedbackView: View {
    @State private var sessionName = ""
    @State private var session: TestSession?
    @State private var scenarioName = ""
    @State private var notes = ""
    @State private var resultsVersion = 0
    @State private var reportFileURL: URL?
    @State private var reportText = ""

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

                if let url = reportFileURL {
                    ShareLink(item: url) {
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
    }

    private func record(_ result: TestResult, in session: TestSession) {
        guard !scenarioName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        session.recordResult(scenarioName: scenarioName, result: result, notes: notes.isEmpty ? nil : notes)
        scenarioName = ""
        notes = ""
        resultsVersion += 1
    }

    private func buildReport() {
        let bundler = BugReportBundler(
            deviceInfoSummary: { DeviceInfoProvider().summary() },
            testSession: session
        )
        let text = bundler.build()
        reportText = text

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedbackkit-bug-report-\(Int(Date().timeIntervalSince1970)).txt")
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        reportFileURL = fileURL
    }
}
#endif
