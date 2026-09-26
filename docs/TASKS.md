This is a snapshot based on the project kickoff interview, a read of the originating app's existing feedback code, and a follow-up design pass adding the QA test-session feature, as of 2026-09-26. It's meant to be updated as work progresses — treat it as a living checklist, not a permanent record.

## Done

- [x] Project docs bootstrapped (`docs/README.md`, `ARCHITECTURE.md`, `USE_CASES.md`, `TASKS.md`) and git repo initialized at `/Users/darius/Developer/FeedbackKit`.
- [x] **`spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — captured exact report text layout and ring-buffer semantics from Presence, both platforms now have one written contract to implement against.
- [x] **`android/core` scaffolded and extraction complete** — Kotlin Multiplatform module (commonMain + androidMain, no iOS target per the architectural rule), all sources ported from `presence/shared/src/{commonMain,androidMain}/kotlin/com/presence/shared/logging/`, tests passing on `testDebugUnitTest`.
- [x] **`ios/` Swift Package scaffolded and extraction complete** — pure Swift implementations (no Kotlin/Native bridge) of `Logger`, `DeviceInfo`, `BugReportBundler`, matching behavior exactly per spec files, with XCTest suites (buildable via Xcode or `swift build -Xswiftc -sdk ...`).

## Initial extraction (bug report + logging)

Goal: get the existing, working feedback functionality (originally built inside the Presence app) out into this standalone repo without behavior regressions, as two independent platform implementations.

- [x] **Write `spec/REPORT_FORMAT.md` and `spec/BEHAVIOR.md`** — captured the exact report text layout and ring-buffer semantics (capacity 500, eviction order, thread-safety non-guarantee) from the originating implementation before porting any code, so both platforms have one source of truth to implement against.
- [x] **Scaffold `android/core`** — new Gradle module (Kotlin Multiplatform, `commonMain` + `androidMain` only, no iOS target per the architectural rule), ported from the originating app's shared logging module.
- [x] **Scaffold `ios/`** — new standalone Swift Package (SPM manifest, `FeedbackKit` target), reimplemented `Logger`/`DeviceInfo`/`BugReportBundler` in pure Swift from the originating app's iOS actuals and shared logic — **not** generated or copied from a KMP `.xcframework`.
- [x] **Tests** — ported the Kotlin `kotlin.test` suite to `android/core` (passing on `testDebugUnitTest`), and wrote an equivalent XCTest suite for the Swift package, both asserting conformance to `spec/REPORT_FORMAT.md`.
- [x] **Packaging** — created `Package.swift` manifest for `ios/` (ready for SPM consumption); `android/core`/build.gradle.kts has the foundation for Maven publish config (not yet configured for actual upload).
- [ ] **Port the UI layer** — Compose `FeedbackScreen` for Android, SwiftUI `FeedbackView` for iOS, adapted to call the new standalone packages instead of `PresenceShared`.
- [ ] **Wire Presence itself back up** — once UI layers are ported and both packages verified equivalent on real devices, switch Presence's own `FeedbackView.swift`/`FeedbackScreen.kt` to depend on this repo instead of its inline `com.presence.shared.logging` code, so there's exactly one place implementing this behavior going forward.

## QA test-session feature

Goal: let a QA tester record structured pass/fail results for named test scenarios from inside the app under test, and export those results standalone or merged into a bug report. Design is written; nothing is implemented yet.

- [x] **Write `spec/TEST_SESSION_FORMAT.md`** — API contract (`TestSession`/`TestResult`/`recordResult`/`exportReport`), behavior (no capacity cap, single-writer thread-safety expectation, session identity), and exact exported-text format, both standalone and merged into a `BugReportBundler` report.
- [ ] **Implement `TestSession` in `android/core`** (`TestSession.kt`, commonMain — no platform actuals needed, pure Kotlin) — `recordResult`, `results()`, `exportReport()`, `clear()`, per the spec.
- [ ] **Implement `TestSession` in `ios/Sources/FeedbackKit`** (`TestSession.swift`) — same API surface, pure Swift, per the spec.
- [ ] **Wire `TestSession` into `BugReportBundler`** on both platforms — add the optional `testSession` constructor parameter, append the merged section per `spec/TEST_SESSION_FORMAT.md`, and confirm `build()`'s output is unchanged when no session is supplied (additive, not breaking).
- [ ] **Tests** — a `TestSessionTest`/`TestSessionTests` suite on each platform (recording order, notes formatting, empty-session export, `clear()` behavior), plus new `BugReportBundler` tests covering the merged-section behavior, both asserting conformance to `spec/TEST_SESSION_FORMAT.md`.
- [ ] **UI hook** — once the platform UI layers exist (see below), add a minimal way for a tester to start a session, record a result per scenario, and trigger export/share — doesn't need to be fancy (a scenario name field + four result buttons + notes field is enough to start).

## UI layer and integration

- [ ] **Port the UI layer** — Compose `FeedbackScreen` for Android, SwiftUI `FeedbackView` for iOS: preview + share for the bug report, extended per the QA UI hook above once `TestSession` exists.
- [ ] **Verify on real devices** — run both the Android app and iOS app with the new packages, confirm logs are collected, test sessions record correctly, and reports bundle/share correctly.
- [ ] **Wire the originating app back up** — once both packages exist and are verified equivalent, switch the original app's feedback screen to depend on this repo instead of its inline logging code, so there's exactly one place implementing this behavior going forward.

## Not started (planned)

- [ ] Sample/demo app per platform showing minimal integration (bug report + test session).
- [ ] Localization strings (the originating app currently uses `String(localized:)`/`stringResource` — FeedbackKit should decide whether to ship default strings or require the host app to supply them).

## Suggested near-term priorities

1. **Implement `TestSession` on both platforms** (`android/core`, `ios/Sources/FeedbackKit`) with tests — the spec is written and this is self-contained, independent of the UI work.
2. **Wire `TestSession` into `BugReportBundler`** and verify the additive/no-session-unchanged behavior with tests.
3. **Port the UI layer** (`FeedbackScreen.kt`/`FeedbackView.swift`), including the minimal QA test-session UI hook.
4. **Verify on real devices**, then wire the originating app back to depend on this repo.
