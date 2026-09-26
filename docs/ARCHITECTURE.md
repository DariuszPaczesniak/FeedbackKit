# Architecture

## Architectural rule: iOS is a native Swift Package, not a KMP target

**The iOS implementation lives entirely in `ios/` as a standalone Swift Package. It never depends on a Kotlin Multiplatform-produced `.xcframework`, and the `android/core` KMP module never declares an iOS target.**

The original Presence implementation shared one Kotlin Multiplatform module across both platforms (`iosMain`/`androidMain` actuals bridged into Swift via a Kotlin/Native `.xcframework`). For FeedbackKit, iOS is deliberately re-implemented in pure Swift instead of reusing that KMP build:

- A pure SPM package is trivially consumable by any iOS app (`.package(url:)`, Xcode's "Add Package Dependency") without that app or its build pipeline needing to know Kotlin/Native, Gradle, or cinterop exist.
- It avoids Kotlin/Native's real interop rough edges hit in Presence's own codebase (boxed numeric types crossing the Swift/Kotlin bridge, `NSLog`'s C-variadic signature segfaulting from Kotlin/Native, cinterop failing to read headers from inside `Xcode.app`) — none of that risk surface applies to a project with no Kotlin/Native step at all.
- It keeps the iOS package's release cadence and Swift-version compatibility independent of the Android/Gradle toolchain's release cadence.

What **is** shared between platforms is the *design*, not the runtime code: the `spec/` directory holds the bug-report text format and ring-buffer behavioral contract as prose/pseudocode both implementations must match, and each platform has its own test suite asserting conformance to it. There is no code-sharing mechanism enforcing this — it's convention-and-spec-enforced today (see "Known structural inconsistencies" below), verified by each platform's own tests against `spec/REPORT_FORMAT.md`.

```
spec/  (language-agnostic: report format, ring buffer semantics)
  |
  +---> android/core (Kotlin, KMP: commonMain + androidMain only)
  |
  +---> ios/ (Swift Package, standalone)
```

Rules that follow from this:

1. Never add an `iosMain`/`iosArm64()`/etc. target to `android/core`'s Gradle build — if iOS needs Kotlin code, that's a sign the spec is out of sync, not a reason to reach for KMP's iOS support.
2. A behavior change to the report format or ring buffer must update `spec/` first, then be ported to both `android/core` and `ios/Sources/FeedbackKit` as two separate, reviewed changes.
3. The Swift package has zero dependency on anything under `android/` — no shared build files, no generated bindings.

## Overview

Both platforms implement the same four pieces:

- **`Logger`** — a fixed-capacity ring buffer of log lines, each mirrored to the platform's native logging.
- **`DeviceInfo`** — reads app version + OS version + device model from the platform SDK (`PackageManager`/`Build` on Android; `Bundle`/`UIDevice` on iOS).
- **`BugReportBundler`** — pure function of `(deviceInfoSummary: () -> String, now: () -> Long/Date, testSession: TestSession?)` → formatted report text, so it's unit-testable without a real `Context`/`UIDevice`.
- **`TestSession`** — an in-memory, ordered list of named test-scenario results a QA tester records while working through a test plan, exportable standalone or merged into a `BugReportBundler` report.

A thin platform UI (`FeedbackScreen`/`FeedbackView`) previews the report and triggers the native share flow (`Intent.ACTION_SEND` + `FileProvider` on Android; `ShareLink` on iOS), writing the report to a temp file first so it shares as a real file attachment, not inline text.

## Test session module

`TestSession` is a separate, optional concern from `Logger` — a host app or tester who never runs a formal test plan never touches it, and `Logger`/`BugReportBundler` work exactly as before without one.

```
TestSession(name: String, now: () -> Long = epochMillisNow)
  recordResult(scenarioName: String, result: TestResult, notes: String? = null)
  results(): List<TestScenarioResult>   // in recorded order
  exportReport(): String                // per spec/TEST_SESSION_FORMAT.md
  clear()

enum TestResult { PASS, FAIL, SKIP, BLOCKED }

TestScenarioResult (conceptual)
  scenarioName: String
  result: TestResult
  notes: String?
  recordedAtMillis: Long
```

Design decisions:

1. **No capacity cap, unlike `Logger`.** A test plan is a bounded, human-authored list (tens of scenarios, not thousands of log lines) — there's no ring-buffer eviction risk worth the added complexity. If this becomes a real problem for very large test plans, revisit; don't pre-optimize for it now.
2. **`TestSession` doesn't know about `Logger`.** They're independent, composable pieces — `BugReportBundler` is the thing that knows how to combine them (see below), not `TestSession` reaching into `Logger`'s internals. This keeps `TestSession` usable standalone (e.g. a host app that wants scenario tracking but not the log ring buffer).
3. **A session is a plain object, not a singleton.** Unlike `Logger` (one shared ring buffer for the whole app), a caller constructs a `TestSession` per test run and holds onto it — this is what makes "start a fresh session for a re-run" (use case 8) trivial rather than needing an explicit reset-and-hope-nothing-else-is-watching-the-shared-state dance.
4. **`BugReportBundler` takes an optional `TestSession`.** When supplied, `build()` appends a test-session section (per `spec/TEST_SESSION_FORMAT.md`) after the log section, so a single shared report carries both without the caller manually concatenating two strings.

## Module breakdown

### `android/core` (Kotlin Multiplatform: commonMain + androidMain)
- `Logger.kt` (commonMain) — ring buffer, `expect fun platformLog(...)`.
- `Logger.android.kt` (androidMain) — `actual fun platformLog` via `android.util.Log`.
- `DeviceInfo.kt` (commonMain `expect class`) / `DeviceInfo.android.kt` (`actual`, takes a `Context`).
- `BugReportBundler.kt` (commonMain) — report assembly.
- `TestSession.kt` (commonMain, planned) — scenario result recording + export; no platform actuals needed (pure Kotlin, no platform API dependency).

### `android/ui` (Android library, Jetpack Compose — depends on `android:core`)
- `FeedbackScreen.kt` — Compose UI: test-session recording (session name, scenario/notes fields, PASS/FAIL/SKIP/BLOCKED buttons, recorded-results list) + bug-report preview + share button (`ACTION_SEND` via `FileProvider`). Kept in a separate module from `android/core` so a consumer that only wants `Logger`/`BugReportBundler`/`TestSession` (no Compose dependency) isn't forced to pull in Compose.
- `AndroidManifest.xml` — declares the `FileProvider` (`${applicationId}.feedbackkit.fileprovider`) a host app's manifest merges in automatically; `res/xml/feedbackkit_file_paths.xml` scopes it to a `feedbackkit-reports/` cache subdirectory.

### `ios/Sources/FeedbackKit`
- `Logger.swift` — ring buffer + `os_log`/`print` mirroring.
- `DeviceInfo.swift` — reads `Bundle.main` + `UIDevice.current`.
- `BugReportBundler.swift` — report assembly, mirroring `android/core`'s output shape per `spec/REPORT_FORMAT.md`.
- `TestSession.swift` (planned) — scenario result recording + export, mirroring `android/core`'s `TestSession.kt` per `spec/TEST_SESSION_FORMAT.md`.
- `FeedbackView.swift` — SwiftUI: same test-session recording UI + bug-report preview + `ShareLink`, gated behind `#if os(iOS)` (the package has no macOS platform floor, and `ShareLink`'s `Transferable` conformance needs iOS 16/macOS 13 — since this view is iOS-only by design anyway, gating it lets `swift test` still build/run cleanly on the host Mac without pulling in an unwanted macOS platform requirement).

### `spec/`
- `REPORT_FORMAT.md` — exact text layout of a bundled report (header, device info block, log section) so both platforms produce byte-for-byte comparable output for a given input.
- `BEHAVIOR.md` — ring buffer capacity, eviction order, thread-safety expectations (deliberately not thread-safe on either platform — a diagnostic aid, not a system of record).
- `TEST_SESSION_FORMAT.md` — exact text layout of an exported test-session report, and how it merges into a `BugReportBundler` report.

## Data model detail

```
LogEntry (conceptual, not a shared class)
  timestampMillis: Int64
  level: DEBUG | INFO | WARN | ERROR
  tag: String
  message: String

BugReport (conceptual — the bundler's output is plain text, not a structured type)
  header: "=== FeedbackKit bug report ==="
  generatedAtMillis: Int64
  deviceInfoSummary: String   // multi-line, platform-specific fields
  logCount: Int
  logLines: String            // ring buffer contents, oldest first, newline-joined
  testSessionSection: String? // present only when a TestSession was supplied

TestScenarioResult (conceptual)
  scenarioName: String
  result: PASS | FAIL | SKIP | BLOCKED
  notes: String?
  recordedAtMillis: Int64
```

Both platforms format `LogEntry` as `"{timestampMillis} [{LEVEL}] {tag}: {message}"` — this exact shape lives in `spec/REPORT_FORMAT.md`, not just in code, so a diff between platforms is checkable without reading both languages side by side. `TestScenarioResult`'s export line format lives in `spec/TEST_SESSION_FORMAT.md`, same reasoning.

## Cross-cutting concerns

- **Persistence:** none — the ring buffer and any in-progress `TestSession` are in-memory only and are lost on process death by design; this is a live-session diagnostic aid, not a crash reporter or a test-management system.
- **Concurrency:** `Logger` is deliberately not thread-safe on either platform — worst case under concurrent logging is an occasionally dropped/out-of-order line, acceptable for this use case. `TestSession` is expected to be driven from a single (usually UI) thread by a human tester working through scenarios one at a time, so the same tradeoff applies without a distinct new risk. Revisit either if a consumer needs stronger guarantees.
- **Testing:** `Logger`, `BugReportBundler`, and `TestSession` are unit-testable via injected dependencies (`deviceInfoSummary`, `now`) on both platforms, with passing test suites (17 Kotlin tests, 16 Swift tests). The UI layer has real, automated interaction tests on iOS (`ios/Example`'s `ExampleUITests`, an XCUITest suite run against a real simulator — see `docs/TASKS.md`'s testing plan for the full use-case-to-test mapping); Android's UI layer (`FeedbackScreen`) doesn't have an equivalent Compose UI test suite yet.

## Known structural inconsistencies

- The Android/KMP and Swift implementations are two independently-maintained codebases with no compiler-enforced parity — `spec/` is the only thing keeping them in sync. Both `spec/REPORT_FORMAT.md` and `spec/TEST_SESSION_FORMAT.md` have passing conformance tests on both platforms.
- iOS's UI layer has a real simulator-driven test suite (`ios/Example`/`ExampleUITests`); Android's (`FeedbackScreen`, Compose) doesn't have an equivalent yet — see [Tasks](TASKS.md)'s testing plan.
