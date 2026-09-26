# Use Cases

## Who uses FeedbackKit

FeedbackKit is a developer-facing SDK: it's integrated by mobile app teams (starting with Presence) who want an in-app "send logs to a developer" path without shipping their own logging/bug-report infrastructure or standing up a backend. The people who *feel* its effect are the app's own testers and end users, who get a lightweight way to hand over diagnostic context when something goes wrong.

Primary persona: **the integrating app developer** — needs to drop in a ring-buffer logger, call it from existing code paths, and expose a share action, without writing platform share-sheet plumbing themselves.

Secondary persona: **a tester or end user of the host app** — hits a bug, opens the feedback screen, and shares a report to a developer (email, Slack, AirDrop, whatever their share sheet offers) without needing adb, Xcode, or a terminal attached.

## Core use cases

### 1. Log during normal app operation
The host app calls `Logger.debug/info/warn/error(tag, message)` from its own code (e.g. a BLE callback, a network call) during normal operation. Each call is buffered in a fixed-capacity ring buffer and mirrored to the platform's native logging (Logcat / os_log), so normal dev tooling still sees everything.
- Supported by: `android/core/Logger.kt` (commonMain + androidMain), `ios/Sources/FeedbackKit/Logger.swift`.
- Status: not started — to be ported from Presence's `PresenceLogger`.

### 2. Preview a bug report before sending
A user opens the feedback screen and sees a live preview: bundled device/app info (version, OS, model) plus the most recent buffered log lines, rendered as plain text.
- Supported by: `BugReportBundler` (both platforms), `FeedbackScreen`/`FeedbackView`.
- Status: not started.

### 3. Share a bug report as a file attachment
The user taps "send," and the report is written to a temp file and handed to the platform's native share flow (Android: `ACTION_SEND` + `FileProvider`-backed URI with `ClipData` for a rich Sharesheet preview; iOS: `ShareLink`) — rebuilt fresh at share time so it reflects the latest logs, not a stale preview.
- Supported by: `FeedbackScreen.kt` (Android), `FeedbackView.swift` (iOS).
- Status: not started.

### 4. Integrate into a host app with minimal glue
A team adding FeedbackKit to their own app depends on `android/core` (Gradle/Maven) or the `ios/` Swift Package (SPM), calls `Logger` from their existing code, and either drops in the provided screen/view as-is or calls `BugReportBundler` directly to build their own UI around it.
- Supported by: the public API surface of `android/core` and `ios/Sources/FeedbackKit`; packaging (Maven publish / SPM manifest).
- Status: not started.

## Non-goals (as currently understood)

- **Crash reporting / persistence across process death.** The ring buffer is in-memory only by design — this is a "hand over what's happening right now" tool, not a Crashlytics/Sentry replacement.
- **A backend or dashboard.** Reports are shared via the OS share sheet to whatever destination the user picks (email, chat, AirDrop); FeedbackKit never talks to a server itself.
- **Structured/remote log ingestion.** No network calls, no analytics pipeline — everything happens on-device until the user explicitly shares.
- **A shared iOS/Android runtime.** As decided in [Architecture](ARCHITECTURE.md#architectural-rule-ios-is-a-native-swift-package-not-a-kmp-target), iOS is a separate native Swift implementation, not a KMP-shared binary — this is deliberate, not a gap to "fix" later.
