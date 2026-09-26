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

Both platforms implement the same three pieces:

- **`Logger`** (Android: `PresenceLogger`-derived object; iOS: a Swift `enum`/`final class` namespace) — a fixed-capacity ring buffer of log lines, each mirrored to the platform's native logging.
- **`DeviceInfo`** — reads app version + OS version + device model from the platform SDK (`PackageManager`/`Build` on Android; `Bundle`/`UIDevice` on iOS).
- **`BugReportBundler`** — pure function of `(deviceInfoSummary: () -> String, now: () -> Long/Date)` → formatted report text, so it's unit-testable without a real `Context`/`UIDevice`.

A thin platform UI (`FeedbackScreen`/`FeedbackView`) previews the report and triggers the native share flow (`Intent.ACTION_SEND` + `FileProvider` on Android; `ShareLink` on iOS), writing the report to a temp file first so it shares as a real file attachment, not inline text.

## Module breakdown

### `android/core` (Kotlin Multiplatform: commonMain + androidMain)
- `Logger.kt` (commonMain) — ring buffer, `expect fun platformLog(...)`.
- `Logger.android.kt` (androidMain) — `actual fun platformLog` via `android.util.Log`.
- `DeviceInfo.kt` (commonMain `expect class`) / `DeviceInfo.android.kt` (`actual`, takes a `Context`).
- `BugReportBundler.kt` (commonMain) — report assembly.

### `android/app` (or a sample app, once it exists)
- `FeedbackScreen.kt` — Compose UI: preview + share button (`ACTION_SEND` via `FileProvider`).

### `ios/Sources/FeedbackKit`
- `Logger.swift` — ring buffer + `os_log`/`print` mirroring.
- `DeviceInfo.swift` — reads `Bundle.main` + `UIDevice.current`.
- `BugReportBundler.swift` — report assembly, mirroring `android/core`'s output shape per `spec/REPORT_FORMAT.md`.
- `FeedbackView.swift` — SwiftUI: preview + `ShareLink`.

### `spec/`
- `REPORT_FORMAT.md` — exact text layout of a bundled report (header, device info block, log section) so both platforms produce byte-for-byte comparable output for a given input.
- `BEHAVIOR.md` — ring buffer capacity, eviction order, thread-safety expectations (deliberately not thread-safe on either platform — a diagnostic aid, not a system of record).

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
```

Both platforms format `LogEntry` as `"{timestampMillis} [{LEVEL}] {tag}: {message}"` — this exact shape lives in `spec/REPORT_FORMAT.md`, not just in code, so a diff between platforms is checkable without reading both languages side by side.

## Cross-cutting concerns

- **Persistence:** none — the ring buffer is in-memory only and is lost on process death by design; this is a live-session diagnostic aid, not a crash reporter.
- **Concurrency:** deliberately not thread-safe on either platform, matching Presence's original tradeoff — worst case under concurrent logging is an occasionally dropped/out-of-order line, acceptable for this use case. Revisit if a consumer needs stronger guarantees.
- **Testing:** `BugReportBundler` and `Logger` are unit-testable via injected dependencies (`deviceInfoSummary`, `now`) on both platforms; the UI layers are not covered by automated tests yet (manual test cases only, inherited from Presence's `docs/manual-test-cases.md` convention).

## Known structural inconsistencies

- The Android/KMP and Swift implementations are two independently-maintained codebases with no compiler-enforced parity — `spec/` is the only thing keeping them in sync, and it doesn't exist yet (tracked in [Tasks](TASKS.md)). Until it's written and both platforms have tests asserting conformance to it, "shared behavior" is aspirational, not verified.
- Neither `android/` nor `ios/` has been extracted from Presence yet — this repo currently holds only planning docs.
