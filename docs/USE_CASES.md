# Use Cases

## Who uses FeedbackKit

FeedbackKit is a developer-facing SDK for any mobile app team that wants two related capabilities without building their own infrastructure or standing up a backend:

1. An in-app "send diagnostic logs to a developer" path — a lightweight bug-report mechanism.
2. A way for a QA tester to run through a set of test scenarios *inside the app under test* and produce a structured pass/fail results report alongside the diagnostic logs.

The people who *feel* its effect are the app's own testers, QA engineers, and end users — anyone who needs to hand over context about what happened, without needing a debugger, terminal, or backend attached.

Primary persona: **the integrating app developer** — drops in a ring-buffer logger and (optionally) a test-session recorder, calls them from existing code paths, and exposes a share action, without writing platform share-sheet plumbing or a results-reporting format themselves.

Secondary persona: **a QA tester or end user of the host app** — either hits a bug and wants to hand over logs, or is deliberately working through a test plan and needs to record/export what passed and what didn't, all from inside the app.

## Core use cases

### 1. Log during normal app operation
The host app calls `Logger.debug/info/warn/error(tag, message)` from its own code (e.g. a network call, a state transition, a background task) during normal operation. Each call is buffered in a fixed-capacity ring buffer and mirrored to the platform's native logging (Logcat / os_log), so normal dev tooling still sees everything.
- Supported by: `android/core` `Logger.kt`, `ios/Sources/FeedbackKit/Logger.swift`.
- Status: implemented (both platforms, tests passing).

### 2. Preview a bug report before sending
A user opens the feedback screen and sees a live preview: bundled device/app info (version, OS, model) plus the most recent buffered log lines, rendered as plain text.
- Supported by: `BugReportBundler` (both platforms), `FeedbackScreen` (`android/ui`) / `FeedbackView` (`ios/Sources/FeedbackKit`).
- Status: iOS verified via a real simulator UI test (`ExampleUITests.testReportPreviewIsVisible`, part of `docs/TASKS.md`'s testing plan); Android implemented but not yet UI-tested.

### 3. Share a bug report as a file attachment
The user taps "send," and the report is written to a temp file and handed to the platform's native share flow (Android: `ACTION_SEND` + `FileProvider`-backed URI; iOS: `ShareLink`) — rebuilt fresh at share time so it reflects the latest logs, not a stale preview.
- Supported by: `FeedbackScreen.kt` (Android), `FeedbackView.swift` (iOS).
- Status: iOS verified via a real simulator UI test (`ExampleUITests.testSendButtonPresentsShareSheet` — confirms the system share sheet actually appears after tapping); Android implemented but not yet UI-tested.

### 4. Integrate into a host app with minimal glue
A team adding FeedbackKit to their own app depends on `android/core` + `android/ui` (Gradle/Maven) or the `ios/` Swift Package (SPM), calls `Logger` from their existing code, and either drops in the provided screen/view as-is or calls `BugReportBundler` directly to build their own UI around it.
- Supported by: the public API surface of `android/core`/`android/ui` and `ios/Sources/FeedbackKit`; packaging (Maven publish / SPM manifest).
- Status: packaging scaffolded; not yet consumed by a real host app.

## QA test-session use cases

A QA tester working through a written test plan (a list of named scenarios, each with expected steps/outcomes) needs a way to record, per scenario, whether it passed — without leaving the app under test or hand-typing results into a separate spreadsheet.

### 5. Start a test session and record scenario results
A tester starts a named `TestSession` (e.g. "Release candidate 1.4 smoke test"), then works through their test plan, recording each scenario as `PASS`, `FAIL`, `SKIP`, or `BLOCKED` with optional free-text notes (e.g. "failed at step 3: button did not respond"). In the provided UI, this is a session-name field + "Start session" button, then a scenario-name/notes field pair with four result buttons.
- Supported by: `TestSession` (both platforms, tests passing) — see [Architecture](ARCHITECTURE.md#test-session-module); `FeedbackScreen`/`FeedbackView` for the UI.
- Status: unit-tested on both platforms; iOS additionally verified via a real simulator UI test walking the full tap flow (`ExampleUITests.testStartSessionAndRecordResult`, `.testRecordResultWithNotesShowsSuffix` — session creation, scenario/notes entry, all four result buttons, the notes-suffix format). Android not yet UI-tested.

### 6. Export a structured test-session report
Once a session is complete (or at any point mid-session), the tester exports a plain-text results report: session name, start time, and every recorded scenario with its result and notes, in a fixed format both platforms produce identically.
- Supported by: `TestSession.exportReport()`.
- Status: implemented and unit-tested on both platforms.

### 7. Combine test-session results with diagnostic logs in one share
Because a test session and the `Logger` ring buffer run concurrently, a tester can share one combined report — scenario pass/fail results *plus* the log lines captured while running them — so a failing scenario's notes ("FAIL: step 3") line up with the actual log output from that moment, without the developer needing to correlate two separate files.
- Supported by: `BugReportBundler` accepting an optional `TestSession`, appending a test-session section to the standard bug report (see `spec/TEST_SESSION_FORMAT.md`); the provided `FeedbackScreen`/`FeedbackView` builds the combined report automatically whenever a session is active.
- Status: unit-tested on both platforms (including a test confirming `build()`'s output is unchanged when no session is supplied); iOS additionally verified via a real simulator UI test confirming the merged section actually appears in the on-screen preview (`ExampleUITests.testRecordedResultAppearsInSharedReportPreview`). Android not yet UI-tested.

### 8. Resume or reference a prior session's scope
A tester re-running a subset of a test plan (e.g. only regression-testing the scenarios that failed last time) starts a fresh `TestSession` scoped to just those scenarios — sessions are lightweight and disposable, not a persistent test-management system (see Non-goals).
- Supported by: `TestSession`'s constructor (a session is just a name + an in-memory list; nothing prevents starting a new one per run).
- Status: implemented (a direct consequence of `TestSession`'s design — no dedicated code needed).

## Non-goals (as currently understood)

- **Crash reporting / persistence across process death.** The ring buffer and any in-progress test session are in-memory only by design — this is a "hand over what's happening right now" tool, not a Crashlytics/Sentry replacement or a test-management system.
- **A backend, dashboard, or test-case management system.** Reports (bug reports and test-session reports alike) are shared via the OS share sheet to whatever destination the user picks; FeedbackKit never talks to a server, never stores historical session results, and doesn't replace a real test-case management tool (TestRail, Zephyr, etc.) — it produces a report a human pastes into one, or attaches to a ticket.
- **Structured/remote log ingestion or analytics.** No network calls, no analytics pipeline — everything happens on-device until the user explicitly shares.
- **Defining or validating the test plan itself.** FeedbackKit records whatever scenario names/results the host app or tester gives it — it has no opinion on what a "test plan" contains, no built-in scenario library, and doesn't verify that recorded steps were actually followed.
- **A shared iOS/Android runtime.** As decided in [Architecture](ARCHITECTURE.md#architectural-rule-ios-is-a-native-swift-package-not-a-kmp-target), iOS is a separate native Swift implementation, not a KMP-shared binary — this is deliberate, not a gap to "fix" later.
