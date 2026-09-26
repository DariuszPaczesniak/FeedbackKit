# FeedbackKit

FeedbackKit is a standalone bug-report and QA test-session SDK for mobile apps. It bundles device/app metadata with an in-memory ring buffer of recent log lines into one plain-text report, and hands that report to the platform's native share sheet so a tester or user can send it to a developer directly from the app — no debugger, terminal, or backend attached. It also lets a QA tester record structured pass/fail results for a set of test scenarios from inside the app under test, and export those results (optionally alongside the diagnostic logs) as one shareable report. It started as an extraction from a specific app's feedback screen, generalized so any app can reuse the same capability without depending on that app.

## Documentation

- [Use Cases](USE_CASES.md) — who uses this and the core scenarios it supports
- [Architecture](ARCHITECTURE.md) — module layout, data model, and key technical decisions
- [Tasks](TASKS.md) — what's implemented, what's stubbed out, and what's left to build

## Core idea

1. **`Logger`** — an in-memory ring buffer that apps write log lines to during normal operation; it mirrors every line to the platform's own logging (Logcat / os_log) so nothing is lost from normal dev tooling.
2. **`DeviceInfo`** — a small platform-metadata snapshot (app version, OS version, device model).
3. **`BugReportBundler`** — combines the two into one plain-text report, generated fresh at share time so it always reflects the latest state.
4. **`TestSession`** — an in-memory, ordered list of named test-scenario results (pass/fail/skip/blocked + notes) that a QA tester records while working through a test plan inside the app, exportable on its own or merged into a `BugReportBundler` report so results and logs line up.
5. A thin platform UI layer (a screen/view + a share action) that a host app drops in as-is, or bypasses to call the bundler/session APIs directly and wire up its own UI.

## Tech stack

- **Android + shared core logic:** Kotlin, packaged as a Kotlin Multiplatform library (published as an Android artifact; the `commonMain` source set exists so future non-iOS platforms — e.g. desktop/JVM — can reuse the core logic, but this project does **not** use KMP's iOS target).
- **iOS:** Swift, packaged as a standalone Swift Package (SPM) — a separate, pure-Swift reimplementation of the same behavior, not a Kotlin/Native framework. See [Architecture: why two implementations](ARCHITECTURE.md#architectural-rule-ios-is-a-native-swift-package-not-a-kmp-target) for why.
- **Testing:** Kotlin `kotlin.test` for the Android/shared side; XCTest for the Swift package.

## Repository layout

```
android/                   Kotlin (JVM + Android) module: Logger, DeviceInfo, BugReportBundler, TestSession, FeedbackScreen (Compose)
  core/                     Kotlin Multiplatform library (commonMain + androidMain); publishable as a Maven artifact
ios/                        Swift Package: FeedbackKit target (native Swift, no KMP dependency)
  Sources/FeedbackKit/      Logger, DeviceInfo, BugReportBundler, TestSession, FeedbackView (SwiftUI)
  Tests/FeedbackKitTests/
spec/                       Shared, language-agnostic design notes both platforms implement against
  REPORT_FORMAT.md           The bug-report text layout/wire format
  BEHAVIOR.md                 Ring buffer semantics, size limits, thread-safety expectations
  TEST_SESSION_FORMAT.md      The test-session results text layout/wire format
docs/                       This documentation
```

`android/core` and `ios/` are scaffolded with `Logger`/`DeviceInfo`/`BugReportBundler` (tests passing); `TestSession` and the UI layers are tracked in [Tasks](TASKS.md), not yet built.
