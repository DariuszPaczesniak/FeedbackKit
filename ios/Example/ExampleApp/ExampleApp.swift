import SwiftUI
import FeedbackKit

/// Launch arguments (used by ExampleUITests; also settable via Xcode's
/// scheme editor to try the checklist flow by hand):
/// - `-sampleChecklist`: run `SampleChecklist.json` instead of free-form.
/// - `-resetSavedSessions`: delete saved test sessions before showing the UI.
@main
struct ExampleApp: App {
    private let checklist: TestChecklist?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSavedSessions") {
            TestSessionStore().deleteAll()
        }
        if arguments.contains("-sampleChecklist"),
           let url = Bundle.main.url(forResource: "SampleChecklist", withExtension: "json") {
            do {
                checklist = try TestChecklist.load(from: url)
            } catch {
                Logger.error(tag: "ExampleApp", message: error.localizedDescription)
                checklist = nil
            }
        } else {
            checklist = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let checklist {
                FeedbackView(checklist: checklist)
            } else {
                // The original zero-argument call, kept literally so this app
                // keeps proving existing `FeedbackView()` call sites compile.
                FeedbackView()
            }
        }
    }
}
